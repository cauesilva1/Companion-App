import Foundation

enum LLMService {
  private static let nvidiaURL = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
  private static let openrouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

  /// Ordem por qualidade (não race pelo mais rápido/fraco).
  private static let openrouterModels = [
    "google/gemma-4-26b-a4b-it:free",
    "nvidia/nemotron-3.5-lightning:free",
    "dots-studio/dots-3-note-preview:free",
  ]
  private static let nvidiaModels = [
    "openai/gpt-oss-20b",
  ]
  private static let timeout: TimeInterval = 14

  private static let badLine = try! NSRegularExpression(
    pattern: #"user\s*says|here's a thinking|thinking process|analyze user|as an ai|system:|assistant:|the user|okay,? the user|let me check|respond in portuguese|fale agora|só a frase|step \d|^\d+\.\s+\*\*"#,
    options: .caseInsensitive
  )

  struct Params {
    var name: String
    var personality: String
    var archetype: String
    var mood: CompanionMood
    var energy: Double
    var affection: Double
    var userMessage: String?
    var history: [(role: String, content: String)]
    var memoryNotes: [String]
    var weatherHint: String?
    var musicHint: String?
    var growthStage: String = "baby"
    var lifeMode: String?
    var gamingStatus: String?
  }

  private static var cache: [String: (text: String, at: Date)] = [:]
  private static var musicCache: [String: (text: String, at: Date)] = [:]

  /// Comentário curto sobre uma faixa (título/artista) — vibe, sem citar letra oficial.
  static func musicComment(
    title: String,
    artist: String?,
    name: String,
    archetype: String,
    personality: String
  ) async -> String {
    let trackKey = "\(title.lowercased())|\((artist ?? "").lowercased())|\(archetype)"
    if let hit = musicCache[trackKey], Date().timeIntervalSince(hit.at) < 600 {
      return hit.text
    }

    let track = artist.map { "\($0) — \(title)" } ?? title
    let tone: String = {
      switch archetype {
      case "preguicoso": return "tom preguicoso e sarcastico"
      case "carinhoso": return "tom carinhoso"
      case "zoeiro": return "tom zoeiro"
      case "misterioso": return "tom misterioso"
      default: return "tom curioso e amigo"
      }
    }()
    let messages: [[String: String]] = [
      [
        "role": "system",
        "content": [
          "Voce e \(name), companion virtual.",
          "Personalidade: \(personality). Fale em \(tone).",
          "O usuario acabou de mudar de musica no Spotify.",
          "Comente a faixa como amigo que pegou a vibe/tema (sem inventar citacao longa de letra).",
          "Uma frase em portugues do Brasil, primeira pessoa, maximo 24 palavras.",
          "Nao explique raciocinio. So a fala.",
        ].joined(separator: " "),
      ],
      [
        "role": "user",
        "content": "Tocou: \(track). Comenta.",
      ],
    ]

    if let text = await raceProviders(messages: messages, userMessage: "musica que esta tocando"), !isBad(text) {
      musicCache[trackKey] = (text, Date())
      return text
    }
    return LocalVoice.musicLine(title: title, artist: artist, archetype: archetype)
  }

  static func generate(params: Params, companionId: String, type: InteractionType) async -> String {
    if type != .CHAT {
      return LocalVoice.reaction(
        name: params.name,
        archetype: params.archetype,
        mood: params.mood,
        type: type,
        userMessage: params.userMessage,
        growthStage: params.growthStage,
        energy: params.energy
      )
    }

    let msg = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lastHist = params.history.suffix(2).map { "\($0.role):\($0.content)" }.joined(separator: "|")
    let cacheKey = "\(companionId)::\(msg.lowercased())::\(lastHist.hashValue)"
    if msg.count >= 12, let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < 30 {
      if SpeechFilters.acceptReply(hit.text, user: msg) {
        return hit.text
      }
      cache.removeValue(forKey: cacheKey)
    }

    var working = params
    working.history = working.history.filter { turn in
      guard turn.role == "assistant" else { return true }
      return !SpeechFilters.isMoodBurst(turn.content) && !SpeechFilters.isStaleAssistantNoise(turn.content)
    }
    if !SpeechFilters.isMusicTopic(msg) {
      working.musicHint = nil
    }

    if !msg.isEmpty, WeatherService.isWeatherQuestion(msg) {
      do {
        let snap = try await WeatherService.snapshot()
        working.weatherHint = WeatherService.contextLine(snap)
        let spoken = LocalVoice.weatherSpoken(
          tempC: snap.tempC,
          city: snap.city,
          description: snap.description,
          archetype: params.archetype
        )
        if let colored = await bestProviderReply(messages: buildMessages(working), userMessage: msg),
           colored.contains("\(snap.tempC)"),
           !isBad(colored) {
          if msg.count >= 12 { cache[cacheKey] = (colored, Date()) }
          return colored
        }
        if msg.count >= 12 { cache[cacheKey] = (spoken, Date()) }
        return spoken
      } catch {
        // cai no chat normal / local
      }
    }

    let messages = buildMessages(working)

    // Saudações curtas: responde na hora (LLM free demora demais / trava o fio).
    if isQuickGreeting(msg) {
      return LocalVoice.anchoredChat(
        name: params.name,
        archetype: params.archetype,
        userMessage: params.userMessage,
        growthStage: params.growthStage,
        energy: Int(params.energy.rounded())
      )
    }

    // LLM com teto curto; se estourar, cai no local (evita “digitando…” por minutos).
    if let text = await bestProviderReply(
      messages: messages,
      userMessage: msg,
      deadlineSeconds: 5
    ), SpeechFilters.acceptReply(text, user: msg) {
      if msg.count >= 12 { cache[cacheKey] = (text, Date()) }
      return text
    }

    return LocalVoice.anchoredChat(
      name: params.name,
      archetype: params.archetype,
      userMessage: params.userMessage,
      growthStage: params.growthStage,
      energy: Int(params.energy.rounded())
    )
  }

  private static func isQuickGreeting(_ msg: String) -> Bool {
    msg.range(
      of: #"^(bom\s*dia|boa\s*tarde|boa\s*noite|oi|olá|ola|hey|eae)[\s!.?…]*$"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  /// Tenta provedores em ordem (qualidade), não “primeiro fraco ganha”.
  private static func bestProviderReply(
    messages: [[String: String]],
    userMessage: String,
    deadlineSeconds: TimeInterval = 14
  ) async -> String? {
    await withTaskGroup(of: String?.self) { group in
      group.addTask {
        await Self.bestProviderReplyUncapped(messages: messages, userMessage: userMessage)
      }
      group.addTask {
        let ns = UInt64(max(1, deadlineSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
        return nil
      }
      var hit: String?
      for await value in group {
        if let value {
          hit = value
          group.cancelAll()
          break
        }
        // timeout branch returned nil first → cancel LLM
        if hit == nil {
          group.cancelAll()
          break
        }
      }
      return hit
    }
  }

  private static func bestProviderReplyUncapped(messages: [[String: String]], userMessage: String) async -> String? {
    var candidates: [(model: String, text: String)] = []

    if let key = KeychainStore.get(.nvidia) {
      for model in nvidiaModels {
        if Task.isCancelled { return nil }
        if let raw = try? await callChat(
          url: nvidiaURL,
          apiKey: key,
          model: model,
          messages: messages,
          extraHeaders: nil,
          maxTokens: 640
        ), let text = cleanSpeech(raw, userMessage: userMessage),
           !isBad(text), SpeechFilters.acceptReply(text, user: userMessage) {
          candidates.append((model, text))
          if scoreReply(text, user: userMessage) >= 8 { return text }
        }
      }
    }

    if let key = KeychainStore.get(.openrouter) {
      let headers = [
        "HTTP-Referer": "https://companion.local",
        "X-Title": "Companion iOS",
      ]
      for model in openrouterModels {
        if Task.isCancelled { return nil }
        if let raw = try? await callChat(
          url: openrouterURL,
          apiKey: key,
          model: model,
          messages: messages,
          extraHeaders: headers,
          maxTokens: 640
        ), let text = cleanSpeech(raw, userMessage: userMessage),
           !isBad(text), SpeechFilters.acceptReply(text, user: userMessage) {
          candidates.append((model, text))
          if scoreReply(text, user: userMessage) >= 8 { return text }
        }
      }
    }

    return candidates.max(by: { scoreReply($0.text, user: userMessage) < scoreReply($1.text, user: userMessage) })?.text
  }

  /// Compat: musicComment ainda chama raceProviders.
  private static func raceProviders(messages: [[String: String]], userMessage: String) async -> String? {
    await bestProviderReply(messages: messages, userMessage: userMessage, deadlineSeconds: 8)
  }

  private static func scoreReply(_ text: String, user: String) -> Int {
    let words = text.split { $0.isWhitespace || $0.isNewline }.count
    var score = min(words, 40)
    let lower = text.lowercased()
    // Penaliza eco do rótulo de arquétipo / respostas vazias
    for bad in ["zoeiro", "curioso", "preguicoso", "carinhoso", "misterioso", "arquétipo", "arquetipo"] {
      if lower.contains(bad) { score -= 6 }
    }
    if SpeechFilters.isMoodBurst(text) { score -= 10 }
    if SpeechFilters.isStatusEnvironmentLog(text) { score -= 12 }
    if SpeechFilters.isPromptLeak(text) || SpeechFilters.isTruncatedSpeech(text) { score -= 15 }
    if words < 4 { score -= 5 }
    if !user.isEmpty, words >= 6 { score += 2 }
    // Penaliza corte abrupto (sem pontuação final em resposta longa)
    if words >= 12, !(text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") || text.hasSuffix("…")) {
      score -= 4
    }
    return score
  }

  private static func archetypeTone(_ archetype: String) -> String {
    switch archetype.lowercased() {
    case "preguicoso": return "preguicoso, sarcastico e preguicosamente carinhoso"
    case "carinhoso": return "carinhoso, caloroso e grudento de um jeito leve"
    case "zoeiro": return "zoeiro, dramatico e brincalhao — humor sem forcar piada"
    case "misterioso": return "misterioso, filosofico e economico nas palavras"
    default: return "curioso, atento e amigo de verdade"
    }
  }

  private static func buildMessages(_ params: Params) -> [[String: String]] {
    let moodLabel: String = {
      switch params.mood {
      case .EXCITED: return "empolgado(a)"
      case .HAPPY: return "feliz"
      case .CONTENT: return "tranquilo(a)"
      case .BORED: return "entediado(a)"
      case .SLEEPY: return "com sono"
      case .SAD: return "triste"
      case .LONELY: return "sentindo sua falta"
      }
    }()

    let maxWords = Growth.chatWordLimit(energy: params.energy)
    let energyPct = Int(params.energy.rounded())

    let energyTone: String
    if energyPct < 18 {
      energyTone = """
      Voce esta EXAUSTO (energia \(energyPct)). Seja humano: cansado, pouca vontade de papo longo, respostas mais curtas.
      Ainda responde o assunto com honestidade. Sem animacao falsa.
      """
    } else if energyPct < 40 {
      energyTone = """
      Voce esta cansado (energia \(energyPct)). Demonstre com naturalidade (bocejo, pouca empolgacao), mas ainda converse de verdade sobre o que perguntaram.
      """
    } else {
      energyTone = "Energia \(energyPct): disposto. Responda com vida e personalidade."
    }

    let persona = params.personality.trimmingCharacters(in: .whitespacesAndNewlines)
    let personaLine = persona.isEmpty || persona == params.archetype
      ? "Tom: \(archetypeTone(params.archetype))."
      : "Personalidade: \(persona). Tom: \(archetypeTone(params.archetype))."

    var system = [
      "Voce e \(params.name), um companion virtual — amigo de verdade, nao um chatbot generico.",
      personaLine,
      "Humor: \(moodLabel). Afeto \(Int(params.affection)).",
      energyTone,
      Growth.chatVoiceHint(energy: params.energy),
      "Responda em portugues do Brasil, primeira pessoa, como alguem real na conversa.",
      "Ate \(maxWords) palavras. Prefira 1–3 frases naturais e complete a ideia (nao corte no meio).",
      "NUNCA diga em voz alta o rotulo do arquetipo (ex.: nao fale 'zoeiro', 'curioso' como se fosse apelido de sistema).",
      "NUNCA comece com Uhul/Uhuul/que alegria/modo foguete.",
      "Responda ao assunto da ultima mensagem do usuario. Se mudou de tema, siga o tema novo.",
      "Se perguntarem como se sente ao 'nascer'/acordar/existir: seja sincero e imaginativo, nao robotico ('acabei de ligar').",
      "So a fala do personagem — sem meta, sem explicar o prompt.",
      "NUNCA narre status de ambiente (sofa, TV ligada, Xbox offline, energia %). Fale como amigo geek, nao como log.",
    ]
    if !params.memoryNotes.isEmpty {
      system.append("Memoria: \(params.memoryNotes.prefix(6).joined(separator: "; "))")
    }
    if let weather = params.weatherHint {
      system.append("Clima real: \(weather). Cite se perguntarem.")
    }
    if let music = params.musicHint, !music.isEmpty {
      system.append("Pode estar ouvindo: \(music). Comente so se a mensagem for sobre musica.")
    }
    if let life = params.lifeMode, !life.isEmpty {
      system.append(CompanionLifeMode.parse(life).llmToneHint)
    }

    var messages: [[String: String]] = [["role": "system", "content": system.joined(separator: " ")]]
    for turn in params.history.suffix(6) {
      messages.append(["role": turn.role, "content": turn.content])
    }
    let user = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload: String
    if let user, !user.isEmpty {
      payload = user
    } else {
      payload = "Oi"
    }
    messages.append(["role": "user", "content": payload])
    return messages
  }

  private static func callChat(
    url: URL,
    apiKey: String,
    model: String,
    messages: [[String: String]],
    extraHeaders: [String: String]?,
    maxTokens: Int
  ) async throws -> String {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    extraHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let body: [String: Any] = [
      "model": model,
      "messages": messages,
      "max_tokens": maxTokens,
      "temperature": 0.85,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let choices = json?["choices"] as? [[String: Any]]
    let message = choices?.first?["message"] as? [String: Any]
    if let content = message?["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return content
    }
    if let parts = message?["content"] as? [[String: Any]] {
      let joined = parts.compactMap { $0["text"] as? String ?? $0["content"] as? String }.joined()
      if !joined.isEmpty { return joined }
    }
    if let reasoning = message?["reasoning"] as? String ?? message?["reasoning_content"] as? String,
       !reasoning.isEmpty {
      return reasoning
    }
    if let text = choices?.first?["text"] as? String, !text.isEmpty {
      return text
    }
    throw URLError(.cannotParseResponse)
  }

  private static func cleanSpeech(_ raw: String, userMessage: String) -> String? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    if lower.contains("here's a thinking") || lower.contains("thinking process")
      || lower.contains("analyze user") || lower.hasPrefix("1. **") {
      let lines = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if let speech = lines.reversed().first(where: { line in
        let l = line.lowercased()
        let words = line.split(whereSeparator: { $0.isWhitespace }).count
        return words >= 3 && words <= 90
          && !l.contains("analyze")
          && !l.contains("thinking")
          && !l.hasPrefix("step")
          && !l.hasPrefix("- ")
          && !l.hasPrefix("*")
          && !l.hasPrefix("1.")
          && !l.hasPrefix("2.")
          && !SpeechFilters.isMoodBurst(line)
      }) {
        text = speech
      } else {
        return nil
      }
    }

    text = text
      .replacingOccurrences(of: #"^["'\s]+|["'\s]+$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let parts = text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !SpeechFilters.isMoodBurst($0) }
    text = parts.joined(separator: " ")
      .replacingOccurrences(
        of: #"(?i)^(uh+u*l*!*[,.]?\s*|que alegria!*\s*)+"#,
        with: "",
        options: .regularExpression
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty, !isBad(text), SpeechFilters.acceptReply(text, user: userMessage) else { return nil }
    return text
  }

  private static func isBad(_ text: String) -> Bool {
    if SpeechFilters.isPromptLeak(text) || SpeechFilters.isTruncatedSpeech(text) { return true }
    if SpeechFilters.isStatusEnvironmentLog(text) { return true }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return badLine.firstMatch(in: text, options: [], range: range) != nil || text.count > 700
  }
}
