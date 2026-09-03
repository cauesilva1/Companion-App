import { InteractionType, Mood } from "@prisma/client";
import { localReaction, LocalVoiceParams } from "./localVoice";

const OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL ?? "openrouter/auto";
const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
/** Modelos NVIDIA em ordem de tentativa (build.nvidia.com). */
const NVIDIA_MODELS: string[] = (
  process.env.NVIDIA_MODELS ??
  [
    "openai/gpt-oss-20b",
    "moonshotai/kimi-k3",
    "nvidia/nemotron-3-super-120b-a12b",
    "deepseek-ai/deepseek-v4-pro-0813",
  ].join(",")
)
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const NVIDIA_MODEL = process.env.NVIDIA_MODEL ?? NVIDIA_MODELS[0] ?? "openai/gpt-oss-20b";
const MAX_TOKENS = 80;
const CHAT_CACHE_MS = 30_000;
const LLM_TIMEOUT_MS = 14_000;

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
  };
  type: InteractionType;
  mood: Mood;
  energy: number;
  affection: number;
  userMessage?: string | null;
  history?: ChatTurn[];
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
  /user\s*says|thinking|analyze|user input|current mood|personality:|energy:|here's a|here is a|as an ai|contexto:|vinculo|step\s*\d|fale agora|so a frase|só a frase|o usuario|o usuário|mensagem do|system:|assistant:/i;

const chatCache = new Map<string, { text: string; at: number }>();

function cacheKey(companionId: string | undefined, message: string) {
  return `${companionId ?? "x"}::${message.trim().toLowerCase()}`;
}

function buildMessages(params: ReactionParams): ChatMessage[] {
  const { companion, mood, userMessage, history = [] } = params;
  const arch = companion.archetype ?? "curioso";
  const tone = ARCH_TONE[arch] ?? ARCH_TONE.curioso;

  const system = [
    `Voce e ${companion.name}, companion virtual.`,
    `Personalidade: ${companion.personality}. Arquétipo: ${arch}.`,
    `Estilo visual (tom): ${companion.artStyle ?? "cartoon"}.`,
    `Humor agora: ${MOOD_LABELS[mood]}.`,
    tone,
    `Responda em portugues do Brasil, primeira pessoa, no maximo 12 palavras.`,
    `Apenas a fala. Sem aspas, sem ingles, sem explicar, sem repetir o pedido.`,
  ].join(" ");

  const messages: ChatMessage[] = [{ role: "system", content: system }];
  for (const turn of history.slice(-5)) {
    messages.push({ role: turn.role, content: turn.content });
  }
  messages.push({ role: "user", content: userMessage?.trim() || "Oi" });
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
    if (
      /\b(the|analyze|mood|energy|personality|input|user|says)\b/i.test(candidate) &&
      !/[áàãâéêíóôõúç]/i.test(candidate)
    ) {
      continue;
    }
    return words.slice(0, 14).join(" ");
  }
  return null;
}

export function isBadReaction(text: string): boolean {
  return !text || BAD_LINE.test(text) || !!text.match(/^User\s*says/i);
}

function extractText(data: OpenAICompatibleResponse): string {
  const msg = data.choices?.[0]?.message;
  const content = (msg?.content ?? "").trim();
  if (content) return content;
  const reasoning = (msg?.reasoning ?? msg?.reasoning_content ?? "").trim();
  if (reasoning) return reasoning;
  return (data.choices?.[0]?.text ?? "").trim();
}

async function callChatAPI(
  apiUrl: string,
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  extraHeaders?: Record<string, string>
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
        temperature: 0.85,
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

  const msg = params.userMessage?.trim() ?? "";
  if (msg) {
    const key = cacheKey(companionId, msg);
    const hit = chatCache.get(key);
    if (hit && Date.now() - hit.at < CHAT_CACHE_MS) {
      return hit.text;
    }
  }

  const messages = buildMessages(params);
  const orHeaders = {
    "HTTP-Referer": process.env.APP_URL ?? "http://localhost:3333",
    "X-Title": "Companion Engine",
  };

  const nvidiaKey = process.env.NVIDIA_API_KEY;
  if (nvidiaKey) {
    const models = Array.from(new Set([NVIDIA_MODEL, ...NVIDIA_MODELS]));
    for (const model of models) {
      try {
        const text = await callChatAPI(NVIDIA_API_URL, nvidiaKey, model, messages);
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
        orHeaders
      );
      if (msg) chatCache.set(cacheKey(companionId, msg), { text, at: Date.now() });
      return text;
    } catch (err) {
      console.warn("[llm] OpenRouter falhou, usando fallback local:", err);
    }
  }

  return toLocal(params);
}
