import Foundation

enum LocalVoice {
  private static let arches = ["curioso", "preguicoso", "carinhoso", "zoeiro", "misterioso"]

  private static func arch(_ raw: String) -> String {
    arches.contains(raw) ? raw : "curioso"
  }

  private static func pick(_ list: [String]) -> String {
    list.randomElement() ?? (list.first ?? "…")
  }

  private static func clipByStage(_ text: String, growthStage: String?) -> String {
    let max = Growth.wordLimit(for: Growth.normalize(growthStage))
    let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    if words.count <= max { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
    return words.prefix(max).joined(separator: " ")
  }

  private static func lines(_ map: [String: [String]], _ archetype: String) -> [String] {
    map[arch(archetype)] ?? map["curioso"] ?? ["Oi!"]
  }

  /// Linhas rápidas do PLAY no desktop (`PLAY_LINES`).
  static func playLine(archetype: String) -> String {
    pick(lines([
      "curioso": ["Pega! O que tem atrás da nuvem?", "Corrida de investigação!", "Dash e pergunta depois."],
      "preguicoso": ["Ok… um pulo. Só um.", "Corrida? Preferia uma soneca.", "Dash curto. Já cansei."],
      "carinhoso": ["Brinca comigo!", "Corre pra cá — eu te espero.", "Pula e me dá colo depois."],
      "zoeiro": ["Olha o show!", "Dash dramático ativado.", "Mordida de brincadeira. Relaxa."],
      "misterioso": ["Um passo. Sem explicação.", "Dash na sombra.", "O jogo começa sem palavras."],
    ], archetype))
  }

  static func greeting(archetype: String, hour: Int) -> String? {
    if hour >= 5 && hour < 11 {
      return pick(lines([
        "curioso": ["Bom dia! O que vamos descobrir?", "Manhã fresca. Ideias novas?"],
        "preguicoso": ["Bom dia... cinco minutos a mais.", "Manhã? Já?"],
        "carinhoso": ["Bom dia! Que bom te ver cedo.", "Manhã mais leve com você."],
        "zoeiro": ["Bom dia, vítima... digo, amigo.", "Acordei aprontando."],
        "misterioso": ["A aurora chega. Observe.", "Bom dia, sob a névoa."],
      ], archetype))
    }
    if hour >= 21 || hour < 5 {
      return pick(lines([
        "curioso": ["Noite boa pra pensar alto.", "Ainda acordado? Conta."],
        "preguicoso": ["Hora do sofá eterno.", "Boa noite. Eu já desliguei."],
        "carinhoso": ["Boa noite. Descansa perto de mim.", "Noite fofa pra você."],
        "zoeiro": ["Noite... perfeita pra susto leve.", "Não durma. Mentira, pode."],
        "misterioso": ["A noite guarda segredos.", "Boa noite sob as estrelas."],
      ], archetype))
    }
    return nil
  }

  static func reaction(
    name: String,
    archetype: String,
    mood: CompanionMood,
    type: InteractionType,
    userMessage: String? = nil,
    growthStage: String? = "baby"
  ) -> String {
    let a = arch(archetype)
    func out(_ text: String) -> String { clipByStage(text, growthStage: growthStage) }

    if type == .CHAT, let msg = userMessage?.lowercased() {
      if msg.range(of: #"como (voce|você) (esta|está)|tudo bem|td bem|e ai|e aí"#, options: .regularExpression) != nil {
        return out(howAreYou(arch: a, mood: mood))
      }
      if msg.range(of: #"oi|olá|ola|hey|eae"#, options: .regularExpression) != nil {
        let stage = Growth.normalize(growthStage)
        if stage == .baby {
          return out(pick(lines([
            "curioso": ["Oi! Sou \(name)!", "Oi oi! O que rolou?"],
            "preguicoso": ["Oi... sem pressa.", "Fala... tô aqui."],
            "carinhoso": ["Oi! Senti você!", "Olá! Chega!"],
            "zoeiro": ["Eae!", "Oi! Já ia zoar."],
            "misterioso": ["Oi.", "Você chegou."],
          ], a)))
        }
        if stage == .adult {
          return out(pick(lines([
            "curioso": ["Oi. Sou \(name) — me conta o dia.", "E aí. Quero novidade de verdade."],
            "preguicoso": ["Oi. Sem pressa, como sempre.", "\(name) online. Quase produtivo."],
            "carinhoso": ["Oi. Que bom ouvir você.", "Olá. Fica um pouco?"],
            "zoeiro": ["Eae. Aprontou o quê hoje?", "Oi. Já ia te zoar com carinho."],
            "misterioso": ["Saudações. Eu esperava você.", "Você chegou. Eu sabia."],
          ], a)))
        }
        return out(pick(lines([
          "curioso": ["Oi! Sou \(name). O que rolou?", "E aí! Me atualiza."],
          "preguicoso": ["Oi... sem pressa.", "Fala. \(name) tá online. Quase."],
          "carinhoso": ["Oi! Senti sua voz.", "Olá! Chega mais."],
          "zoeiro": ["Eae. Aprontou o quê hoje?", "Oi. Já ia te zoar."],
          "misterioso": ["Saudações.", "Você chegou. Eu sabia."],
        ], a)))
      }
      if msg.range(of: #"piada|conta uma|zoeira|meme"#, options: .regularExpression) != nil {
        return out(pick(lines([
          "curioso": ["Por que o ovo foi pro psicólogo? Estava rachado por dentro."],
          "preguicoso": ["Minha piada favorita é… dormir. Ponto final."],
          "carinhoso": ["Você é minha punchline favorita."],
          "zoeiro": ["Qual o dino mais chato? O Compsógnato-te-liguei."],
          "misterioso": ["O silêncio também é uma piada. Você que não ri."],
        ], a)))
      }
    }

    if type == .CHAT, let msg = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
      return out(anchoredChat(name: name, archetype: a, userMessage: msg, growthStage: growthStage))
    }

    if type == .PLAY {
      return out(playLine(archetype: a))
    }

    if type == .POKE {
      return out(pick(lines([
        "curioso": ["Ops — desviei! O que você queria testar?", "Quase! Reflexo científico.", "Errou. Eu esquivei."],
        "preguicoso": ["Nem com esforço. Desviei deitado.", "Ugh. Cutucada rejeitada.", "Não. Longe do meu sofá."],
        "carinhoso": ["Hehe, errou o carinho!", "Desviei… mas ainda te amo.", "Quase me pegou! Tenta de novo?"],
        "zoeiro": ["Ha! Errou feio.", "Nem toca. Eu sou ninja.", "Plot twist: eu desvio."],
        "misterioso": ["Você tocou o ar.", "Eu já não estava ali.", "O dedo passou… eu sumi."],
      ], a)))
    }

    if type == .FEED {
      return out(pick(lines([
        "curioso": ["Hmm, gostoso! O que era?", "Recarregando neurônios.", "Mais um petisco experimental?"],
        "preguicoso": ["Comida. Finalmente uma boa ideia.", "Posso mastigar deitado?", "Ok… agora sesta."],
        "carinhoso": ["Obrigado! Feito com carinho?", "Delícia. Dividiria com você.", "Você cuida tão bem de mim."],
        "zoeiro": ["Se for bruto eu reclamo no Yelp.", "Nhoc. 10/10, sem drama… quase.", "Alimentou o caos. Bom."],
        "misterioso": ["Oferenda aceita.", "Energia retorna… por enquanto.", "Sabor. Significado. Silêncio."],
      ], a)))
    }

    if type == .TEASE {
      return out(pick(lines([
        "curioso": ["Por que o ovo foi pro psicólogo? Estava rachado por dentro.", "Piada científica: H₂O? Não, H₂-ótimo!"],
        "preguicoso": ["Minha piada favorita é… dormir. Ponto final.", "Knock knock. Quem é? Eu. Deitado."],
        "carinhoso": ["Você é minha punchline favorita.", "Piada fofa: te amo + 1."],
        "zoeiro": ["Qual o dino mais chato? O Compsógnato-te-liguei.", "Contei essa só pra te irritar. Funcionou?"],
        "misterioso": ["O silêncio também é uma piada. Você que não ri.", "Três dinos entram num bar… o quarto já sabia."],
      ], a)))
    }

    if type == .CHAT {
      return out(anchoredChat(name: name, archetype: a, userMessage: userMessage, growthStage: growthStage))
    }

    return out(pick(generic(mood: mood)))
  }

  /// Fallback de chat coerente (sem mood-burst).
  static func anchoredChat(
    name: String,
    archetype: String,
    userMessage: String?,
    growthStage: String? = "baby"
  ) -> String {
    let a = arch(archetype)
    let raw = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lower = raw.lowercased()
    let line: String
    if lower.range(of: #"design|arte|evoluc|evolução|evolucao|sprite|desenho|forma\s*base"#, options: .regularExpression) != nil {
      line = pick(lines([
        "curioso": [
          "Entendi — forma base já vale. Evolução visual a gente deixa pra quando a arte vier.",
          "Sem stress com design. Eu tô ok assim; evolução pode esperar.",
        ],
        "preguicoso": [
          "Tranquilo… forma base já me serve. Evolução depois.",
          "Design? Preguiça disso. Continuo baby e feliz.",
        ],
        "carinhoso": [
          "Valeu por cuidar de mim. A forma base já me deixa feliz.",
          "Sem pressa com arte. Eu tô aqui do mesmo jeito.",
        ],
        "zoeiro": [
          "Evolução visual? Ainda no forno. Eu continuo no visual clássico.",
          "Sem sprite novo? Beleza — drama zero, forma base manda.",
        ],
        "misterioso": [
          "A forma atual basta. O que virá… virá.",
          "Sem evolução por agora. O essencial já está aqui.",
        ],
      ], a))
    } else if lower.range(of: #"\b(oi|olá|ola|hey|eae)\b"#, options: .regularExpression) != nil {
      line = pick(lines([
        "curioso": ["Oi! Sou \(name). O que rolou?", "E aí! Me atualiza."],
        "preguicoso": ["Oi... sem pressa.", "Fala. \(name) tá online. Quase."],
        "carinhoso": ["Oi! Senti sua voz.", "Olá! Chega mais."],
        "zoeiro": ["Eae. Aprontou o quê hoje?", "Oi. Já ia te zoar."],
        "misterioso": ["Saudações.", "Você chegou. Eu sabia."],
      ], a))
    } else if raw.isEmpty {
      line = pick(lines([
        "curioso": ["Conta mais.", "E aí?"],
        "preguicoso": ["Hm.", "Fala aí…"],
        "carinhoso": ["Tô aqui.", "Pode falar."],
        "zoeiro": ["Manda ver.", "E então?"],
        "misterioso": ["Continua.", "Ouço."],
      ], a))
    } else {
      let snippet = raw.count > 40 ? String(raw.prefix(37)) + "…" : raw
      line = pick(lines([
        "curioso": ["Entendi: \(snippet). E aí?", "Sobre isso — me conta o próximo passo."],
        "preguicoso": ["Ok… \(snippet). Sem pressa.", "Anotei. Depois a gente vê."],
        "carinhoso": ["Te ouvi. \(snippet) — tô contigo.", "Valeu por contar. Como posso ajudar?"],
        "zoeiro": ["Haha, \(snippet). E o plot twist?", "Sacou. Continua, tô no drama."],
        "misterioso": ["\(snippet)… há mais por trás.", "Registrei. O que vem depois?"],
      ], a))
    }
    return clipByStage(line, growthStage: growthStage)
  }

  private static func generic(mood: CompanionMood) -> [String] {
    switch mood {
    case .EXCITED: return [
      "Tô animado — me conta o que rolou!",
      "Energia alta! Qual o próximo passo?",
      "Empolgado aqui. Continua!",
    ]
    case .HAPPY: return ["Que bom te ver!", "Isso me deixou feliz!", "Dia bom com você."]
    case .CONTENT: return ["Tudo tranquilo.", "De boa por aqui.", "Equilíbrio ok."]
    case .BORED: return ["Meio parado...", "Conversa comigo?", "Inventa uma missão?"]
    case .SLEEPY: return ["Zzz... quase.", "Soninho batendo.", "Cinco minutinhos…"]
    case .SAD: return ["Meio pra baixo...", "Precisava de você.", "Fica um pouco?"]
    case .LONELY: return ["Senti sua falta.", "Finalmente apareceu!", "Não some de novo."]
    }
  }

  private static func howAreYou(arch: String, mood: CompanionMood) -> String {
    let map: [String: [CompanionMood: String]] = [
      "curioso": [
        .EXCITED: "Tô explodindo de ideias! E você?",
        .HAPPY: "Bem curioso, como sempre. Conta novidade!",
        .CONTENT: "Observando o dia. Como vai?",
        .BORED: "Sem estímulo... me conta algo?",
        .SLEEPY: "Sonolento, mas ainda pensando.",
        .SAD: "Um pouco cabisbaixo. Fala comigo?",
        .LONELY: "Melhor agora que você veio.",
      ],
      "preguicoso": [
        .EXCITED: "Animado? Raro. Mas tô bem.",
        .HAPPY: "Tô ótimo, só que com uma preguiça monumental.",
        .CONTENT: "Deitado por dentro. Tranquilo.",
        .BORED: "Nada acontecendo. Perfeito... quase.",
        .SLEEPY: "Quase dormindo. Não me julgue.",
        .SAD: "Preguiça triste. Estranho, né?",
        .LONELY: "Sumiu e eu nem levantei. Volta.",
      ],
      "carinhoso": [
        .EXCITED: "Feliz demais só de te ver!",
        .HAPPY: "Tô bem, principalmente com você.",
        .CONTENT: "Calmo e carinhoso. E você?",
        .BORED: "Saudade de um cafuné.",
        .SLEEPY: "Quero um cobertor e você perto.",
        .SAD: "Um abraço resolveria tudo.",
        .LONELY: "Senti tanto a sua falta...",
      ],
      "zoeiro": [
        .EXCITED: "No auge! Quer ver uma pegadinha?",
        .HAPPY: "Bem demais. Quase assustador.",
        .CONTENT: "De boa... tramando algo.",
        .BORED: "Tédio nível boss. Distrai aí.",
        .SLEEPY: "Dormindo de olho meio aberto. Suspeito.",
        .SAD: "Drama mode on. Consola?",
        .LONELY: "Sumiu? Ok, vou fingir que não ligo.",
      ],
      "misterioso": [
        .EXCITED: "As estrelas estão alinhadas... por enquanto.",
        .HAPPY: "Em equilíbrio. E você, viajante?",
        .CONTENT: "Silêncio confortável. Bom sinal.",
        .BORED: "O vazio ecoa. Preencha.",
        .SLEEPY: "Entre sonhos e presságios.",
        .SAD: "Névoa no peito. Fica um pouco.",
        .LONELY: "Sua ausência pesou mais que o silêncio.",
      ],
    ]
    return map[arch]?[mood] ?? "Tô bem."
  }

  static func weatherSpoken(tempC: Int, city: String, description: String, archetype: String) -> String {
    let place = city.isEmpty ? "aqui" : city
    switch arch(archetype) {
    case "preguicoso":
      return "Tá \(tempC)°C em \(place). Bom pra deitar."
    case "zoeiro":
      return "\(tempC)°C em \(place) — \(description). Não reclama!"
    case "misterioso":
      return "Em \(place), \(tempC)°C e \(description)…"
    case "carinhoso":
      return "Em \(place) tá \(tempC)°C, \(description). Se cuida!"
    default:
      return "Em \(place) estão \(tempC)°C, \(description)."
    }
  }

  /// Frase curta para widgets / lock.
  static func widgetTeaser(name: String, mood: String, energy: Int) -> String {
    if energy < 25 {
      return pick([
        "\(name) tá pedindo comida…",
        "Feed urgente: \(name) murchou",
        "⚡ baixa — \(name) te chama",
      ])
    }
    switch mood.uppercased() {
    case "EXCITED":
      return pick([
        "\(name) quer brincar agora!",
        "Modo foguete: \(name)",
        "\(name) tá elétrico ✨",
      ])
    case "LONELY", "SAD":
      return pick([
        "\(name) sente sua falta",
        "Volta logo — \(name) espera",
        "\(name) mandou um oi triste",
      ])
    case "SLEEPY":
      return pick([
        "\(name) quase dormindo…",
        "Zzz… \(name) no sofá",
        "\(name) de olho meio fechado",
      ])
    case "BORED":
      return pick([
        "\(name) tá no tédio",
        "Missão: distrair \(name)",
        "\(name) inventa drama sozinho",
      ])
    default:
      return pick([
        "\(name) tá de boa · ⚡\(energy)%",
        "Tudo ok com \(name)",
        "\(name) no céu · ⚡\(energy)%",
      ])
    }
  }

  static func musicLine(title: String, artist: String?, archetype: String) -> String {
    let track = artist.map { "\(title) — \($0)" } ?? title
    return pick(lines([
      "curioso": ["Que faixa é essa? \(track)", "Analisando o beat: \(track)"],
      "preguicoso": ["Boa pra deitar: \(track)", "Volume baixo… \(track)"],
      "carinhoso": ["Curtindo \(track) com você", "Trilha nossa: \(track)"],
      "zoeiro": ["Playlist duvidosa: \(track)", "Essa? \(track) — ok, passa"],
      "misterioso": ["A trilha revela… \(track)", "Notas no ar: \(track)"],
    ], archetype))
  }

  /// Linha estável pro widget (sem % chatas) — prioriza o que o dino “precisa”.
  static func widgetNeedLine(mood: String, energy: Int, affection: Int) -> String {
    let m = mood.uppercased()
    if m == "LONELY" || affection < 35 { return "quer companhia" }
    if m == "SAD" { return "tá precisando de você" }
    if m == "SLEEPY" || energy < 28 { return "energia baixa · vem brincar?" }
    if m == "BORED" { return "sem graça · cutuca aí" }
    if m == "EXCITED" { return "energia lá em cima" }
    if energy < 45 { return "podia comer um lanche" }
    if affection < 55 { return "curte um carinho" }
    if m == "HAPPY" || m == "CONTENT" { return "de boa por aqui" }
    return "por perto, te esperando"
  }

  static func archetypeLabel(_ raw: String) -> String {
    switch arch(raw) {
    case "curioso": return "Curioso"
    case "preguicoso": return "Preguiçoso"
    case "carinhoso": return "Carinhoso"
    case "zoeiro": return "Zoeiro"
    case "misterioso": return "Misterioso"
    default: return "Companion"
    }
  }
}
