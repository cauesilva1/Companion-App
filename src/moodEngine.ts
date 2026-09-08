/**
 * @deprecated Cloud-First: a fonte de verdade é Postgres RPC + Edge Functions.
 * Mantido para mock Express / pack Mac (modo manutenção). Spec: survivalSpec.ts
 */
import { Mood, InteractionType, Companion } from "@prisma/client";
import {
  AFFECTION_DECAY_PER_HOUR,
  ENERGY_DECAY_PER_HOUR,
  DECAY_IDLE_GRACE_HOURS,
  INTERACTION_EFFECTS as SPEC_FX,
} from "./survivalSpec";

const CLAMP = (value: number, min = 0, max = 100) =>
  Math.max(min, Math.min(max, value));

export interface DecayResult {
  energy: number;
  affection: number;
  mood: Mood;
}

export function applyTimeDecay(companion: Companion, now: Date = new Date()): DecayResult {
  const hoursSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60);
  const hoursIdle = Math.max(0, hoursSinceInteraction - DECAY_IDLE_GRACE_HOURS);

  const affection = CLAMP(companion.affection - hoursIdle * AFFECTION_DECAY_PER_HOUR);
  const energy = CLAMP(companion.energy - hoursIdle * ENERGY_DECAY_PER_HOUR);
  const daysSinceInteraction = hoursSinceInteraction / 24;

  return {
    energy,
    affection,
    mood: computeMood(affection, energy, daysSinceInteraction),
  };
}

const INTERACTION_EFFECTS: Record<
  InteractionType,
  { affection: number; energy: number }
> = { ...SPEC_FX };

export interface InteractionResult {
  energy: number;
  affection: number;
  mood: Mood;
}

export function applyInteraction(
  baseEnergy: number,
  baseAffection: number,
  type: InteractionType,
  _daysSinceInteraction = 0
): InteractionResult {
  const fx = INTERACTION_EFFECTS[type];
  const affection = CLAMP(baseAffection + fx.affection);
  const energy = CLAMP(baseEnergy + fx.energy);
  return {
    energy,
    affection,
    mood: computeMood(affection, energy, 0),
  };
}

export function computeMood(
  affection: number,
  energy: number,
  daysSinceInteraction = 0
): Mood {
  if (daysSinceInteraction > 3) return Mood.LONELY;
  if (energy < 18) return Mood.SLEEPY;
  if (affection < 18) return Mood.SAD;
  if (affection < 32) return Mood.BORED;
  if (affection > 75 && energy > 40) return Mood.EXCITED;
  if (affection > 42) return Mood.HAPPY;
  return Mood.CONTENT;
}
