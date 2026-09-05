import { Mood, InteractionType, Companion } from "@prisma/client";

const CLAMP = (value: number, min = 0, max = 100) =>
  Math.max(min, Math.min(max, value));

/** Afeto cai ~2/dia; energia cai ~1 a cada 2h sem interação. */
const AFFECTION_DECAY_PER_HOUR = 2 / 24;
const ENERGY_DECAY_PER_HOUR = 0.5;

export interface DecayResult {
  energy: number;
  affection: number;
  mood: Mood;
}

export function applyTimeDecay(companion: Companion, now: Date = new Date()): DecayResult {
  const hoursSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60);
  const hoursIdle = Math.max(0, hoursSinceInteraction - 1);

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
> = {
  POKE: { affection: 2, energy: -1 },
  FEED: { affection: 0, energy: 8 },
  PLAY: { affection: 6, energy: -4 },
  CHAT: { affection: 4, energy: -2 },
  TEASE: { affection: 5, energy: -2 },
  IGNORE_CHECK: { affection: -4, energy: -2 },
};

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
