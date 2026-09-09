import Foundation

/// Filtros de fala do chat — espelhados em tests/companion-logic/speechFilters.mjs
enum SpeechFilters {
  static func isMusicTopic(_ text: String) -> Bool {
    text.range(
      of: #"m[uú]sica|spotify|playlist|faixa|ouvindo|ouvir|tocando|rap\b|racionais|album|álbum|\bsom\b|track|banda|artista"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  static func isDesignTopic(_ text: String) -> Bool {
    text.range(
      of: #"design|arte|evoluc|evolução|evolucao|sprite|visual|desenho|forma\s*base"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  static func isMoodBurst(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    if trimmed.range(of: #"^(uh+u+l*!*\s*)+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
      return true
    }
    if trimmed.range(
      of: #"modo\s*foguete|melhor\s*momento|que\s*alegria\s*!*$"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil {
      return true
    }
    if trimmed.lowercased().contains("modo foguete") { return true }
    let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    if words.count <= 4 {
      let joined = words.map { String($0).lowercased() }.joined(separator: " ")
      if joined.range(of: #"uhu+l|uhul|eba+|bo+a+|yay|woo+|foguete|alegria|empolg"#, options: .regularExpression) != nil {
        return true
      }
    }
    return false
  }

  static func isOffTopic(reply: String, user: String) -> Bool {
    let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !u.isEmpty else { return false }
    if isMusicTopic(u) { return false }
    let r = reply.lowercased()
    if isMusicTopic(reply) { return true }
    if r.range(of: #"pra ouvir|para ouvir|sugest[aã]o do rap|curtiu.*rap|mais pra ouvir|racionais"#, options: .regularExpression) != nil {
      return true
    }
    if isDesignTopic(u) && isMusicTopic(reply) { return true }
    if u.range(of: #"uhu|foguete|por ?que.*(falou|disse)"#, options: [.regularExpression, .caseInsensitive]) == nil,
       r.range(of: #"express[aã]o espont[aâ]nea|falei uhu|disse uhu|modo foguete"#, options: .regularExpression) != nil {
      return true
    }
    return false
  }

  /// Não inventar evolução (produto sem growth).
  static func isFalseEvolution(_ reply: String, growthEnabled: Bool = false) -> Bool {
    let r = reply.lowercased()
    return r.range(
      of: #"j[aá]\s+evolu|voc[eê]\s+j[aá]\s+evolu|cresce\s+sozinho|eu\s+evolu[ií]|evolui,?\s*s[oó]|forma\s+nova|vire[i]?\s+teen|vire[i]?\s+adulto"#,
      options: .regularExpression
    ) != nil
  }

  static func isStaleAssistantNoise(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.range(
      of: #"express[aã]o espont[aâ]nea|sugest[aã]o do rap|modo foguete|mais pra ouvir|j[aá]\s+evolu|cresce\s+sozinho"#,
      options: .regularExpression
    ) != nil
  }

  /// Log de ambiente (sofá/TV/Xbox/energia) — pensamentos não devem soar assim.
  static func isStatusEnvironmentLog(_ text: String) -> Bool {
    let t = text.lowercased()
    if t.range(
      of: #"t[oô]\s+no\s+sof[aá]|deitado\s+aqui\s+no\s+sof[aá]|sof[aá],\s*tv|tv\s+ligada|xbox\s+offline|xbox\s+ligado|energia\s+\d+%|energia\s+voltando|modo\s+sof[aá]|recarrega\s+no\s+sof[aá]|sof[aá]\s*\+\s*regener"#,
      options: .regularExpression
    ) != nil {
      return true
    }
    var hits = 0
    for needle in ["sofá", "sofa", "tv ligada", "xbox", "energia"] {
      if t.contains(needle) { hits += 1 }
    }
    return hits >= 2
  }

  /// Eco de instrução de prompt / raciocínio do modelo.
  static func isPromptLeak(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.range(
      of: #"fala curta|como pensamento|lifemode:|traits:|here'?s a thinking|thinking process|analyze user|system:|assistant:|gere uma|micro-hist[oó]ria"#,
      options: .regularExpression
    ) != nil
  }

  /// Frase cortada no meio (ex.: termina em "pens").
  static func isTruncatedSpeech(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    let last = trimmed.last!
    let endsOk = ".!?…\"".contains(last) || last == "'" || last == "”" || last == "’"
    if endsOk { return false }
    let lastToken = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last.map(String.init) ?? ""
    let letters = lastToken.filter(\.isLetter)
    if (1...4).contains(letters.count) { return true }
    let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    return words >= 8
  }

  static func acceptAutonomousThought(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !isMoodBurst(t) else { return false }
    if isPromptLeak(t) || isStatusEnvironmentLog(t) || isTruncatedSpeech(t) { return false }
    if isFalseEvolution(t) { return false }
    return true
  }

  static func acceptReply(_ reply: String, user: String, growthEnabled: Bool = false) -> Bool {
    guard !reply.isEmpty, !isMoodBurst(reply) else { return false }
    if isPromptLeak(reply) || isTruncatedSpeech(reply) { return false }
    if isOffTopic(reply: reply, user: user) { return false }
    if isFalseEvolution(reply) { return false }
    return true
  }
}
