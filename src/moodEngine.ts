import { Mood, InteractionType, Companion } from "@prisma/client";

const CLAMP = (value: number, min = 0, max = 100) =>
  Math.max(min, Math.min(max, value));

const AFFECTION_DECAY_PER_DAY = 2;

export interface DecayResult {
  energy: number;
  affection: number;
  mood: Mood;
}

export function applyTimeDecay(companion: Companion, now: Date = new Date()): DecayResult {
  const daysSinceInteraction =
    (now.getTime() - companion.lastInteractionAt.getTime()) / (1000 * 60 * 60 * 24);

  const affection = CLAMP(
    companion.affection - Math.max(0, daysSinceInteraction - 1) * AFFECTION_DECAY_PER_DAY
  );

  return {
    energy: companion.energy,
    affection,
    mood: computeMood(affection, daysSinceInteraction),
  };
}

const INTERACTION_EFFECTS: Record<InteractionType, number> = {
  POKE: 2,
  FEED: 0,
  PLAY: 6,
  CHAT: 4,
  IGNORE_CHECK: -4,
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
  daysSinceInteraction = 0
): InteractionResult {
  const affection = CLAMP(baseAffection + INTERACTION_EFFECTS[type]);
  return {
    energy: baseEnergy,
    affection,
    mood: computeMood(affection, 0),
  };
}

export function computeMood(affection: number, daysSinceInteraction: number): Mood {
  if (daysSinceInteraction > 3) return Mood.LONELY;
  if (affection < 18) return Mood.SAD;
  if (affection < 32) return Mood.BORED;
  if (affection > 75) return Mood.EXCITED;
  if (affection > 42) return Mood.HAPPY;
  return Mood.CONTENT;
}
