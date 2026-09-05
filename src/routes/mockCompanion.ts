import { Router } from "express";
import { z } from "zod";
import { Mood } from "@prisma/client";
import { applyTimeDecay, applyInteraction } from "../moodEngine";
import { generateReaction, isBadReaction } from "../llm";
import { computeAlert, moodText } from "../companionStatus";
import { localGreeting, localReaction, suggestPrank } from "../localVoice";
import {
  loadStore,
  saveStore,
  toCompanion,
  StoredCompanion,
  StoredInteraction,
} from "../jsonStore";

export const mockRouter = Router();

type RuntimeCompanion = ReturnType<typeof toCompanion> & {
  pendingAlert?: string;
  memoryNotes?: string[];
  userDisplayName?: string;
};

let file = loadStore();

function persist() {
  saveStore(file);
}

function findRow(id: string): StoredCompanion | undefined {
  const key = id === "mock" ? file.companions[0]?.id : id;
  return file.companions.find((c) => c.id === key);
}

function runtime(row: StoredCompanion): RuntimeCompanion {
  return toCompanion(row);
}

function writeBack(companion: RuntimeCompanion) {
  const idx = file.companions.findIndex((c) => c.id === companion.id);
  const row: StoredCompanion = {
    id: companion.id,
    name: companion.name,
    personality: companion.personality,
    skin: companion.skin,
    artStyle: companion.artStyle,
    backdrop: companion.backdrop,
    archetype: companion.archetype,
    mood: companion.mood,
    energy: companion.energy,
    affection: companion.affection,
    lastDecayAt: companion.lastDecayAt.toISOString(),
    lastInteractionAt: companion.lastInteractionAt.toISOString(),
    pendingAlert: companion.pendingAlert,
    memoryNotes: companion.memoryNotes,
    userDisplayName: companion.userDisplayName,
  };
  if (idx >= 0) file.companions[idx] = row;
  else file.companions.push(row);
  persist();
}

function extractMemoryFromMessage(message: string): string[] {
  const notes: string[] = [];
  const nameMatch = message.match(
    /(?:meu nome é|me chamo|pode me chamar de|eu sou o|eu sou a)\s+([A-Za-zÀ-ÿ][\wÀ-ÿ'-]{1,24})/i
  );
  if (nameMatch) notes.push(`Usuário se chama ${nameMatch[1]}`);
  const likeMatch = message.match(/eu (?:gosto|amo|adoro) (?:de |da |do )?(.{3,40})/i);
  if (likeMatch) notes.push(`Gosta de ${likeMatch[1].trim().replace(/[。.!?].*$/, "")}`);
  return notes;
}

function mergeMemory(
  companion: RuntimeCompanion,
  extras: string[],
  trackTitle?: string
) {
  const list = [...(companion.memoryNotes ?? [])];
  for (const n of extras) {
    if (!list.some((x) => x.toLowerCase() === n.toLowerCase())) list.unshift(n);
  }
  if (trackTitle) {
    const note = `Última música: ${trackTitle.slice(0, 60)}`;
    const withoutOld = list.filter((x) => !x.startsWith("Última música:"));
    withoutOld.unshift(note);
    companion.memoryNotes = withoutOld.slice(0, 8);
  } else {
    companion.memoryNotes = list.slice(0, 8);
  }
  const nameNote = extras.find((n) => n.startsWith("Usuário se chama "));
  if (nameNote) companion.userDisplayName = nameNote.replace("Usuário se chama ", "");
}

function applyDecay(companion: RuntimeCompanion): void {
  const now = new Date();
  const decayed = applyTimeDecay(companion as any, now);
  companion.energy = decayed.energy;
  companion.affection = decayed.affection;
  companion.mood = decayed.mood;
  companion.lastDecayAt = now;
  const alert = computeAlert(companion.name, companion.mood);
  if (alert) companion.pendingAlert = alert;
}

function chatHistory(companionId: string) {
  return file.interactions
    .filter((i) => i.companionId === companionId && i.type === "CHAT" && !isBadReaction(i.reactionText))
    .slice(0, 5)
    .reverse()
    .flatMap((i) => {
      const turns: { role: "user" | "assistant"; content: string }[] = [];
      if (i.userMessage) turns.push({ role: "user", content: i.userMessage });
      turns.push({ role: "assistant", content: i.reactionText });
      return turns;
    });
}

function statePayload(companion: RuntimeCompanion) {
  const alert = companion.pendingAlert;
  companion.pendingAlert = undefined;
  const hour = new Date().getHours();
  const greeting = localGreeting(companion.archetype, hour);
  writeBack(companion);
  return {
    id: companion.id,
    name: companion.name,
    personality: companion.personality,
    skin: companion.skin,
    artStyle: companion.artStyle,
    backdrop: companion.backdrop,
    archetype: companion.archetype,
    mood: companion.mood,
    affection: companion.affection,
    energy: companion.energy,
    lastInteractionAt: companion.lastInteractionAt,
    moodText: moodText(companion.name, companion.mood),
    greeting,
    alert,
    memoryNotes: companion.memoryNotes ?? [],
  };
}

export function tickMockCompanions() {
  for (const row of file.companions) {
    const companion = runtime(row);
    applyDecay(companion);
    writeBack(companion);
  }
}

function nextId(prefix = "cmp") {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const createSchema = z.object({
  name: z.string().min(1).max(40),
  personality: z.string().max(120).optional(),
  skin: z.string().max(40).optional(),
  artStyle: z.string().max(40).optional(),
  backdrop: z.string().max(40).optional(),
  archetype: z.string().max(40).optional(),
});

mockRouter.post("/", (req, res) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const now = new Date().toISOString();
  const companion: StoredCompanion = {
    id: nextId("cmp"),
    name: parsed.data.name,
    personality: parsed.data.personality ?? "curioso",
    skin: parsed.data.skin ?? "blob",
    artStyle: parsed.data.artStyle ?? "cartoon",
    backdrop: parsed.data.backdrop ?? "bedroom",
    archetype: parsed.data.archetype ?? "curioso",
    mood: Mood.HAPPY,
    energy: 80,
    affection: 50,
    lastDecayAt: now,
    lastInteractionAt: now,
  };
  file.companions.push(companion);
  persist();
  return res.status(201).json(statePayload(runtime(companion)));
});

mockRouter.get("/export", (_req, res) => {
  return res.json(file);
});

mockRouter.post("/import", (req, res) => {
  const body = req.body as { companions?: StoredCompanion[]; interactions?: StoredInteraction[] };
  if (!body?.companions || !Array.isArray(body.companions)) {
    return res.status(400).json({ error: "JSON inválido" });
  }
  file = {
    companions: body.companions,
    interactions: Array.isArray(body.interactions) ? body.interactions : [],
  };
  persist();
  return res.json({ ok: true, count: file.companions.length });
});

mockRouter.get("/:id/state", (req, res) => {
  const row = findRow(req.params.id);
  if (!row) return res.status(404).json({ error: "Companion não encontrado" });
  const companion = runtime(row);
  applyDecay(companion);
  return res.json(statePayload(companion));
});

mockRouter.get("/:id/status", (req, res) => {
  const row = findRow(req.params.id);
  if (!row) return res.status(404).json({ error: "Companion não encontrado" });
  const companion = runtime(row);
  applyDecay(companion);
  return res.json(statePayload(companion));
});

const interactSchema = z.object({
  type: z.enum(["POKE", "FEED", "PLAY", "CHAT", "TEASE", "IGNORE_CHECK"]),
  message: z.string().max(500).optional(),
  pranksEnabled: z.boolean().optional(),
  rememberChats: z.boolean().optional(),
  trackTitle: z.string().max(120).optional(),
  screenHint: z.string().max(160).optional(),
});

mockRouter.post("/:id/interact", async (req, res) => {
  const row = findRow(req.params.id);
  if (!row) return res.status(404).json({ error: "Companion não encontrado" });

  const parsed = interactSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const companion = runtime(row);
  const now = new Date();
  const daysSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60 * 24);

  applyDecay(companion);
  const result = applyInteraction(
    companion.energy,
    companion.affection,
    parsed.data.type as any,
    daysSinceInteraction
  );

  const remember = parsed.data.rememberChats !== false;
  if (remember && parsed.data.message) {
    mergeMemory(companion, extractMemoryFromMessage(parsed.data.message), parsed.data.trackTitle);
  } else if (parsed.data.trackTitle) {
    mergeMemory(companion, [], parsed.data.trackTitle);
  }

  const history = parsed.data.type === "CHAT" ? chatHistory(companion.id) : [];

  let reactionText = await generateReaction(
    {
      companion: {
        name: companion.name,
        personality: companion.personality,
        archetype: companion.archetype,
        artStyle: companion.artStyle,
      },
      type: parsed.data.type as any,
      mood: result.mood,
      energy: result.energy,
      affection: result.affection,
      userMessage: parsed.data.message,
      history,
      memoryNotes: remember ? companion.memoryNotes : undefined,
      screenHint: parsed.data.screenHint,
    },
    companion.id
  );

  if (isBadReaction(reactionText)) {
    reactionText = localReaction({
      name: companion.name,
      archetype: companion.archetype,
      mood: result.mood,
      type: parsed.data.type as any,
      userMessage: parsed.data.message,
    });
  }

  const prank = suggestPrank(
    companion.archetype,
    parsed.data.message,
    !!parsed.data.pranksEnabled
  );

  companion.energy = result.energy;
  companion.affection = result.affection;
  companion.mood = result.mood;
  companion.lastDecayAt = now;
  companion.lastInteractionAt = now;
  companion.pendingAlert = undefined;

  const interaction: StoredInteraction = {
    id: nextId("act"),
    companionId: companion.id,
    type: parsed.data.type,
    userMessage: parsed.data.message ?? null,
    reactionText,
    moodAfter: result.mood,
    energyAfter: result.energy,
    affectionAfter: result.affection,
    createdAt: now.toISOString(),
  };
  file.interactions.unshift(interaction);
  writeBack(companion);

  return res.json({
    companion: {
      id: companion.id,
      name: companion.name,
      mood: companion.mood,
      affection: companion.affection,
      energy: companion.energy,
      artStyle: companion.artStyle,
      backdrop: companion.backdrop,
      skin: companion.skin,
      archetype: companion.archetype,
      moodText: moodText(companion.name, companion.mood),
      memoryNotes: companion.memoryNotes ?? [],
    },
    reaction: reactionText,
    prank,
    interaction,
  });
});

mockRouter.get("/:id/feed", (req, res) => {
  const row = findRow(req.params.id);
  if (!row) return res.status(404).json({ error: "Companion não encontrado" });
  const limit = Math.min(Number(req.query.limit) || 20, 50);
  const list = file.interactions
    .filter((i) => i.companionId === row.id && !isBadReaction(i.reactionText))
    .slice(0, limit)
    .map((i) => ({
      ...i,
      companionName: row.name,
    }));
  return res.json(list);
});
