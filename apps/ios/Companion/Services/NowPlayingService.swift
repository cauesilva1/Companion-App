import Foundation
import MediaPlayer

/// Now Playing só-leitura (título / artista). Sem play/pause/skip.
@MainActor
final class NowPlayingService: ObservableObject {
  static let shared = NowPlayingService()

  @Published private(set) var title: String?
  @Published private(set) var artist: String?
  @Published private(set) var isPlaying = false

  private static let enabledKey = "companion.nowPlayingEnabled"
  private var timer: Timer?

  static var isEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: enabledKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  var line: String? {
    guard Self.isEnabled, let title, !title.isEmpty else { return nil }
    if let artist, !artist.isEmpty {
      return "\(title) — \(artist)"
    }
    return title
  }

  func start() {
    guard Self.isEnabled else { return }
    refresh()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func setEnabled(_ on: Bool) {
    Self.isEnabled = on
    if on {
      start()
    } else {
      stop()
      title = nil
      artist = nil
      isPlaying = false
    }
  }

  func refresh() {
    guard Self.isEnabled else { return }
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    let t = info?[MPMediaItemPropertyTitle] as? String
    let a = info?[MPMediaItemPropertyArtist] as? String
    title = t
    artist = a
    if let rate = info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
      isPlaying = rate > 0.01
    } else {
      isPlaying = t != nil
    }
  }
}
