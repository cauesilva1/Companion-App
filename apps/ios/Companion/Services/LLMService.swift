import Foundation

enum LLMService {
  private static let nvidiaURL = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
  private static let openrouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

  /// Race: Lightning (strip) → Gemma → dots → gpt-oss NIM.
  private static let openrouterModels = [
    "nvidia/nemotron-3.5-lightning:free",
    "google/gemma-4-26b-a4b-it:free",
    "dots-studio/dots-3-note-preview:free",
  ]
  private static let nvidiaModels = [
    "openai/gpt-oss-20b",
  ]
  private static let timeout: TimeInterval = 6

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
          "Personalidade: \(personality). Arquétipo: \(archetype). Fale em \(tone).",
          "O usuario acabou de mudar de musica no Spotify.",
          "Comente a faixa como amigo que pegou a vibe/tema (sem inventar citacao longa de letra).",
          "Uma frase em portugues do Brasil, primeira pessoa, maximo 20 palavras.",
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
        growthStage: params.growthStage
      )
    }

    let msg = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lastHist = params.history.suffix(2).map { "\($0.role):\($0.content)" }.joined(separator: "|")
    let cacheKey = "\(companionId)::\(msg.lowercased())::\(lastHist.hashValue)"
    if msg.count >= 12, let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < 30 {
      // Não reusa reply off-topic / evolução falsa.
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
    // Música só entra no prompt se o usuário estiver falando de música.
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
        if let colored = await raceProviders(messages: buildMessages(working), userMessage: msg),
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
    if let text = await raceProviders(messages: messages, userMessage: msg),
       SpeechFilters.acceptReply(text, user: msg) {
      if msg.count >= 12 { cache[cacheKey] = (text, Date()) }
      return text
    }

    return LocalVoice.anchoredChat(
      name: params.name,
      archetype: params.archetype,
      userMessage: params.userMessage,
      growthStage: params.growthStage
    )
  }

  /// Dispara OpenRouter + NVIDIA em paralelo; primeiro texto limpo ganha.
  private static func raceProviders(messages: [[String: String]], userMessage: String) async -> String? {
    await withTaskGroup(of: String?.self) { group in
      if let key = KeychainStore.get(.openrouter) {
        let headers = [
          "HTTP-Referer": "https://companion.local",
          "X-Title": "Companion iOS",
        ]
        for model in openrouterModels {
          let maxTok = model.contains("lightning") || model.contains("dots") ? 220 : 120
          group.addTask {
            let raw = try? await callChat(
              url: openrouterURL,
              apiKey: key,
              model: model,
              messages: messages,
              extraHeaders: headers,
              maxTokens: maxTok
            )
            return raw.flatMap { cleanSpeech($0, userMessage: userMessage) }
          }
        }
      }
      if let key = KeychainStore.get(.nvidia) {
        for model in nvidiaModels {
          group.addTask {
            let raw = try? await callChat(
              url: nvidiaURL,
              apiKey: key,
              model: model,
              messages: messages,
              extraHeaders: nil,
              maxTokens: 220
            )
            return raw.flatMap { cleanSpeech($0, userMessage: userMessage) }
          }
        }
      }

      for await result in group {
        if let text = result, !text.isEmpty, !isBad(text), SpeechFilters.acceptReply(text, user: userMessage) {
          group.cancelAll()
          return text
        }
      }
      return nil
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

    let tone: String = {
      switch params.archetype {
      case "preguicoso": return "Fale preguicoso e sarcastico, frases curtas."
      case "carinhoso": return "Fale carinhoso e grudento."
      case "zoeiro": return "Fale zoeiro e dramatico."
      case "misterioso": return "Fale misterioso e filosofico."
      default: return "Fale curioso e atento; pergunta só se fizer sentido no momento."
      }
    }()

    let stage = Growth.normalize(params.growthStage)
    let maxWords = Growth.wordLimit(for: stage)

    var system = [
      "Voce e \(params.name), companion virtual e amigo de verdade.",
      "Personalidade: \(params.personality). Arquétipo: \(params.archetype).",
      "Humor agora: \(moodLabel). Energia \(Int(params.energy)), afeto \(Int(params.affection)).",
      tone,
      Growth.voiceHint(for: stage),
      "Espelhe o jeito de falar do usuario (ritmo, gírias, informalidade, emoji) sem copiar a frase dele.",
      "PRIORIDADE: a ultima mensagem do usuario. Responda ao assunto DELA.",
      "Se o usuario mudou de tema, abandone o assunto anterior (musica, rap, clima, etc).",
      "Historico e so contexto; nao continue conversa antiga se a mensagem atual for outra coisa.",
      "Nunca comece com grito vazio (Uhul, Uhuul, que alegria, modo foguete).",
      "Nao explique por que voce disse uhul/foguete a menos que o usuario pergunte isso agora.",
      "Nao repita pergunta ja respondida. Nao reinicie o assunto.",
      "Responda em portugues do Brasil, primeira pessoa, no maximo \(maxWords) palavras.",
      "Nao explique raciocinio. So a fala do personagem.",
    ]
    if !Growth.isEnabled {
      system.append(
        "Evolucao visual DESLIGADA: voce ainda e so a forma base. Nao diga que ja evoluiu, que cresce sozinho, nem que o usuario te evoluiu."
      )
      system.append(
        "Se falarem de design/evolucao/arte: seja empatico; diga que a forma base ja esta ok e que evolucoes visuais podem vir depois — sem inventar progresso."
      )
    }
    if !params.memoryNotes.isEmpty {
      system.append("Memoria e estilo: \(params.memoryNotes.prefix(6).joined(separator: "; "))")
    }
    if let weather = params.weatherHint {
      system.append("Clima real agora: \(weather). Cite temperatura e lugar se perguntarem.")
    }
    if let music = params.musicHint, !music.isEmpty {
      system.append("Usuario pode estar ouvindo: \(music). So comente se a mensagem atual for sobre musica.")
    }
    if let life = params.lifeMode, !life.isEmpty {
      system.append(CompanionLifeMode.parse(life).llmToneHint)
      if CompanionLifeMode.parse(life) == .indoor, let gaming = params.gamingStatus, !gaming.isEmpty {
        system.append("Status Xbox agora: \(gaming). Comente so se couber no modo sofá/lazer.")
      }
    }

    var messages: [[String: String]] = [["role": "system", "content": system.joined(separator: " ")]]
    // Pouco histórico: modelos free grudam no tema antigo.
    for turn in params.history.suffix(4) {
      messages.append(["role": turn.role, "content": turn.content])
    }
    let user = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload: String
    if let user, !user.isEmpty {
      payload = "Mensagem atual (responda isto; ignore assunto antigo se mudou de tema): \(user)"
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
      "temperature": 0.65,
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

  /// Remove thinking / meta e devolve só a fala do personagem.
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
        return words >= 2 && words <= 28
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

    // Junta linhas úteis; descarta gritos vazios no começo.
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
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return badLine.firstMatch(in: text, options: [], range: range) != nil || text.count > 180
  }
}
