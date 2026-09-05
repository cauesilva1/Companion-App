import { InteractionType, Mood } from "@prisma/client";
import { localReaction, LocalVoiceParams } from "./localVoice";
import {
  getWeatherSnapshot,
  isWeatherQuestion,
  weatherContextLine,
  weatherSpokenLine,
} from "./weather";
import { effectiveGrowthStage, stageVoiceHint, stageWordLimit, type GrowthStage, GROWTH_ENABLED } from "./growth";
import {
  acceptReply,
  isMusicTopic,
  isMoodBurst,
  isStaleAssistantNoise,
} from "./speechFilters";

const OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL ?? "openrouter/auto";
const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
/** Modelos NVIDIA em ordem de tentativa (build.nvidia.com). */
const NVIDIA_MODELS: string[] = (
  process.env.NVIDIA_MODELS ??
  [
    "deepseek-ai/deepseek-v4-pro-0813",
    "nvidia/nemotron-3-super-120b-a12b",
    "moonshotai/kimi-k3",
    "openai/gpt-oss-20b",
  ].join(",")
)
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const NVIDIA_MODEL = process.env.NVIDIA_MODEL ?? NVIDIA_MODELS[0] ?? "deepseek-ai/deepseek-v4-pro-0813";
/** Primário + no máximo 1 fallback NVIDIA (evita cascata de 4×14s). */
const NVIDIA_TRY_MODELS = Array.from(
  new Set([NVIDIA_MODEL, NVIDIA_MODELS[1]].filter(Boolean) as string[])
).slice(0, 2);
const MAX_TOKENS = 80;
const CHAT_CACHE_MS = 30_000;
const LLM_TIMEOUT_MS = 10_000;

interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

export interface ReactionParams {
  companion: {
    name: string;
    personality: string;
    archetype?: string;
    artStyle?: string;
    growthStage?: string;
  };
  type: InteractionType;
  mood: Mood;
  energy: number;
  affection: number;
  userMessage?: string | null;
  history?: ChatTurn[];
  memoryNotes?: string[];
  screenHint?: string;
  weatherHint?: string;
  musicHint?: string;
  growthEnabled?: boolean;
}

interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

interface OpenAICompatibleResponse {
  choices?: {
    message?: {
      content?: string | null;
      reasoning?: string | null;
      reasoning_content?: string | null;
    };
    text?: string;
  }[];
}

const MOOD_LABELS: Record<Mood, string> = {
  EXCITED: "empolgado(a)",
  HAPPY: "feliz",
  CONTENT: "tranquilo(a)",
  BORED: "entediado(a)",
  SLEEPY: "com sono",
  SAD: "triste",
  LONELY: "sentindo sua falta",
};

const ARCH_TONE: Record<string, string> = {
  curioso: "Fale curioso, faça perguntas curtas, tom animado.",
  preguicoso: "Fale preguicoso e sarcastico, frases curtas e preguicosas.",
  carinhoso: "Fale carinhoso e grudento, tom afetuoso.",
  zoeiro: "Fale zoeiro e dramatico, tom de brincadeira.",
  misterioso: "Fale misterioso e filosofico, tom enigmatico.",
};

const BAD_LINE =
  /user\s*says|thinking|analyze|user input|current mood|personality:|energy:|here's a|here is a|as an ai|contexto:|vinculo|step\s*\d|fale agora|so a frase|só a frase|o usuario|o usuário|mensagem do|system:|assistant:|they'?re asking|the user|okay,? the user|let me check|embedded interaction|assistant role|respond in portuguese/i;

const chatCache = new Map<string, { text: string; at: number }>();

function cacheKey(companionId: string | undefined, message: string) {
  return `${companionId ?? "x"}::${message.trim().toLowerCase()}`;
}

function buildMessages(params: ReactionParams): ChatMessage[] {
  const {
    companion,
    mood,
    userMessage,
    history = [],
    memoryNotes,
    screenHint,
    weatherHint,
    musicHint,
    growthEnabled = GROWTH_ENABLED,
  } = params;
  const arch = companion.archetype ?? "curioso";
  const tone = ARCH_TONE[arch] ?? ARCH_TONE.curioso;
  const stage: GrowthStage = effectiveGrowthStage(companion.growthStage);
  const maxWords = stageWordLimit(stage);
  const msg = userMessage?.trim() ?? "";

  const systemParts = [
    `Voce e ${companion.name}, companion virtual e amigo de verdade.`,
    `Personalidade: ${companion.personality}. Arquétipo: ${arch}.`,
    `Estilo visual (tom): ${companion.artStyle ?? "cartoon"}.`,
    `Humor agora: ${MOOD_LABELS[mood]}.`,
    tone,
    stageVoiceHint(stage),
    `PRIORIDADE: a ultima mensagem do usuario. Responda ao assunto DELA.`,
    `Se o usuario mudou de tema, abandone o assunto anterior (musica, rap, clima, etc).`,
    `Nunca comece com grito vazio (Uhul, Uhuul, que alegria, modo foguete).`,
    `Responda em portugues do Brasil, primeira pessoa, no maximo ${maxWords} palavras.`,
    `Apenas a fala. Sem aspas, sem ingles, sem explicar raciocinio.`,
  ];
  if (!growthEnabled) {
    systemParts.push(
      `Evolucao visual DESLIGADA: voce ainda e so a forma base. Nao diga que ja evoluiu, que cresce sozinho, nem que o usuario te evoluiu.`
    );
    systemParts.push(
      `Se falarem de design/evolucao/arte: seja empatico; forma base ja esta ok; evolucoes visuais podem vir depois — sem inventar progresso.`
    );
  }
  if (memoryNotes?.length) {
    systemParts.push(`Memoria curta (use com naturalidade): ${memoryNotes.slice(0, 6).join("; ")}.`);
  }
  if (screenHint) {
    systemParts.push(`Contexto da tela do usuario agora: ${screenHint}`);
  }
  if (weatherHint) {
    systemParts.push(weatherHint);
    systemParts.push(`Pode usar ate ${Math.max(maxWords, 18)} palavras so nesta resposta de clima.`);
  }
  if (musicHint && isMusicTopic(msg)) {
    systemParts.push(`Usuario pode estar ouvindo: ${musicHint}. So comente se a mensagem atual for sobre musica.`);
  }

  const messages: ChatMessage[] = [{ role: "system", content: systemParts.join(" ") }];
  const cleanHistory = history
    .filter((turn) => turn.role !== "assistant" || (!isMoodBurst(turn.content) && !isStaleAssistantNoise(turn.content)))
    .slice(-4);
  for (const turn of cleanHistory) {
    messages.push({ role: turn.role, content: turn.content });
  }
  const payload = msg
    ? `Mensagem atual (responda isto; ignore assunto antigo se mudou de tema): ${msg}`
    : "Oi";
  messages.push({ role: "user", content: payload });
  return messages;
}

export function sanitizeReaction(raw: string): string | null {
  let text = raw
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/<think>[\s\S]*?<\/think>/gi, " ")
    .replace(/<\/?[^>]+>/g, " ")
    .replace(/^\s*User\s*says\s*:\s*/gim, "")
    .replace(/^\s*Assistant\s*:\s*/gim, "")
    .trim();

  const lines = text
    .split(/\n+/)
    .map((line) =>
      line
        .replace(/^[-*•\d.)\s]+/, "")
        .replace(/^["“']+|["”']+$/g, "")
        .trim()
    )
    .filter(Boolean);

  const candidates = lines.length ? [...lines].reverse() : [text];

  for (let candidate of candidates) {
    candidate = candidate
      .replace(/^User\s*says\s*:\s*/i, "")
      .replace(/^.*Fale agora[^.!?]*[.!]?\s*/i, "")
      .trim();

    if (!candidate || BAD_LINE.test(candidate)) continue;
    const words = candidate.split(/\s+/).filter(Boolean);
    if (words.length < 1 || words.length > 18) continue;
    // Bloqueia meta/inglês que vaza de modelos "reasoning"
    if (
      /\b(the|analyze|mood|energy|personality|input|user|says|asking|okay|check|conversation|history|temperature now|they)\b/i.test(
        candidate
      ) &&
      !/[áàãâéêíóôõúç]/i.test(candidate)
    ) {
      continue;
    }
    // Exige pelo menos algum sinal de PT-BR em respostas longas
    if (words.length >= 4 && !/[áàãâéêíóôõúç]|(\b(não|nao|tá|ta|tô|to|pra|pro|você|voce|meu|minha|uns|tá|quente|frio)\b)/i.test(candidate)) {
      if (/\b(now|they|asking|user|the|okay|let)\b/i.test(candidate)) continue;
    }
    return words.slice(0, 14).join(" ");
  }
  return null;
}

export function isBadReaction(text: string): boolean {
  return (
    !text ||
    BAD_LINE.test(text) ||
    !!text.match(/^User\s*says/i) ||
    /\b(they'?re asking|the user is asking|okay,? the user)\b/i.test(text)
  );
}

function extractText(data: OpenAICompatibleResponse): string {
  const msg = data.choices?.[0]?.message;
  // Nunca usar reasoning como fala — gpt-oss/openrouter-auto vazam thinking em inglês
  const content = (msg?.content ?? "").trim();
  if (content) return content;
  return (data.choices?.[0]?.text ?? "").trim();
}

async function callChatAPI(
  apiUrl: string,
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  extraHeaders?: Record<string, string>,
  gate?: { userMessage: string; growthEnabled: boolean }
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
  try {
    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        ...extraHeaders,
      },
      body: JSON.stringify({
        model,
        messages,
        max_tokens: MAX_TOKENS,
        temperature: 0.65,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    const data = (await response.json()) as OpenAICompatibleResponse;
    const text = extractText(data);
    if (!text) throw new Error("Resposta vazia da API");
    const clean = sanitizeReaction(text);
    if (!clean) throw new Error("Resposta da IA inválida (thinking/meta)");
    if (
      gate &&
      !acceptReply(clean, gate.userMessage, { growthEnabled: gate.growthEnabled })
    ) {
      throw new Error("Resposta rejeitada pelos filtros de fala");
    }
    return clean;
  } finally {
    clearTimeout(timer);
  }
}

function toLocal(params: ReactionParams): string {
  const local: LocalVoiceParams = {
    name: params.companion.name,
    archetype: params.companion.archetype ?? "curioso",
    mood: params.mood,
    type: params.type,
    userMessage: params.userMessage,
    growthStage: params.companion.growthStage,
  };
  return localReaction(local);
}

export async function generateReaction(
  params: ReactionParams,
  companionId?: string
): Promise<string> {
  if (params.type !== "CHAT") {
    return toLocal(params);
  }

  const growthEnabled = params.growthEnabled ?? GROWTH_ENABLED;
  const msg = params.userMessage?.trim() ?? "";
  if (msg) {
    const key = cacheKey(companionId, msg);
    const hit = chatCache.get(key);
    if (hit && Date.now() - hit.at < CHAT_CACHE_MS) {
      if (acceptReply(hit.text, msg, { growthEnabled })) {
        return hit.text;
      }
      chatCache.delete(key);
    }
  }

  // Não injeta música no prompt se o user não falou de música.
  if (params.musicHint && !isMusicTopic(msg)) {
    params = { ...params, musicHint: undefined };
  }
  params = { ...params, growthEnabled };

  const gate = { userMessage: msg, growthEnabled };

  // Clima/temperatura: dados reais da região (IP → Open-Meteo)
  if (msg && isWeatherQuestion(msg)) {
    try {
      const snap = await getWeatherSnapshot();
      params = {
        ...params,
        weatherHint: weatherContextLine(snap),
      };
      const spoken = weatherSpokenLine(snap, params.companion.archetype ?? "curioso");
      const citesWeather = (text: string) => {
        const hasTemp = text.includes(String(snap.tempC));
        const place = (snap.city || "").toLowerCase();
        const hasPlace =
          !place ||
          place === "sua região" ||
          text.toLowerCase().includes(place) ||
          (!!snap.region && text.toLowerCase().includes(snap.region.toLowerCase()));
        return hasTemp && hasPlace;
      };
      const messages = buildMessages(params);
      const orHeaders = {
        "HTTP-Referer": process.env.APP_URL ?? "http://localhost:3333",
        "X-Title": "Companion Engine",
      };
      const nvidiaKey = process.env.NVIDIA_API_KEY;
      if (nvidiaKey) {
        try {
          const text = await callChatAPI(
            NVIDIA_API_URL,
            nvidiaKey,
            NVIDIA_TRY_MODELS[0],
            messages,
            undefined,
            gate
          );
          if (citesWeather(text)) {
            if (msg) chatCache.set(cacheKey(companionId, msg), { text, at: Date.now() });
            return text;
          }
        } catch (err) {
          console.warn(`[llm] NVIDIA clima falhou:`, err);
        }
      } else {
        const openrouterKey = process.env.OPENROUTER_API_KEY;
        if (openrouterKey) {
          try {
            const text = await callChatAPI(
              OPENROUTER_API_URL,
              openrouterKey,
              OPENROUTER_MODEL,
              messages,
              orHeaders,
              gate
            );
            if (citesWeather(text)) {
              if (msg) chatCache.set(cacheKey(companionId, msg), { text, at: Date.now() });
              return text;
            }
          } catch (err) {
            console.warn("[llm] OpenRouter falhou (clima):", err);
          }
        }
      }
      if (msg) chatCache.set(cacheKey(companionId, msg), { text: spoken, at: Date.now() });
      return spoken;
    } catch (err) {
      console.warn("[llm] clima falhou:", err);
    }
  }

  const messages = buildMessages(params);
  const orHeaders = {
    "HTTP-Referer": process.env.APP_URL ?? "http://localhost:3333",
    "X-Title": "Companion Engine",
  };

  const nvidiaKey = process.env.NVIDIA_API_KEY;
  if (nvidiaKey) {
    for (const model of NVIDIA_TRY_MODELS) {
      try {
        const text = await callChatAPI(NVIDIA_API_URL, nvidiaKey, model, messages, undefined, gate);
        if (msg) chatCache.set(cacheKey(companionId, msg), { text, at: Date.now() });
        return text;
      } catch (err) {
        console.warn(`[llm] NVIDIA ${model} falhou:`, err);
      }
    }
  }

  const openrouterKey = process.env.OPENROUTER_API_KEY;
  if (openrouterKey) {
    try {
      const text = await callChatAPI(
        OPENROUTER_API_URL,
        openrouterKey,
        OPENROUTER_MODEL,
        messages,
        orHeaders,
        gate
      );
      if (msg) chatCache.set(cacheKey(companionId, msg), { text, at: Date.now() });
      return text;
    } catch (err) {
      console.warn("[llm] OpenRouter falhou, usando fallback local:", err);
    }
  }

  return toLocal(params);
}
