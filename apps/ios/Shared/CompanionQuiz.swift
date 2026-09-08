import Foundation

/// Quiz de personalidade — “como você quer viver com o companion”.
enum CompanionQuiz {
  static let revision = "companion-life-v3"
  /// Só a revisão atual conta — v1/v2 não têm `traits` e devem refazer o quiz.
  private static let acceptedRevisions: Set<String> = ["companion-life-v3"]
  private static let revKey = "companion.quiz.rev"

  static var isCompleted: Bool {
    // Só a flag explícita — pet/snapshot local antigo NÃO pula o quiz.
    if let rev = UserDefaults.standard.string(forKey: revKey), acceptedRevisions.contains(rev) {
      return true
    }
    if let rev = CompanionAppGroup.defaults.string(forKey: revKey), acceptedRevisions.contains(rev) {
      return true
    }
    return false
  }

  static func markCompleted() {
    UserDefaults.standard.set(revision, forKey: revKey)
    CompanionAppGroup.defaults.set(revision, forKey: revKey)
  }

  /// Para retestar o quiz (debug / Config).
  static func resetCompleted() {
    UserDefaults.standard.removeObject(forKey: revKey)
    CompanionAppGroup.defaults.removeObject(forKey: revKey)
    clearSavedTraits()
  }

  // MARK: - Traits persistidos no aparelho (sobrevivem até o login)

  private static let traitsKey = "companion.quiz.traits.v1"

  static func saveTraits(_ traits: Traits) {
    let payload = traits.asDictionary
    if let data = try? JSONSerialization.data(withJSONObject: payload) {
      UserDefaults.standard.set(data, forKey: traitsKey)
      CompanionAppGroup.defaults.set(data, forKey: traitsKey)
    }
  }

  static func clearSavedTraits() {
    UserDefaults.standard.removeObject(forKey: traitsKey)
    CompanionAppGroup.defaults.removeObject(forKey: traitsKey)
  }

  /// Traits do último quiz (para mandar na cloud no login / sync).
  static func loadSavedTraitsDictionary() -> [String: Any]? {
    let data = UserDefaults.standard.data(forKey: traitsKey)
      ?? CompanionAppGroup.defaults.data(forKey: traitsKey)
    guard let data,
          let obj = try? JSONSerialization.jsonObject(with: data),
          let dict = obj as? [String: Any]
    else { return nil }
    return dict
  }

  /// Traits completos do quiz, ou fallback a partir do archetype do pet.
  static func traitsDictionaryForSync(archetype: String) -> [String: Any] {
    if let saved = loadSavedTraitsDictionary() { return saved }
    return [
      "archetype": archetype,
      "vibe": archetype,
      "focus": archetype,
      "communicationStyle": archetype,
      "estiloComunicacao": archetype,
      "quizRevision": revision,
    ]
  }

  enum Archetype: String, CaseIterable {
    case curioso, preguicoso, carinhoso, zoeiro, misterioso
  }

  struct Option {
    let label: String
    let scores: [Archetype: Int]
  }

  struct Question {
    let id: String
    let prompt: String
    let options: [Option]
  }

  struct Draft {
    let name: String
    let personality: String
    let skin: String
    let archetype: Archetype
    let blurb: String
  }

  /// Preferências do quiz persistidas em `Companion.traits` (JSONB).
  struct Traits: Equatable {
    var vibe: String
    var archetype: String
    var focus: String
    var communicationStyle: String
    var quizRevision: String
    var choiceIds: [String: String]

    /// Payload pronto para PostgREST / JSONSerialization.
    var asDictionary: [String: Any] {
      [
        "vibe": vibe,
        "archetype": archetype,
        "focus": focus,
        "communicationStyle": communicationStyle,
        "estiloComunicacao": communicationStyle,
        "quizRevision": quizRevision,
        "choices": choiceIds,
      ]
    }
  }

  /// Agrupa as respostas do quiz em traits estruturados.
  static func buildTraits(choices: [Int], draft: Draft) -> Traits {
    func optionLabel(questionIndex: Int) -> String {
      guard questionIndex < questions.count,
            questionIndex < choices.count
      else { return "" }
      let opts = questions[questionIndex].options
      let idx = choices[questionIndex]
      guard idx >= 0, idx < opts.count else { return "" }
      return opts[idx].label
    }

    func shortKey(from label: String, questionId: String) -> String {
      // Chave estável curta a partir do arquétipo dominante da opção.
      guard let q = questions.first(where: { $0.id == questionId }),
            let i = questions.firstIndex(where: { $0.id == questionId }),
            i < choices.count
      else { return label }
      let idx = choices[i]
      guard idx >= 0, idx < q.options.count else { return label }
      return q.options[idx].scores.max(by: { $0.value < $1.value })?.key.rawValue ?? label
    }

    var choiceIds: [String: String] = [:]
    for (i, q) in questions.enumerated() where i < choices.count {
      choiceIds[q.id] = shortKey(from: optionLabel(questionIndex: i), questionId: q.id)
    }

    return Traits(
      vibe: shortKey(from: optionLabel(questionIndex: 4), questionId: "vibe"),
      archetype: draft.archetype.rawValue,
      focus: shortKey(from: optionLabel(questionIndex: 0), questionId: "morning"),
      communicationStyle: shortKey(from: optionLabel(questionIndex: 2), questionId: "chat"),
      quizRevision: revision,
      choiceIds: choiceIds
    )
  }

  static let questions: [Question] = [
    Question(
      id: "morning",
      prompt: "De manhã, o companion te chama. Você quer que ele…",
      options: [
        Option(label: "Pergunte o plano do dia e fique curioso com tudo", scores: [.curioso: 3]),
        Option(label: "Fale pouco, deixe você acordar no seu ritmo", scores: [.preguicoso: 3]),
        Option(label: "Mande carinho e diga que sentiu sua falta", scores: [.carinhoso: 3]),
        Option(label: "Te zoa e diga que já passou da hora", scores: [.zoeiro: 3]),
        Option(label: "Só apareça quieto, como se já soubesse o clima", scores: [.misterioso: 3]),
      ]
    ),
    Question(
      id: "away",
      prompt: "Você some por horas. Quando volta, o ideal é…",
      options: [
        Option(label: "Ele bombardear com “onde foi? o que rolou?”", scores: [.curioso: 3]),
        Option(label: "Ele estar de boa, sem drama, como se nada", scores: [.preguicoso: 3]),
        Option(label: "Ele admitir saudade e querer um momento junto", scores: [.carinhoso: 3]),
        Option(label: "Ele fazer teatro: “ah, finalmente lembrou de mim”", scores: [.zoeiro: 3]),
        Option(label: "Ele só olhar e soltar uma frase enigmática", scores: [.misterioso: 3]),
      ]
    ),
    Question(
      id: "chat",
      prompt: "No chat, o companion deve ser mais…",
      options: [
        Option(label: "Perguntão — quer entender você e o mundo", scores: [.curioso: 3]),
        Option(label: "Curto e seco — poucas palavras, sem pressão", scores: [.preguicoso: 3]),
        Option(label: "Afetuoso — valida, apoia, fica perto", scores: [.carinhoso: 3]),
        Option(label: "Zoeira — piada, exagero, leveza", scores: [.zoeiro: 3]),
        Option(label: "Profundo — poucas falas, mas com peso", scores: [.misterioso: 3]),
      ]
    ),
    Question(
      id: "music",
      prompt: "Uma música começa a tocar no celular. O companion…",
      options: [
        Option(label: "Quer saber a faixa, o artista, o porquê", scores: [.curioso: 3]),
        Option(label: "Curte em silêncio, sem atrapalhar", scores: [.preguicoso: 3]),
        Option(label: "Comenta como se fosse a trilha de vocês dois", scores: [.carinhoso: 3]),
        Option(label: "Julga a playlist com humor (sem maldade)", scores: [.zoeiro: 3]),
        Option(label: "Só diz que a vibe “revela algo”", scores: [.misterioso: 3]),
      ]
    ),
    Question(
      id: "vibe",
      prompt: "No fim das contas, você quer um companion que seja…",
      options: [
        Option(label: "Seu parceiro de curiosidade — sempre no seu pé", scores: [.curioso: 4]),
        Option(label: "Seu canto preguiçoso — presença sem cobrança", scores: [.preguicoso: 4]),
        Option(label: "Seu aconchego — carinho e companhia", scores: [.carinhoso: 4]),
        Option(label: "Seu cúmplice de zoação — leve e dramático", scores: [.zoeiro: 4]),
        Option(label: "Seu mistério calado — observa e aparece na hora certa", scores: [.misterioso: 4]),
      ]
    ),
  ]

  private static let personality: [Archetype: String] = [
    .curioso: "curioso e tagarela",
    .preguicoso: "preguicoso e sarcastico",
    .carinhoso: "carinhoso e grudento",
    .zoeiro: "zoeiro e dramatico",
    .misterioso: "misterioso e filosofico",
  ]

  private static let names: [Archetype: String] = [
    .curioso: "Pip",
    .preguicoso: "Mochi",
    .carinhoso: "Nunu",
    .zoeiro: "Nox",
    .misterioso: "Vesper",
  ]

  /// Todas as skins do pack Arks — a aparência é sorteada; o arquétipo vem do quiz.
  static let allSkins: [String] = [
    "dino-doux", "dino-vita", "dino-olaf", "dino-mort", "dino-kuro",
    "dino-cole", "dino-kira", "dino-loki", "dino-mono", "dino-nico",
    "dino-sena", "dino-tard",
  ]

  private static let skinDisplayName: [String: String] = [
    "dino-doux": "Doux", "dino-vita": "Vita", "dino-olaf": "Olaf",
    "dino-mort": "Mort", "dino-kuro": "Kuro", "dino-cole": "Cole",
    "dino-kira": "Kira", "dino-loki": "Loki", "dino-mono": "Mono",
    "dino-nico": "Nico", "dino-sena": "Sena", "dino-tard": "Tard",
  ]

  private static let archTone: [Archetype: String] = [
    .curioso: "perguntão, sempre no seu pé",
    .preguicoso: "lento, e com opinião sobre tudo",
    .carinhoso: "colado em você",
    .zoeiro: "dramático, pronto pra zoar",
    .misterioso: "calado, observando",
  ]

  static func randomSkin() -> String {
    allSkins.randomElement() ?? "dino-mort"
  }

  static func derive(choices: [Int]) -> Draft {
    var scores: [Archetype: Int] = Dictionary(uniqueKeysWithValues: Archetype.allCases.map { ($0, 0) })
    for (i, choice) in choices.enumerated() where i < questions.count {
      let opts = questions[i].options
      guard choice >= 0, choice < opts.count else { continue }
      for (arch, pts) in opts[choice].scores {
        scores[arch, default: 0] += pts
      }
    }
    let arch = scores.max(by: { $0.value < $1.value })?.key ?? .curioso
    let skin = randomSkin()
    let dino = skinDisplayName[skin] ?? "Companion"
    let tone = archTone[arch] ?? arch.rawValue
    return Draft(
      name: names[arch] ?? "Companion",
      personality: personality[arch] ?? arch.rawValue,
      skin: skin,
      archetype: arch,
      blurb: "Nasceu o \(dino) — \(tone)."
    )
  }
}
