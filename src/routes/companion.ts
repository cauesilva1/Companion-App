import { Router } from "express";
import { z } from "zod";
import { InteractionType } from "@prisma/client";
import { prisma } from "../db";
import { applyTimeDecay, applyInteraction } from "../moodEngine";
import { generateReaction } from "../llm";
import { computeAlert, moodText } from "../companionStatus";
import { AuthedRequest, requireAuth } from "../auth";
import { bumpMission, kindFromInteraction } from "../missions";

export const companionRouter = Router();

const createSchema = z.object({
  name: z.string().min(1).max(40),
  personality: z.string().max(120).optional(),
  skin: z.string().max(40).optional(),
  artStyle: z.string().max(40).optional(),
  backdrop: z.string().max(40).optional(),
  archetype: z.string().max(40).optional(),
});

function companionPayload(c: {
  id: string;
  name: string;
  personality: string;
  skin: string;
  artStyle: string;
  backdrop: string;
  archetype: string;
  mood: import("@prisma/client").Mood;
  energy: number;
  affection: number;
  lastInteractionAt: Date;
  pendingAlert: string | null;
  memoryNotes: string[];
}) {
  return {
    id: c.id,
    name: c.name,
    personality: c.personality,
    skin: c.skin,
    artStyle: c.artStyle,
    backdrop: c.backdrop,
    archetype: c.archetype,
    mood: c.mood,
    energy: c.energy,
    affection: c.affection,
    lastInteractionAt: c.lastInteractionAt,
    moodText: moodText(c.name, c.mood),
    alert: c.pendingAlert ?? computeAlert(c.name, c.mood),
    memoryNotes: c.memoryNotes,
  };
}

companionRouter.post("/", requireAuth, async (req: AuthedRequest, res) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const userId = req.auth!.userId;
  const existing = await prisma.companion.findFirst({ where: { userId } });
  if (existing) {
    return res.status(200).json(companionPayload(existing));
  }

  const created = await prisma.companion.create({
    data: {
      userId,
      name: parsed.data.name,
      personality: parsed.data.personality ?? parsed.data.archetype ?? "curioso",
      skin: parsed.data.skin ?? "dino-mort",
      artStyle: parsed.data.artStyle ?? "pixel",
      backdrop: parsed.data.backdrop ?? "sky",
      archetype: parsed.data.archetype ?? "curioso",
    },
  });

  return res.status(201).json(companionPayload(created));
});

companionRouter.get("/me", requireAuth, async (req: AuthedRequest, res) => {
  const companion = await prisma.companion.findFirst({
    where: { userId: req.auth!.userId },
    orderBy: { createdAt: "asc" },
  });
  if (!companion) return res.status(404).json({ error: "no_companion" });

  const now = new Date();
  const decayed = applyTimeDecay(companion, now);
  const updated = await prisma.companion.update({
    where: { id: companion.id },
    data: {
      energy: decayed.energy,
      affection: decayed.affection,
      mood: decayed.mood,
      lastDecayAt: now,
    },
  });
  return res.json(companionPayload(updated));
});

async function loadOwned(req: AuthedRequest, id: string) {
  return prisma.companion.findFirst({
    where: { id, userId: req.auth!.userId },
  });
}

companionRouter.get("/:id/state", requireAuth, async (req: AuthedRequest, res) => {
  const companion = await loadOwned(req, req.params.id);
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });

  const now = new Date();
  const decayed = applyTimeDecay(companion, now);
  const updated = await prisma.companion.update({
    where: { id: companion.id },
    data: {
      energy: decayed.energy,
      affection: decayed.affection,
      mood: decayed.mood,
      lastDecayAt: now,
    },
  });
  return res.json(companionPayload(updated));
});

const interactSchema = z.object({
  type: z.enum(["POKE", "FEED", "CHAT", "PLAY", "TEASE", "IGNORE_CHECK"]),
  message: z.string().max(500).optional(),
});

companionRouter.post("/:id/interact", requireAuth, async (req: AuthedRequest, res) => {
  const parsed = interactSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const companion = await loadOwned(req, req.params.id);
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });

  const now = new Date();
  const daysSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60 * 24);

  const type = parsed.data.type as InteractionType;
  const decayed = applyTimeDecay(companion, now);
  const result = applyInteraction(
    decayed.energy,
    decayed.affection,
    type,
    daysSinceInteraction
  );

  const reactionText = await generateReaction({
    companion: { ...companion, archetype: companion.archetype },
    type,
    mood: result.mood,
    energy: result.energy,
    affection: result.affection,
    userMessage: parsed.data.message ?? (type === "TEASE" ? "conta uma piada" : undefined),
  });

  const [updatedCompanion, interaction] = await prisma.$transaction([
    prisma.companion.update({
      where: { id: companion.id },
      data: {
        energy: result.energy,
        affection: result.affection,
        mood: result.mood,
        lastDecayAt: now,
        lastInteractionAt: now,
        pendingAlert: null,
      },
    }),
    prisma.interaction.create({
      data: {
        companionId: companion.id,
        type,
        userMessage: parsed.data.message,
        reactionText,
        moodAfter: result.mood,
        energyAfter: result.energy,
        affectionAfter: result.affection,
      },
    }),
  ]);

  const missionKind = kindFromInteraction(type);
  if (missionKind) {
    await bumpMission(req.auth!.userId, missionKind, 1);
  }

  return res.json({
    companion: companionPayload(updatedCompanion),
    reaction: interaction.reactionText,
    interaction: {
      id: interaction.id,
      type: interaction.type,
      reactionText: interaction.reactionText,
      createdAt: interaction.createdAt,
    },
  });
});

companionRouter.get("/:id/feed", requireAuth, async (req: AuthedRequest, res) => {
  const companion = await loadOwned(req, req.params.id);
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });
  const limit = Math.min(Number(req.query.limit) || 20, 50);
  const interactions = await prisma.interaction.findMany({
    where: { companionId: companion.id },
    orderBy: { createdAt: "desc" },
    take: limit,
  });
  return res.json(interactions);
});
