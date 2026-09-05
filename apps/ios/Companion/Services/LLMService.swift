import Foundation

enum LLMService {
  private static let nvidiaURL = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
  private static let openrouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
  private static let nvidiaModels = [
    "deepseek-ai/deepseek-v4-pro-0813",
    "nvidia/nemotron-3-super-120b-a12b",
  ]
  private static let openrouterModel = "openrouter/auto"
  private static let timeout: TimeInterval = 12

  private static let badLine = try! NSRegularExpression(
    pattern: #"user\s*says|thinking|analyze|as an ai|system:|assistant:|the user|okay,? the user|let me check|respond in portuguese|fale agora|só a frase"#,
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
  }

  private static var cache: [String: (text: String, at: Date)] = [:]

  static func generate(params: Params, companionId: String, type: InteractionType) async -> String {
    if type != .CHAT {
      return LocalVoice.reaction(
        name: params.name,
        archetype: params.archetype,
        mood: params.mood,
        type: type,
        userMessage: params.userMessage
      )
    }

    let msg = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let cacheKey = "\(companionId)::\(msg.lowercased())"
    if !msg.isEmpty, let hit = cache[cacheKey], Date().timeIntervalSince(hit.at) < 30 {
      return hit.text
    }

    var working = params

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
        if let colored = await tryProviders(messages: buildMessages(working)),
           colored.contains("\(snap.tempC)"),
           !isBad(colored) {
          cache[cacheKey] = (colored, Date())
          return colored
        }
        cache[cacheKey] = (spoken, Date())
        return spoken
      } catch {
        // cai no chat normal / local
      }
    }

    let messages = buildMessages(working)
    if let text = await tryProviders(messages: messages), !isBad(text) {
      if !msg.isEmpty { cache[cacheKey] = (text, Date()) }
      return text
    }

    return LocalVoice.reaction(
      name: params.name,
      archetype: params.archetype,
      mood: params.mood,
      type: .CHAT,
      userMessage: params.userMessage
    )
  }

  private static func tryProviders(messages: [[String: String]]) async -> String? {
    if let key = KeychainStore.get(.nvidia) {
      for model in nvidiaModels {
        if let text = try? await callChat(url: nvidiaURL, apiKey: key, model: model, messages: messages, extraHeaders: nil) {
          return sanitize(text)
        }
      }
    }
    if let key = KeychainStore.get(.openrouter) {
      let headers = [
        "HTTP-Referer": "https://companion.local",
        "X-Title": "Companion iOS",
      ]
      if let text = try? await callChat(
        url: openrouterURL,
        apiKey: key,
        model: openrouterModel,
        messages: messages,
        extraHeaders: headers
      ) {
        return sanitize(text)
      }
    }
    return nil
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
      default: return "Fale curioso, faça perguntas curtas."
      }
    }()

    var system = [
      "Voce e \(params.name), companion virtual e amigo de verdade.",
      "Personalidade: \(params.personality). Arquétipo: \(params.archetype).",
      "Humor agora: \(moodLabel). Energia \(Int(params.energy)), afeto \(Int(params.affection)).",
      tone,
      "Espelhe o jeito de falar do usuario (ritmo, gírias, informalidade, emoji) sem copiar a frase dele.",
      "Pense como um amigo proximo: presente, atento, coerente com o historico.",
      "Responda em portugues do Brasil, primeira pessoa, no maximo 18 palavras.",
      "Nao explique raciocinio. So a fala do personagem.",
    ]
    if !params.memoryNotes.isEmpty {
      system.append("Memoria e estilo: \(params.memoryNotes.prefix(6).joined(separator: "; "))")
    }
    if let weather = params.weatherHint {
      system.append("Clima real agora: \(weather). Cite temperatura e lugar se perguntarem.")
    }

    var messages: [[String: String]] = [["role": "system", "content": system.joined(separator: " ")]]
    for turn in params.history.suffix(6) {
      messages.append(["role": turn.role, "content": turn.content])
    }
    let user = params.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    messages.append(["role": "user", "content": (user?.isEmpty == false) ? user! : "Oi"])
    return messages
  }

  private static func callChat(
    url: URL,
    apiKey: String,
    model: String,
    messages: [[String: String]],
    extraHeaders: [String: String]?
  ) async throws -> String {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    extraHeaders?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let body: [String: Any] = [
      "model": model,
      "messages": messages,
      "max_tokens": 80,
      "temperature": 0.8,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let choices = json?["choices"] as? [[String: Any]]
    let message = choices?.first?["message"] as? [String: Any]
    if let content = message?["content"] as? String, !content.isEmpty {
      return content
    }
    if let text = choices?.first?["text"] as? String, !text.isEmpty {
      return text
    }
    throw URLError(.cannotParseResponse)
  }

  private static func sanitize(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"^["'\s]+|["'\s]+$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .newlines)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
  }

  private static func isBad(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return badLine.firstMatch(in: text, options: [], range: range) != nil || text.count > 180
  }
}
