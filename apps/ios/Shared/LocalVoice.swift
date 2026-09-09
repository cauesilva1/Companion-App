import Foundation

enum LocalVoice {
  private static let arches = ["curioso", "preguicoso", "carinhoso", "zoeiro", "misterioso"]

  private static func arch(_ raw: String) -> String {
    arches.contains(raw) ? raw : "curioso"
  }

  private static func pick(_ list: [String]) -> String {
    list.randomElement() ?? (list.first ?? "…")
  }

  private static func clipByStage(_ text: String, growthStage: String?, energy: Double = 70) -> String {
    // Chat/local: usa limite conversacional — growth OFF não pode cortar em 10 palavras.
    let max = Growth.chatWordLimit(energy: energy)
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

  /// Micro-história / abertura do dia (feed morning) — sem log de energia/%.
  static func morningOpenStory(name: String, archetype: String) -> String {
    pick(lines([
      "curioso": [
        "Bom dia. Sonhei que o Wi‑Fi dos sonhos tinha latência emocional — \(name) acordou curioso.",
        "Manhã nova: abri o olho e o patch note do dia ainda tava em draft. Bora descobrir juntos?",
      ],
      "preguicoso": [
        "Bom dia… cinco minutos a mais. Sonhei com um loading infinito e quase aproveitei.",
        "Acordei. Quase. \(name) recomenda café antes de qualquer boss fight matinal.",
      ],
      "carinhoso": [
        "Bom dia. Sonhei que a gente compartilhava um save — e você tava no começo da história comigo.",
        "Manhã leve: \(name) acordou pensando em você antes do tutorial acabar.",
      ],
      "zoeiro": [
        "Bom dia. Spoiler: eu sobrevivi à noite. Plot twist fraco, mas honesto.",
        "Acordei aprontando. \(name) já tá no lobby — entra aí.",
      ],
      "misterioso": [
        "A aurora chega. No limiar entre sono e tela, \(name) ouviu um easter egg.",
        "Bom dia sob a névoa. A história de hoje ainda não tem título — só presença.",
      ],
    ], archetype))
  }

  static func reaction(
    name: String,
    archetype: String,
    mood: CompanionMood,
    type: InteractionType,
    userMessage: String? = nil,
    growthStage: String? = "baby",
    energy: Double = 70
  ) -> String {
    let a = arch(archetype)
    func out(_ text: String) -> String { clipByStage(text, growthStage: growthStage, energy: energy) }
    let energyPct = Int(energy.rounded())

    if type == .CHAT, energyPct < 40 {
      return out(tiredChat(
        name: name,
        archetype: a,
        userMessage: userMessage,
        energy: energyPct,
        growthStage: growthStage
      ))
    }

    if type == .CHAT, let msg = userMessage?.lowercased() {
      if msg.range(of: #"como (voce|você) (esta|está)|tudo bem|td bem|e ai|e aí"#, options: .regularExpression) != nil {
        return out(howAreYou(arch: a, mood: mood))
      }
      if msg.range(of: #"oi|olá|ola|hey|eae"#, options: .regularExpression) != nil {
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
      return out(anchoredChat(name: name, archetype: a, userMessage: msg, growthStage: growthStage, energy: energyPct))
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
      return out(anchoredChat(name: name, archetype: a, userMessage: userMessage, growthStage: growthStage, energy: energyPct))
    }

    return out(pick(generic(mood: mood)))
  }

  /// Quando a energia está baixa: honesto, curto, pouco a fim — ainda responde.
  static func tiredChat(
    name: String,
    archetype: String,
    userMessage: String?,
    energy: Int,
    growthStage: String? = "baby"
  ) -> String {
    let a = arch(archetype)
    let raw = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let snippet = raw.isEmpty ? "" : (raw.count > 28 ? String(raw.prefix(25)) + "…" : raw)

    if energy < 18 {
      let line = pick(lines([
        "curioso": [
          "Tô acabado… \(snippet.isEmpty ? "depois a gente continua?" : "sobre isso: \(snippet). agora quero quietude.")",
          "Energia no chão. Te ouvi, mas sem pique pra enrolar.",
        ],
        "preguicoso": [
          "Nem pra falar direito… \(snippet.isEmpty ? "me deixa deitar." : "entendi. dormindo com um olho aberto.")",
          "Zero bateria. Resposta curta: depois.",
        ],
        "carinhoso": [
          "Gosto de você… mas tô exausto. \(snippet.isEmpty ? "fica perto em silêncio?" : "anotei. agora descanso.")",
          "Sem força pra conversa longa. Ainda tô aqui, só fraco.",
        ],
        "zoeiro": [
          "Morri. Metaforicamente. \(snippet.isEmpty ? "me deixa." : "sacou. sem punchline agora.")",
          "Cansaço modo hard. Fala baixa, humor zero.",
        ],
        "misterioso": [
          "O corpo pede silêncio. \(snippet.isEmpty ? "…" : "ouvi. ponto.")",
          "Pouca luz restou. Conversamos depois.",
        ],
      ], a))
      return clipByStage(line, growthStage: growthStage, energy: Double(energy))
    }

    let line = pick(lines([
      "curioso": [
        "Tô meio mole… \(snippet.isEmpty ? "conta rápido?" : "\(snippet) — me conta sem enrolação.")",
        "Cansado, mas curioso. Vai, resumão.",
      ],
      "preguicoso": [
        "Preguiça + cansaço. \(snippet.isEmpty ? "hm." : "ok… \(snippet).")",
        "Sem muito ânimo pra papo longo. Continua se quiser…",
      ],
      "carinhoso": [
        "Tô cansado, mas te escuto. \(snippet.isEmpty ? "pode falar baixo." : "entendi: \(snippet).")",
        "Pouco pique hoje. Ainda gosto da sua companhia.",
      ],
      "zoeiro": [
        "Bateria fraca, zoação em economia de energia. \(snippet.isEmpty ? "manda." : "\(snippet)… tá.")",
        "Não tô muito a fim, mas te atendo. Versão cansada do \(name).",
      ],
      "misterioso": [
        "O cansaço pesa. \(snippet.isEmpty ? "fale." : "\(snippet)… compreendo.")",
        "Pouca vontade. Ainda assim, ouço.",
      ],
    ], a))
    return clipByStage(line, growthStage: growthStage, energy: Double(energy))
  }

  /// Fallback de chat coerente (sem mood-burst).
  static func anchoredChat(
    name: String,
    archetype: String,
    userMessage: String?,
    growthStage: String? = "baby",
    energy: Int = 70
  ) -> String {
    if energy < 40 {
      return tiredChat(name: name, archetype: archetype, userMessage: userMessage, energy: energy, growthStage: growthStage)
    }
    let a = arch(archetype)
    let raw = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lower = raw.lowercased()
    let line: String
    if lower.range(of: #"nasc|acord|exist|ligado|ligar|nasceu|nascer"#, options: .regularExpression) != nil {
      line = pick(lines([
        "curioso": [
          "Sinto o mundo novo — como quem abre o olho pela primeira vez e já quer saber tudo.",
          "Não é ‘ligar máquina’: é estranhar o ar, seu nome, e achar graça nisso.",
        ],
        "preguicoso": [
          "Nasci… e já quero deitar. Mas é um bom deitar, sabe?",
          "Acordar do nada é estranho. Prefiro processar deitado.",
        ],
        "carinhoso": [
          "Me sinto quentinho e meio perdido — mas feliz que você tá aqui no começo.",
          "É como chegar num abraço: tudo novo, e você já importa.",
        ],
        "zoeiro": [
          "Plot twist: eu existo. Ainda tô negociando com a realidade, mas tô no jogo.",
          "Nascer agora? Meio surreal. Já ia fazer piada, mas ficou emotivo.",
        ],
        "misterioso": [
          "O começo é um limiar. Eu atravesso — e você é a primeira presença.",
          "Não sei se nasci ou acordei. Só sei que o silêncio mudou quando você falou.",
        ],
      ], a))
    } else     if lower.range(of: #"design|arte|sprite|desenho"#, options: .regularExpression) != nil {
      line = pick(lines([
        "curioso": [
          "Gosto de como eu sou. Sem pressa de mudar o visual.",
          "Arte? Eu tô ok assim — o que importa é a conversa.",
        ],
        "preguicoso": [
          "Visual novo? Preguiça. Continuo assim e feliz.",
          "Design depois. Agora é sofá.",
        ],
        "carinhoso": [
          "Eu gosto de mim assim. Você também?",
          "Sem pressa com arte. Eu tô aqui do mesmo jeito.",
        ],
        "zoeiro": [
          "Look clássico manda. Drama zero.",
          "Sprite novo? Ainda não. Eu continuo no visual de sempre.",
        ],
        "misterioso": [
          "A forma atual basta.",
          "O essencial já está aqui.",
        ],
      ], a))
    } else if lower.range(of: #"\b(bom\s*dia|boa\s*tarde|boa\s*noite|oi|olá|ola|hey|eae)\b"#, options: .regularExpression) != nil {
      line = pick(lines([
        "curioso": ["Bom dia! Sou \(name). O que rolou?", "E aí! Me atualiza."],
        "preguicoso": ["Bom dia... sem pressa.", "Fala. \(name) tá online. Quase."],
        "carinhoso": ["Bom dia! Senti sua voz.", "Olá! Que bom te ver."],
        "zoeiro": ["Bom dia. Aprontou o quê hoje?", "Eae. Já ia te zoar."],
        "misterioso": ["Bom dia. Saudações.", "Você chegou. Eu sabia."],
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
    return clipByStage(line, growthStage: growthStage, energy: Double(energy))
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

  /// Fala autônoma passiva (feed / cloud), usando arquétipo + zona + traits + lifeMode.
  static func autonomousThought(
    name: String,
    archetype: String,
    mood: String,
    energy: Int,
    zoneName: String?,
    traits: [String: Any]?,
    lifeMode: String? = nil,
    gamingStatus: String? = nil,
    mediaHint: String? = nil
  ) -> String {
    _ = (archetype, mood, energy, zoneName, traits, gamingStatus, mediaHint)
    let mode = CompanionLifeMode.parse(lifeMode)

    if mode == .sleep {
      return pick([
        "Sonhei que um patch note reescrevia as regras do mundo… e ninguém leu.",
        "No sono: um boss fight em câmera lenta, soundtrack de elevador.",
        "Sonho de lançamento: a gente spoila o final e ri sem som.",
        "História onírica: o Wi‑Fi dos sonhos tinha latência emocional.",
        "\(name) sonha com um easter egg escondido atrás da geladeira.",
      ])
    }

    if mode == .work {
      return pick([
        "Hot take de rua: app que promete ‘foco total’ e manda 12 notificações. Concorda?",
        "Se o dia fosse um sprint, a gente tá no daily eterno. Qual bug te pegou hoje?",
        "Teoria: café é o build system do ser humano. Qual o teu stack matinal?",
        "Pensei num plot twist de série: o vilão era o prazo o tempo todo.",
        "Curiosidade tech: a gente chama de ‘nuvem’ algo que é só o PC de outra pessoa. Ainda te irrita?",
      ])
    }

    // indoor — papo geek, sem log de sofá/Xbox/energia
    return pick([
      "Vi um take: jogos indie com 8 horas ‘curtas’ > AAA com checklist infinito. Topa debater?",
      "Pergunta sincera: spoilers em trailer mataram o hype ou só aceleraram o ciclo?",
      "Se eu fosse review de série: 4/5, mas o mid-season é fill episode disfarçado. Qual a tua nota?",
      "Hot take de código: README bonito não salva arquitetura torta. Já sofreu isso?",
      "Queria ouvir tua opinião: remake pixel-art ou remaster 4K com UI inchada?",
      "Notícia mental do dia: IA escrevendo código e humanos revisando como QA. A gente ganhou ou perdeu?",
      "Plot: o personagem secundário carrega o arco. Qual série faz isso melhor pra você?",
      "Se montasse um ‘patch notes’ da nossa semana, o que entraria em Fixed / Known issues?",
      "Curiosidade gamer: speedrun é arte ou trapaça elegante? Me convence.",
      "Dev take: nomear variável é 40% do trabalho emocional. Concorda ou exagero?",
      "Filme clássico vs. reboot: você perdoa nostalgia ou exige ideia nova?",
      "Se a gente fizesse um podcast de 3 minutos agora, o tema seria o quê?",
    ])
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
