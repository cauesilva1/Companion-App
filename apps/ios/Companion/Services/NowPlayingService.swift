import Foundation
import UserNotifications

/// Now Playing só-leitura. No iPhone o caminho real é **Spotify Web API** (OAuth).
/// YouTube / Safari não expõem a faixa para apps de terceiros.
@MainActor
final class NowPlayingService: ObservableObject {
  static let shared = NowPlayingService()

  @Published private(set) var title: String?
  @Published private(set) var artist: String?
  @Published private(set) var isPlaying = false
  @Published private(set) var companionLine: String?
  @Published private(set) var source: String = "—"

  private static let enabledKey = "companion.nowPlayingEnabled"
  private static let musicNotifKey = "companion.musicNotifEnabled"
  private var timer: Timer?
  private var lastNotifiedKey: String?

  static var isEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: enabledKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  static var musicNotificationsEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: musicNotifKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: musicNotifKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: musicNotifKey) }
  }

  var line: String? {
    guard Self.isEnabled, let title, !title.isEmpty else { return nil }
    if let artist, !artist.isEmpty {
      return "\(title) — \(artist)"
    }
    return title
  }

  private var trackKey: String? {
    guard let title, !title.isEmpty else { return nil }
    return "\(title)|\(artist ?? "")"
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
    clearTrack(reloadWidget: true)
    source = "—"
  }

  func setEnabled(_ on: Bool) {
    Self.isEnabled = on
    if on {
      start()
    } else {
      stop()
    }
  }

  func refresh() {
    guard Self.isEnabled else { return }
    Task { await refreshAsync() }
  }

  func refreshAsync() async {
    guard Self.isEnabled else { return }

    guard SpotifyService.shared.isConnected else {
      clearTrack(reloadWidget: title != nil)
      source = "Conecte o Spotify"
      return
    }

    switch await SpotifyService.shared.currentlyPlaying() {
    case .track(let track) where !track.title.isEmpty:
      apply(
        title: track.title,
        artist: track.artist,
        playing: track.isPlaying,
        source: track.isPlaying ? "Spotify" : "Spotify (pausado)"
      )
    case .idle:
      // 204 / sem item = fechou o player → limpa app + widget
      clearTrack(reloadWidget: true)
      source = "Spotify"
    case .track, .unavailable:
      // Rede/erro: não apaga a última faixa conhecida
      if title != nil {
        isPlaying = false
        source = "Spotify (pausado)"
      } else {
        source = "Spotify"
      }
    }
  }

  private func clearTrack(reloadWidget: Bool) {
    let had = title != nil
    title = nil
    artist = nil
    isPlaying = false
    companionLine = nil
    lastNotifiedKey = nil
    guard reloadWidget, had else { return }
    WidgetSpeechStore.clearMusic()
    WidgetReloader.reload()
  }

  private func apply(title nextTitle: String, artist nextArtist: String?, playing: Bool, source label: String) {
    let prevKey = trackKey
    title = nextTitle
    artist = nextArtist
    isPlaying = playing
    source = label

    let key = trackKey
    if let key, key != prevKey {
      onTrackChanged(title: nextTitle, artist: nextArtist)
    }
  }

  private func onTrackChanged(title: String, artist: String?) {
    guard !title.isEmpty else { return }
    let key = "\(title)|\(artist ?? "")"
    guard key != lastNotifiedKey else { return }
    lastNotifiedKey = key

    // Banner / ingest na hora — não espera o LLM (isso fazia parecer “demora pra identificar”).
    let trackLine: String = {
      if let artist, !artist.isEmpty { return "\(title) — \(artist)" }
      return title
    }()
    publish(line: trackLine, title: title, artist: artist)
    let snap = CompanionSnapshotStore.load()
    let name = snap?.name ?? CompanionLocalStore.load().companions.first?.name ?? "Companion"
    WidgetSpeechStore.saveMusic(title: title, artist: artist, comment: "", name: name)
    WidgetReloader.reload()

    let arch = snap?.archetype ?? "curioso"
    Task {
      let stored = CompanionLocalStore.load().companions.first
      let line = await LLMService.musicComment(
        title: title,
        artist: artist,
        name: snap?.name ?? stored?.name ?? "Companion",
        archetype: arch,
        personality: stored?.personality ?? "amigável"
      )
      guard self.trackKey == key else { return }
      self.companionLine = line
      WidgetSpeechStore.saveMusic(title: title, artist: artist, comment: line, name: name)
      WidgetReloader.reload()
      if Self.musicNotificationsEnabled {
        await MusicTrackNotifier.notify(title: title, artist: artist, body: line)
      }
    }
  }

  private func publish(line: String, title: String, artist: String?) {
    NotificationCenter.default.post(
      name: .companionNowPlayingChanged,
      object: nil,
      userInfo: ["line": line, "title": title, "artist": artist ?? ""]
    )
  }
}

extension Notification.Name {
  static let companionNowPlayingChanged = Notification.Name("companion.nowPlayingChanged")
}

enum MusicTrackNotifier {
  private static let notifIdPrefix = "companion.music."

  static func notify(title: String, artist: String?, body: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
    let after = await center.notificationSettings()
    guard after.authorizationStatus == .authorized || after.authorizationStatus == .provisional else {
      return
    }

    let content = UNMutableNotificationContent()
    let name = CompanionSnapshotStore.load()?.name ?? "Companion"
    content.title = name
    content.body = body
    content.sound = .default
    content.threadIdentifier = "companion.music"

    let id = notifIdPrefix + String(abs(title.hashValue))
    let request = UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
    )
    try? await center.add(request)
  }
}
