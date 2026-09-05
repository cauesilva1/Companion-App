import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum DinoClip: String, Equatable, CaseIterable {
  case idle, move, jump, dash, hurt, kick, bite, scan, avoid
  case eggMove, crack, hatch

  /// FPS iguais ao desktop `DINO_CLIPS`.
  var fps: Double {
    switch self {
    case .idle: return 5
    case .move: return 10
    case .jump: return 8
    case .dash: return 12
    case .hurt, .kick, .bite: return 10
    case .scan: return 8
    case .avoid: return 6
    case .eggMove: return 6
    case .crack, .hatch: return 7
    }
  }

  var isLooping: Bool { self == .idle }

  var assetSuffix: String {
    switch self {
    case .eggMove: return "EggMove"
    default:
      return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
  }
}

enum DinoSpriteCatalog {
  static let playClips: [DinoClip] = [.jump, .move, .dash, .bite, .kick]

  static func folderName(forSkin skin: String) -> String {
    switch skin.lowercased() {
    case "dino-doux", "doux": return "Doux"
    case "dino-vita", "vita": return "Vita"
    case "dino-olaf", "olaf": return "Olaf"
    case "dino-kuro", "kuro": return "Kuro"
    case "dino-mort", "mort": return "Mort"
    default: return "Mort"
    }
  }

  static func sheetName(skin: String, clip: DinoClip) -> String {
    "Sheet\(folderName(forSkin: skin))\(clip.assetSuffix)"
  }

  #if canImport(UIKit)
  private static var sheetCache: [String: UIImage] = [:]
  private static var frameCache: [String: UIImage] = [:]

  static func sheetImage(skin: String, clip: DinoClip) -> UIImage? {
    let name = sheetName(skin: skin, clip: clip)
    if let hit = sheetCache[name] { return hit }
    if let img = UIImage(named: name) {
      sheetCache[name] = img
      return img
    }
    if clip == .idle, let avatar = UIImage(named: CompanionSnapshot.imageName(forSkin: skin)) {
      sheetCache[name] = avatar
      return avatar
    }
    return nil
  }

  static func frameCount(for image: UIImage) -> Int {
    guard let cg = image.cgImage else { return 1 }
    let fh = max(1, cg.height)
    return max(1, cg.width / fh)
  }

  static func frameImage(sheetKey: String, sheet: UIImage, index: Int) -> UIImage {
    guard let cg = sheet.cgImage else { return sheet }
    let fh = max(1, cg.height)
    let fw = fh
    let frames = max(1, cg.width / fw)
    let i = ((index % frames) + frames) % frames
    let key = "\(sheetKey)#\(i)"
    if let hit = frameCache[key] { return hit }
    let rect = CGRect(x: i * fw, y: 0, width: fw, height: fh)
    guard let cropped = cg.cropping(to: rect) else { return sheet }
    let img = UIImage(cgImage: cropped, scale: 1, orientation: .up)
    frameCache[key] = img
    return img
  }
  #endif
}

/// Player estilo desktop: composição a 60 Hz; frames do sheet no fps do clip.
struct DinoSpriteView: View {
  let skin: String
  var clip: DinoClip = .idle
  var mood: String = "HAPPY"
  var size: CGFloat = 160
  var animNonce: Int = 0
  /// Fila após o clip atual (ex.: crack→hatch→idle).
  var followUpQueue: [DinoClip] = []
  var onBecameIdle: (() -> Void)? = nil
  var onClipStarted: ((DinoClip) -> Void)? = nil

  @State private var playing: DinoClip = .idle
  @State private var queue: [DinoClip] = []
  @State private var startedAt = Date()
  @State private var lastHandledNonce = -1
  @State private var completionArmed = false

  private var clipFps: Double {
    if playing == .idle, mood.uppercased() == "SLEEPY" { return 2 }
    return playing.fps
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
      frameView(at: context.date)
    }
    .frame(width: size, height: size)
    .onAppear { boot() }
    .onChange(of: animNonce) { _ in play(clip, queue: followUpQueue, nonce: animNonce) }
    .onChange(of: clip) { newClip in
      if newClip == .idle, playing == .idle { return }
      play(newClip, queue: followUpQueue, nonce: animNonce)
    }
    .onChange(of: skin) { _ in
      startedAt = Date()
      completionArmed = playing != .idle
    }
  }

  private func boot() {
    if animNonce != lastHandledNonce || playing != clip {
      play(clip, queue: followUpQueue, nonce: animNonce)
    }
  }

  private func play(_ next: DinoClip, queue follow: [DinoClip], nonce: Int) {
    playing = next
    queue = follow
    startedAt = Date()
    lastHandledNonce = nonce
    completionArmed = !next.isLooping
    onClipStarted?(next)
  }

  @ViewBuilder
  private func frameView(at date: Date) -> some View {
    #if canImport(UIKit)
    let key = DinoSpriteCatalog.sheetName(skin: skin, clip: playing)
    if let sheet = DinoSpriteCatalog.sheetImage(skin: skin, clip: playing) {
      let count = max(1, DinoSpriteCatalog.frameCount(for: sheet))
      let index = frameIndex(at: date, count: count)
      Image(uiImage: DinoSpriteCatalog.frameImage(sheetKey: key, sheet: sheet, index: index))
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel("Dino \(skin)")
    } else if isEggSequence(playing) {
      // Sem fallback para idle — evita “pular” o hatch.
      let count = max(4, Int(playing.fps))
      let index = frameIndex(at: date, count: count)
      eggPlaceholder(frame: index, total: count)
        .frame(width: size, height: size)
    } else if let idle = DinoSpriteCatalog.sheetImage(skin: skin, clip: .idle) {
      let idleKey = DinoSpriteCatalog.sheetName(skin: skin, clip: .idle)
      Image(uiImage: DinoSpriteCatalog.frameImage(sheetKey: idleKey, sheet: idle, index: 0))
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      DinoAvatar(skin: skin, size: size)
    }
    #else
    DinoAvatar(skin: skin, size: size)
    #endif
  }

  private func isEggSequence(_ clip: DinoClip) -> Bool {
    clip == .eggMove || clip == .crack || clip == .hatch
  }

  @ViewBuilder
  private func eggPlaceholder(frame: Int, total: Int) -> some View {
    let t = Double(frame) / Double(max(1, total - 1))
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .overlay(
          RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
            .stroke(Color.black.opacity(0.15), lineWidth: 2)
        )
        .scaleEffect(0.72 + 0.06 * sin(t * .pi))
      if playing == .crack || playing == .hatch {
        Text(playing == .hatch ? "✨" : "💥")
          .font(.system(size: size * 0.28))
      }
    }
  }

  private func frameIndex(at date: Date, count: Int) -> Int {
    if playing.isLooping {
      let tick = Int(date.timeIntervalSinceReferenceDate * clipFps)
      return ((tick % count) + count) % count
    }
    let raw = Int(max(0, date.timeIntervalSince(startedAt)) * clipFps)
    if raw >= count {
      completeOneShotIfNeeded()
      return count - 1
    }
    return raw
  }

  private func completeOneShotIfNeeded() {
    guard completionArmed else { return }
    completionArmed = false
    DispatchQueue.main.async {
      if !queue.isEmpty {
        let next = queue.removeFirst()
        playing = next
        startedAt = Date()
        completionArmed = !next.isLooping
        onClipStarted?(next)
        if next.isLooping {
          onBecameIdle?()
        }
      } else {
        playing = .idle
        startedAt = Date()
        onBecameIdle?()
      }
    }
  }
}

struct DinoStaticFrame: View {
  let skin: String
  var size: CGFloat = 48

  var body: some View {
    #if canImport(UIKit)
    if let sheet = DinoSpriteCatalog.sheetImage(skin: skin, clip: .idle) {
      let key = DinoSpriteCatalog.sheetName(skin: skin, clip: .idle)
      Image(uiImage: DinoSpriteCatalog.frameImage(sheetKey: key, sheet: sheet, index: 0))
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      DinoAvatar(skin: skin, size: size)
    }
    #else
    DinoAvatar(skin: skin, size: size)
    #endif
  }
}
