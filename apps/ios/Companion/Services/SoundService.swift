import AVFoundation
import Foundation

/// SFX espelhados do desktop (`apps/desktop/renderer/assets/sfx`).
enum SoundService {
  private static let muteKey = "companion.soundMuted"
  private static var players: [String: AVAudioPlayer] = [:]
  private static var sessionReady = false

  static var isMuted: Bool {
    get { UserDefaults.standard.bool(forKey: muteKey) }
    set { UserDefaults.standard.set(newValue, forKey: muteKey) }
  }

  static func playAction(_ type: String) {
    switch type.uppercased() {
    case "PLAY":
      playStep()
    case "POKE":
      play("hit")
    case "CHAT":
      play("growl")
    case "FEED":
      play("hit")
    case "TEASE":
      play("growl")
      play("hit")
    default:
      break
    }
  }

  /// SFX por clip — espelha `playClipSfx` do desktop.
  static func playClip(_ clip: DinoClip) {
    switch clip {
    case .crack, .eggMove:
      play("rocks")
    case .hatch:
      play("roar")
    case .move, .dash, .jump:
      playStep()
    case .bite, .kick:
      play("hit")
    case .hurt:
      play("hit")
    case .scan, .avoid:
      play("growl")
    case .idle:
      break
    }
  }

  static func playStep() {
    play("step\(1 + Int.random(in: 0..<4))")
  }

  static func playHurt() {
    play("hit")
  }

  static func play(_ name: String) {
    guard !isMuted else { return }
    prepareSession()
    guard let player = player(named: name) else { return }
    player.volume = 0.45
    player.currentTime = 0
    player.play()
  }

  private static func prepareSession() {
    guard !sessionReady else { return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true, options: [])
      sessionReady = true
    } catch {
      print("[sfx] session \(error.localizedDescription)")
    }
  }

  private static func player(named name: String) -> AVAudioPlayer? {
    if let existing = players[name] { return existing }
    guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "SFX") else {
      print("[sfx] missing \(name).wav")
      return nil
    }
    do {
      let p = try AVAudioPlayer(contentsOf: url)
      p.prepareToPlay()
      players[name] = p
      return p
    } catch {
      print("[sfx] load \(name): \(error.localizedDescription)")
      return nil
    }
  }
}
