import Foundation

actor CompanionEngine {
  static let shared = CompanionEngine()

  private var file = CompanionLocalStore.load()

  func ensureCompanion() -> StoredCompanion {
    if let existing = file.companions.first {
      return existing
    }
    let created = CompanionLocalStore.makeDefaultCompanion()
    file.companions = [created]
    CompanionLocalStore.save(file)
    CompanionSnapshotStore.saveCompanionId(created.id)
    CompanionSnapshotStore.save(created.toSnapshot())
    return created
  }

  /// Cria/substitui o companion a partir do quiz (skin/arquétipo derivados das respostas).
  @discardableResult
  func birthFromQuiz(draft: CompanionQuiz.Draft, name: String) -> CompanionSnapshot {
    let now = Date()
    let created = StoredCompanion(
      id: CompanionLocalStore.nextId(),
      name: name,
      personality: draft.personality,
      skin: draft.skin,
      artStyle: "pixel",
      backdrop: "sky",
      archetype: draft.archetype.rawValue,
      mood: .HAPPY,
      energy: 80,
      affection: 55,
      lastDecayAt: now,
      lastInteractionAt: now,
      pendingAlert: nil,
      memoryNotes: [],
      userDisplayName: nil
    )
    file.companions = [created]
    file.interactions = []
    CompanionLocalStore.save(file)
    CompanionSnapshotStore.saveCompanionId(created.id)
    let snap = created.toSnapshot(moodText: draft.blurb)
    CompanionSnapshotStore.save(snap)
    CompanionQuiz.markCompleted()
    return snap
  }

  var hasCompanion: Bool { !file.companions.isEmpty }

  func currentSnapshot() -> CompanionSnapshot {
    var companion = ensureCompanion()
    applyDecay(&companion)
    persist(companion)
    let greeting = LocalVoice.greeting(
      archetype: companion.archetype,
      hour: Calendar.current.component(.hour, from: Date())
    )
    var snap = companion.toSnapshot()
    if let greeting {
      snap.moodText = "\(snap.moodText) · \(greeting)"
    }
    CompanionSnapshotStore.save(snap)
    return snap
  }

  func interact(type: InteractionType, message: String? = nil) async -> (CompanionSnapshot, String) {
    var companion = ensureCompanion()
    let now = Date()
    applyDecay(&companion)

    let result = MoodEngine.applyInteraction(
      energy: companion.energy,
      affection: companion.affection,
      type: type
    )

    if let message, !message.isEmpty {
      mergeMemory(&companion, extractMemory(from: message))
    }

    let history: [(role: String, content: String)] = type == .CHAT
      ? chatHistory(companionId: companion.id)
      : []

    let reaction = await LLMService.generate(
      params: .init(
        name: companion.name,
        personality: companion.personality,
        archetype: companion.archetype,
        mood: result.mood,
        energy: result.energy,
        affection: result.affection,
        userMessage: message,
        history: history,
        memoryNotes: companion.memoryNotes,
        weatherHint: nil
      ),
      companionId: companion.id,
      type: type
    )

    companion.energy = result.energy
    companion.affection = result.affection
    companion.mood = result.mood
    companion.lastDecayAt = now
    companion.lastInteractionAt = now
    companion.pendingAlert = nil

    let interaction = StoredInteraction(
      id: CompanionLocalStore.nextId(prefix: "act"),
      companionId: companion.id,
      type: type,
      userMessage: message,
      reactionText: reaction,
      moodAfter: result.mood,
      energyAfter: result.energy,
      affectionAfter: result.affection,
      createdAt: now
    )
    file.interactions.insert(interaction, at: 0)
    if file.interactions.count > 80 {
      file.interactions = Array(file.interactions.prefix(80))
    }
    persist(companion)

    let snap = companion.toSnapshot()
    CompanionSnapshotStore.save(snap)
    return (snap, reaction)
  }

  private func applyDecay(_ companion: inout StoredCompanion) {
    let decayed = MoodEngine.applyTimeDecay(
      energy: companion.energy,
      affection: companion.affection,
      lastInteractionAt: companion.lastInteractionAt
    )
    companion.energy = decayed.energy
    companion.affection = decayed.affection
    companion.mood = decayed.mood
    companion.lastDecayAt = Date()
    if companion.mood == .LONELY {
      companion.pendingAlert = "\(companion.name) sente sua falta."
    }
  }

  private func persist(_ companion: StoredCompanion) {
    if let idx = file.companions.firstIndex(where: { $0.id == companion.id }) {
      file.companions[idx] = companion
    } else {
      file.companions = [companion]
    }
    CompanionLocalStore.save(file)
  }

  private func chatHistory(companionId: String) -> [(role: String, content: String)] {
    var turns: [(role: String, content: String)] = []
    for item in file.interactions where item.companionId == companionId && item.type == .CHAT {
      if turns.count >= 10 { break }
      if let user = item.userMessage, !user.isEmpty {
        turns.append(("user", user))
      }
      turns.append(("assistant", item.reactionText))
    }
    return turns.reversed()
  }

  private func extractMemory(from message: String) -> [String] {
    var notes: [String] = []
    if let regex = try? NSRegularExpression(
      pattern: #"(?:meu nome é|me chamo|pode me chamar de|eu sou o|eu sou a)\s+([A-Za-zÀ-ÿ][\wÀ-ÿ'-]{1,24})"#,
      options: .caseInsensitive
    ) {
      let range = NSRange(message.startIndex..<message.endIndex, in: message)
      if let match = regex.firstMatch(in: message, options: [], range: range),
         let nameRange = Range(match.range(at: 1), in: message) {
        notes.append("Usuário se chama \(message[nameRange])")
      }
    }
    return notes
  }

  private func mergeMemory(_ companion: inout StoredCompanion, _ extras: [String]) {
    var list = companion.memoryNotes
    for note in extras where !list.contains(where: { $0.caseInsensitiveCompare(note) == .orderedSame }) {
      list.insert(note, at: 0)
    }
    companion.memoryNotes = Array(list.prefix(8))
    if let nameNote = extras.first(where: { $0.hasPrefix("Usuário se chama ") }) {
      companion.userDisplayName = nameNote.replacingOccurrences(of: "Usuário se chama ", with: "")
    }
  }
}
