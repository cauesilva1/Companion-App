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

  /// Growth OFF: não inventar que já evoluiu.
  static func isFalseEvolution(_ reply: String, growthEnabled: Bool = Growth.isEnabled) -> Bool {
    if growthEnabled { return false }
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

  static func acceptReply(_ reply: String, user: String, growthEnabled: Bool = Growth.isEnabled) -> Bool {
    guard !reply.isEmpty, !isMoodBurst(reply) else { return false }
    if isOffTopic(reply: reply, user: user) { return false }
    if isFalseEvolution(reply, growthEnabled: growthEnabled) { return false }
    return true
  }
}
