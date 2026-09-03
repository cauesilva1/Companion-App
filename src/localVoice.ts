import { InteractionType, Mood } from "@prisma/client";

export type Archetype = "curioso" | "preguicoso" | "carinhoso" | "zoeiro" | "misterioso";
export type PrankKind = "shake" | "bounce" | "notify" | "tease-sound" | "hide-and-seek";

export interface LocalVoiceParams {
  name: string;
  archetype: string;
  mood: Mood;
  type: InteractionType;
  userMessage?: string | null;
  hour?: number;
}

const ARCH: Archetype[] = ["curioso", "preguicoso", "carinhoso", "zoeiro", "misterioso"];

function asArch(raw: string | undefined): Archetype {
  return ARCH.includes(raw as Archetype) ? (raw as Archetype) : "curioso";
}

function pick(list: string[]): string {
  return list[Math.floor(Math.random() * list.length)];
}

const PLAY: Record<Archetype, string[]> = {
  curioso: ["E se a gente inventar uma regra nova?", "Isso desperta ideias!"],
  preguicoso: ["Ok... mas depois eu deito.", "Esforço demais. Ainda assim foi legal."],
  carinhoso: ["Adoro brincar com você!", "Mais um pouquinho, por favor?"],
  zoeiro: ["Ha! Quase te ganhei.", "Isso foi épico. Replay?"],
  misterioso: ["O jogo revela quem você é...", "Interessante movimento."],
};

const POKE: Record<Archetype, string[]> = {
  curioso: ["Hmm? O que tem aí?", "Cutucou o quê exatamente?"],
  preguicoso: ["...vai embora, tô de boa.", "Cinco minutos de paz, por favor."],
  carinhoso: ["Hehe, cócegas!", "Fico feliz com qualquer carinho."],
  zoeiro: ["Ei! Guerra de cutucadas!", "Você pediu por isso."],
  misterioso: ["...sinto sua presença.", "Não me provoque sem motivo."],
};

const GENERIC: Record<Mood, string[]> = {
  EXCITED: ["Uhuul!", "Melhor momento!"],
  HAPPY: ["Que bom te ver!", "Isso me deixou feliz!"],
  CONTENT: ["Tudo tranquilo.", "De boa por aqui."],
  BORED: ["Meio parado...", "Conversa comigo?"],
  SLEEPY: ["Zzz... quase.", "Soninho batendo."],
  SAD: ["Meio pra baixo...", "Precisava de você."],
  LONELY: ["Senti sua falta.", "Finalmente apareceu!"],
};

const HOW_ARE_YOU: Record<Archetype, Record<Mood, string>> = {
  curioso: {
    EXCITED: "Tô explodindo de ideias! E você?",
    HAPPY: "Bem curioso, como sempre. Conta novidade!",
    CONTENT: "Observando o dia. Como vai?",
    BORED: "Sem estímulo... me conta algo?",
    SLEEPY: "Sonolento, mas ainda pensando.",
    SAD: "Um pouco cabisbaixo. Fala comigo?",
    LONELY: "Melhor agora que você veio.",
  },
  preguicoso: {
    EXCITED: "Animado? Raro. Mas tô bem.",
    HAPPY: "Tô ótimo, só que com uma preguiça monumental.",
    CONTENT: "Deitado por dentro. Tranquilo.",
    BORED: "Nada acontecendo. Perfeito... quase.",
    SLEEPY: "Quase dormindo. Não me julgue.",
    SAD: "Preguiça triste. Estranho, né?",
    LONELY: "Sumiu e eu nem levantei. Volta.",
  },
  carinhoso: {
    EXCITED: "Feliz demais só de te ver!",
    HAPPY: "Tô bem, principalmente com você.",
    CONTENT: "Calmo e carinhoso. E você?",
    BORED: "Saudade de um cafuné.",
    SLEEPY: "Quero um cobertor e você perto.",
    SAD: "Um abraço resolveria tudo.",
    LONELY: "Senti tanto a sua falta...",
  },
  zoeiro: {
    EXCITED: "No auge! Quer ver uma pegadinha?",
    HAPPY: "Bem demais. Quase assustador.",
    CONTENT: "De boa... tramando algo.",
    BORED: "Tédio nível boss. Distrai aí.",
    SLEEPY: "Dormindo de olho meio aberto. Suspeito.",
    SAD: "Drama mode on. Consola?",
    LONELY: "Sumiu? Ok, vou fingir que não ligo.",
  },
  misterioso: {
    EXCITED: "As estrelas estão alinhadas... por enquanto.",
    HAPPY: "Em equilíbrio. E você, viajante?",
    CONTENT: "Silêncio confortável. Bom sinal.",
    BORED: "O vazio ecoa. Preencha.",
    SLEEPY: "Entre sonhos e presságios.",
    SAD: "Névoa no peito. Fica um pouco.",
    LONELY: "Sua ausência pesou mais que o silêncio.",
  },
};

export function localGreeting(archetype: string, hour: number): string | undefined {
  const arch = asArch(archetype);
  if (hour >= 5 && hour < 11) {
    return pick({
      curioso: ["Bom dia! O que vamos descobrir?", "Manhã fresca. Ideias novas?"],
      preguicoso: ["Bom dia... cinco minutos a mais.", "Manhã? Já?"],
      carinhoso: ["Bom dia! Que bom te ver cedo.", "Manhã mais leve com você."],
      zoeiro: ["Bom dia, vítima... digo, amigo.", "Acordei aprontando."],
      misterioso: ["A aurora chega. Observe.", "Bom dia, sob a névoa."],
    }[arch]);
  }
  if (hour >= 21 || hour < 5) {
    return pick({
      curioso: ["Noite boa pra pensar alto.", "Ainda acordado? Conta."],
      preguicoso: ["Hora do sofá eterno.", "Boa noite. Eu já desliguei."],
      carinhoso: ["Boa noite. Descansa perto de mim.", "Noite fofa pra você."],
      zoeiro: ["Noite... perfeita pra susto leve.", "Não durma. Mentira, pode."],
      misterioso: ["A noite guarda segredos.", "Boa noite sob as estrelas."],
    }[arch]);
  }
  return undefined;
}

export function idleMissLine(archetype: string): string {
  return pick({
    curioso: ["Sumiu? Eu fiquei inventando teorias.", "Voltou! Conta o que rolou."],
    preguicoso: ["...você demorou. Eu quase dormi.", "Ah, voltou. Sem pressa da próxima."],
    carinhoso: ["Senti sua falta de verdade.", "Finalmente! Fica um pouquinho."],
    zoeiro: ["Sumiu e eu quase aprontei sozinho.", "Olha quem lembrou que eu existo."],
    misterioso: ["O silêncio falou por você.", "Sua ausência deixou rastros."],
  }[asArch(archetype)]);
}

export function activityLabel(
  activity: string,
  timeOfDay: string
): string {
  if (activity === "listening_music") return "Ouvindo música…";
  if (activity === "idle") return "Ocioso";
  if (activity === "playing") return "Brincando";
  if (activity === "chatting") return "Conversando";
  if (timeOfDay === "morning") return "Manhã tranquila";
  if (timeOfDay === "evening") return "Entardecer";
  if (timeOfDay === "night") return "Noite calma";
  return "Presente";
}

export function localReaction(params: LocalVoiceParams): string {
  const arch = asArch(params.archetype);
  const { type, mood, userMessage, name } = params;

  if (type === "CHAT" && userMessage) {
    const lower = userMessage.toLowerCase();
    if (/como (voce|você) (esta|está)|tudo bem|td bem|e ai|e aí/.test(lower)) {
      return HOW_ARE_YOU[arch][mood];
    }
    if (/oi|olá|ola|hey|eae/.test(lower)) {
      return pick({
        curioso: [`Oi! Sou ${name}. O que rolou?`, "E aí! Me atualiza."],
        preguicoso: ["Oi... sem pressa.", `Fala, ${name} tá online. Quase.`],
        carinhoso: [`Oi! Senti sua voz.`, "Olá! Chega mais."],
        zoeiro: ["Eae. Aprontou o quê hoje?", "Oi. Já ia te zoar."],
        misterioso: ["Saudações.", "Você chegou. Eu sabia."],
      }[arch]);
    }
    if (/apronta|pegadinha|travessura|prega pe[cç]a/.test(lower)) {
      return pick({
        curioso: ["Hmm, experimentando o caos controlado...", "Uma ideia bagunçada surgindo."],
        preguicoso: ["Preguiça de aprontar... mas vá lá.", "Ok. Uma travessura mínima."],
        carinhoso: ["Só se for de leve, prometo!", "Travessura fofa, combinado?"],
        zoeiro: ["Finalmente. Segura aí.", "Missão: bagunça nível 1."],
        misterioso: ["O véu se move...", "Uma sombra passa. Observe."],
      }[arch]);
    }
  }

  if (type === "PLAY") return pick(PLAY[arch]);
  if (type === "POKE") return pick(POKE[arch]);

  return pick(GENERIC[mood]);
}

export function suggestPrank(
  archetype: string,
  userMessage?: string | null,
  pranksEnabled = false
): PrankKind | undefined {
  if (!pranksEnabled) return undefined;
  const arch = asArch(archetype);
  if (!["zoeiro", "preguicoso", "misterioso"].includes(arch)) return undefined;

  const asked =
    !!userMessage && /apronta|pegadinha|travessura|prega pe[cç]a/.test(userMessage.toLowerCase());
  if (!asked && Math.random() > 0.12) return undefined;

  const pool: PrankKind[] =
    arch === "zoeiro"
      ? ["shake", "bounce", "notify", "hide-and-seek", "tease-sound"]
      : arch === "misterioso"
        ? ["hide-and-seek", "notify", "tease-sound"]
        : ["bounce", "tease-sound", "notify"];

  return pick(pool) as PrankKind;
}
