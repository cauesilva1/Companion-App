import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Spotify Web API — currently playing (único caminho público no iPhone para Spotify).
@MainActor
final class SpotifyService: NSObject, ObservableObject {
  static let shared = SpotifyService()

  static let redirectURI = "companion://spotify-callback"
  private static let clientIdKey = "companion.spotifyClientId"
  private static let scopes = "user-read-currently-playing user-read-playback-state"

  @Published private(set) var isConnected = false
  @Published private(set) var lastError: String?

  private var authSession: ASWebAuthenticationSession?
  private var presenter = AuthPresenter()
  private var pendingVerifier: String?

  /// Client ID do produto (Info.plist / .env). Usuários finais não digitam isso.
  var clientId: String {
    if let s = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String,
       !s.isEmpty, !s.contains("YOUR_") {
      return s
    }
    // Override local só para dev (opcional)
    if let s = UserDefaults.standard.string(forKey: Self.clientIdKey), !s.isEmpty { return s }
    return ""
  }

  var hasClientId: Bool { !clientId.isEmpty }

  override init() {
    super.init()
    isConnected = KeychainStore.get(.spotifyAccess) != nil || KeychainStore.get(.spotifyRefresh) != nil
  }

  struct Track: Equatable {
    var title: String
    var artist: String?
    var isPlaying: Bool
  }

  func connect() async throws {
    lastError = nil
    guard hasClientId else {
      throw SpotifyError.missingClientId
    }
    let verifier = Self.randomVerifier()
    pendingVerifier = verifier
    let challenge = Self.challengeS256(verifier)
    var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
    comps.queryItems = [
      URLQueryItem(name: "client_id", value: clientId),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
      URLQueryItem(name: "scope", value: Self.scopes),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "show_dialog", value: "true"),
    ]
    guard let url = comps.url else { throw SpotifyError.badURL }

    let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: "companion"
      ) { callback, error in
        if let error {
          cont.resume(throwing: error)
          return
        }
        guard let callback else {
          cont.resume(throwing: SpotifyError.cancelled)
          return
        }
        cont.resume(returning: callback)
      }
      session.presentationContextProvider = self.presenter
      session.prefersEphemeralWebBrowserSession = false
      self.authSession = session
      if !session.start() {
        cont.resume(throwing: SpotifyError.cancelled)
      }
    }

    guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "code" })?.value,
      let verifier = pendingVerifier
    else {
      throw SpotifyError.noCode
    }
    try await exchangeCode(code, verifier: verifier)
    isConnected = true
  }

  func disconnect() {
    KeychainStore.delete(.spotifyAccess)
    KeychainStore.delete(.spotifyRefresh)
    KeychainStore.delete(.spotifyExpires)
    isConnected = false
  }

  func currentlyPlaying() async -> Track? {
    guard let token = await validAccessToken() else { return nil }
    var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse else { return nil }
      if http.statusCode == 204 { return nil }
      if http.statusCode == 401 {
        if let refreshed = await refreshAccessToken() {
          req.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
          let (data2, resp2) = try await URLSession.shared.data(for: req)
          guard let http2 = resp2 as? HTTPURLResponse, http2.statusCode == 200 else {
            if (resp2 as? HTTPURLResponse)?.statusCode == 401 { disconnect() }
            return nil
          }
          return parseTrack(data2)
        }
        disconnect()
        return nil
      }
      guard http.statusCode == 200 else { return nil }
      return parseTrack(data)
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  private func parseTrack(_ data: Data) -> Track? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let isPlaying = json["is_playing"] as? Bool ?? false
    guard let item = json["item"] as? [String: Any] else { return nil }
    let title = item["name"] as? String ?? ""
    guard !title.isEmpty else { return nil }
    let artists = (item["artists"] as? [[String: Any]]) ?? []
    let artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
    return Track(title: title, artist: artist.isEmpty ? nil : artist, isPlaying: isPlaying)
  }

  // MARK: - OAuth helpers

  private func exchangeCode(_ code: String, verifier: String) async throws {
    var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = [
      "client_id": clientId,
      "grant_type": "authorization_code",
      "code": code,
      "redirect_uri": Self.redirectURI,
      "code_verifier": verifier,
    ]
    req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
      .joined(separator: "&")
      .data(using: .utf8)
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
      let msg = String(data: data, encoding: .utf8) ?? "token failed"
      throw SpotifyError.http(msg)
    }
    try saveTokens(from: data)
  }

  private func refreshAccessToken() async -> String? {
    guard let refresh = KeychainStore.get(.spotifyRefresh), hasClientId else { return nil }
    var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let body = [
      "client_id": clientId,
      "grant_type": "refresh_token",
      "refresh_token": refresh,
    ]
    req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
      .joined(separator: "&")
      .data(using: .utf8)
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
      try saveTokens(from: data, keepRefreshIfMissing: refresh)
      return KeychainStore.get(.spotifyAccess)
    } catch {
      return nil
    }
  }

  private func validAccessToken() async -> String? {
    if let expStr = KeychainStore.get(.spotifyExpires),
       let exp = Double(expStr),
       Date().timeIntervalSince1970 < exp - 60,
       let access = KeychainStore.get(.spotifyAccess) {
      return access
    }
    return await refreshAccessToken() ?? KeychainStore.get(.spotifyAccess)
  }

  private func saveTokens(from data: Data, keepRefreshIfMissing: String? = nil) throws {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = json["access_token"] as? String else {
      throw SpotifyError.http("resposta inválida")
    }
    KeychainStore.set(.spotifyAccess, value: access)
    if let refresh = json["refresh_token"] as? String {
      KeychainStore.set(.spotifyRefresh, value: refresh)
    } else if let keep = keepRefreshIfMissing {
      KeychainStore.set(.spotifyRefresh, value: keep)
    }
    let expiresIn = (json["expires_in"] as? Double) ?? 3600
    let exp = Date().timeIntervalSince1970 + expiresIn
    KeychainStore.set(.spotifyExpires, value: String(exp))
  }

  private static func randomVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64URLEncodedString()
  }

  private static func challengeS256(_ verifier: String) -> String {
    let data = Data(verifier.utf8)
    let hash = SHA256.hash(data: data)
    return Data(hash).base64URLEncodedString()
  }
}

enum SpotifyError: LocalizedError {
  case missingClientId
  case badURL
  case cancelled
  case noCode
  case http(String)

  var errorDescription: String? {
    switch self {
    case .missingClientId:
      return "Spotify não embutido neste build — SPOTIFY_CLIENT_ID no .env + sync"
    case .badURL: return "URL Spotify inválida"
    case .cancelled: return "Login Spotify cancelado"
    case .noCode: return "Spotify não devolveu código"
    case .http(let m): return "Spotify: \(m.prefix(120))"
    }
  }
}

private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
      return key
    }
    return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
