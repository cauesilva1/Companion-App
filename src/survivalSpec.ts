/**
 * Spec canônica de sobrevivência (Cloud-First).
 * Portada para SQL em prisma/migrations/*_cloud_survival_iot/
 * e espelhada em apps/ios/Shared/MoodEngine.swift.
 *
 * LEGACY: Express/Electron não devem divergir desta tabela — modo manutenção.
 */

export const AFFECTION_DECAY_PER_HOUR = 2 / 24;
export const ENERGY_DECAY_PER_HOUR = 0.5;
/** Grace period sem decay após última interação (horas). */
export const DECAY_IDLE_GRACE_HOURS = 1;

export const INTERACTION_EFFECTS = {
  POKE: { affection: 2, energy: -1 },
  FEED: { affection: 0, energy: 8 },
  PLAY: { affection: 6, energy: -4 },
  CHAT: { affection: 4, energy: -2 },
  TEASE: { affection: 5, energy: -2 },
  IGNORE_CHECK: { affection: -4, energy: -2 },
} as const;

/**
 * PresenceStatus espelha LifeMode (sem ESP32/RSSI):
 * indoor→present, work→away, sleep→expedition.
 * Só `decayFrozen` (sleep) pausa o tick.
 */
export const PRESENCE_FROM_LIFE_MODE = {
  indoor: "present",
  work: "away",
  sleep: "expedition",
} as const;

/** Passos HealthKit → +1 energy a cada N passos (cap diário no Edge). */
export const STEPS_PER_ENERGY = 500;
export const STEPS_ENERGY_DAILY_CAP = 24;

/**
 * Life modes (comportamento + LLM). Orthogonal ao PresenceStatus IoT da mesa.
 * Portado em companion_ingest_context (migration life_modes_context).
 */
export const LIFE_MODES = ["work", "indoor", "sleep"] as const;
export type LifeMode = (typeof LIFE_MODES)[number];

/** Madrugada (hora local America/Sao_Paulo) → candidata a sleep. */
export const LIFE_SLEEP_HOUR_START = 0;
export const LIFE_SLEEP_HOUR_END = 6;
/** Passos recentes abaixo disso + charging/parado → sleep. */
export const LIFE_SLEEP_STEPS_RECENT_MAX = 80;
/** Horário comercial para modo trabalho/campo. */
export const LIFE_WORK_HOUR_START = 7;
export const LIFE_WORK_HOUR_END = 18;
/** Passos recentes altos fora de casa → work. */
export const LIFE_WORK_STEPS_RECENT_MIN = 120;
