import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db";
import { applyTimeDecay, applyInteraction } from "../moodEngine";
import { generateReaction } from "../llm";
import { computeAlert, moodText } from "../companionStatus";
import { InteractionType } from "@prisma/client";

export const companionRouter = Router();

const createSchema = z.object({
  name: z.string().min(1).max(40),
  personality: z.string().max(120).optional(),
  skin: z.string().max(40).optional(),
  artStyle: z.string().max(40).optional(),
  backdrop: z.string().max(40).optional(),
  archetype: z.string().max(40).optional(),
});

companionRouter.post("/", async (req, res) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.upsert({
    where: { email: "local@companion.dev" },
    update: {},
    create: { email: "local@companion.dev" },
  });

  const created = await prisma.companion.create({
    data: {
      userId: user.id,
      name: parsed.data.name,
      personality: parsed.data.personality ?? "curioso",
      skin: parsed.data.skin ?? "blob",
    },
  });

  return res.status(201).json({
    id: created.id,
    name: created.name,
    personality: created.personality,
    skin: created.skin,
    mood: created.mood,
    energy: created.energy,
    affection: created.affection,
    moodText: moodText(created.name, created.mood),
  });
});

/**
 * GET /companion/:id/state
 * Retorna o estado atual do companion, ja aplicando o decay de tempo.
 * Isso e o endpoint que o widget (iOS/PC) chama pra saber o que desenhar.
 */
companionRouter.get("/:id/state", async (req, res) => {
  const companion = await prisma.companion.findUnique({ where: { id: req.params.id } });
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });

  const now = new Date();
  const decayed = applyTimeDecay(companion, now);

  const updated = await prisma.companion.update({
    where: { id: companion.id },
    data: { energy: decayed.energy, affection: decayed.affection, mood: decayed.mood, lastDecayAt: now },
  });

  return res.json({
    id: updated.id,
    name: updated.name,
    personality: updated.personality,
    skin: updated.skin,
    mood: updated.mood,
    energy: updated.energy,
    affection: updated.affection,
    lastInteractionAt: updated.lastInteractionAt,
    moodText: moodText(updated.name, updated.mood),
    alert: computeAlert(updated.name, updated.mood),
  });
});

companionRouter.get("/:id/status", async (req, res) => {
  const companion = await prisma.companion.findUnique({ where: { id: req.params.id } });
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });

  const now = new Date();
  const decayed = applyTimeDecay(companion, now);
  const updated = await prisma.companion.update({
    where: { id: companion.id },
    data: { energy: decayed.energy, affection: decayed.affection, mood: decayed.mood, lastDecayAt: now },
  });

  return res.json({
    id: updated.id,
    name: updated.name,
    mood: updated.mood,
    energy: updated.energy,
    affection: updated.affection,
    moodText: moodText(updated.name, updated.mood),
    alert: computeAlert(updated.name, updated.mood),
  });
});

const interactSchema = z.object({
  type: z.nativeEnum(InteractionType),
  message: z.string().max(500).optional(),
});

/**
 * POST /companion/:id/interact
 * Body: { type: "POKE" | "FEED" | "PLAY" | "CHAT", message?: string }
 * Aplica a interacao, gera a fala da IA e retorna o novo estado + reacao.
 */
companionRouter.post("/:id/interact", async (req, res) => {
  const parsed = interactSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const companion = await prisma.companion.findUnique({ where: { id: req.params.id } });
  if (!companion) return res.status(404).json({ error: "Companion nao encontrado" });

  const now = new Date();
  const daysSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60 * 24);

  // 1. aplica decay de tempo primeiro, depois a interacao em cima do resultado
  const decayed = applyTimeDecay(companion, now);
  const result = applyInteraction(decayed.energy, decayed.affection, parsed.data.type, daysSinceInteraction);

  // 2. gera a fala via IA (com fallback local se a API falhar)
  const reactionText = await generateReaction({
    companion,
    type: parsed.data.type,
    mood: result.mood,
    energy: result.energy,
    affection: result.affection,
    userMessage: parsed.data.message,
  });

  // 3. persiste tudo
  const [updatedCompanion, interaction] = await prisma.$transaction([
    prisma.companion.update({
      where: { id: companion.id },
      data: {
        energy: result.energy,
        affection: result.affection,
        mood: result.mood,
        lastDecayAt: now,
        lastInteractionAt: now,
      },
    }),
    prisma.interaction.create({
      data: {
        companionId: companion.id,
        type: parsed.data.type,
        userMessage: parsed.data.message,
        reactionText,
        moodAfter: result.mood,
        energyAfter: result.energy,
        affectionAfter: result.affection,
      },
    }),
  ]);

  return res.json({
    companion: {
      id: updatedCompanion.id,
      name: updatedCompanion.name,
      mood: updatedCompanion.mood,
      energy: updatedCompanion.energy,
      affection: updatedCompanion.affection,
      moodText: moodText(updatedCompanion.name, updatedCompanion.mood),
    },
    reaction: interaction.reactionText,
    interaction: {
      id: interaction.id,
      type: interaction.type,
      reactionText: interaction.reactionText,
      createdAt: interaction.createdAt,
    },
  });
});

/**
 * GET /companion/:id/feed?limit=20
 * Historico de interacoes - equivalente ao "feed social" que aparecia no video.
 */
companionRouter.get("/:id/feed", async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 20, 50);
  const interactions = await prisma.interaction.findMany({
    where: { companionId: req.params.id },
    orderBy: { createdAt: "desc" },
    take: limit,
  });
  return res.json(interactions);
});
