/**
 * Spec canônica de sobrevivência (Cloud-First).
 * Portada para SQL em prisma/migrations/* e supabase/migrations/*.
 * Espelhada em apps/ios/Shared (LifeMode / LocalVoice).
 *
 * LEGACY: Express/Electron não devem divergir desta tabela — modo manutenção.
 */

export const AFFECTION_DECAY_PER_HOUR = 2 / 24;
/** Fallback genérico; o SQL usa taxas por lifeMode. */
export const ENERGY_DECAY_PER_HOUR = 0.5;
/** Grace period sem decay após última interação (horas) — work/default. */
export const DECAY_IDLE_GRACE_HOURS = 1;

/** indoor: recupera energia (~6/h), grace curto. */
export const INDOOR_ENERGY_RECOVER_PER_HOUR = 6;
export const INDOOR_DECAY_GRACE_HOURS = 0.15;
export const INDOOR_AFFECTION_DECAY_PER_HOUR = 1 / 24;

/** work: gasta energia com tempo + passos recentes. */
export const WORK_ENERGY_DECAY_PER_HOUR = 3.5;
export const WORK_DECAY_GRACE_HOURS = 0.5;
export const WORK_STEPS_FATIGUE_PER_500 = 1; // no tick: stepsRecent/500 até +4/h
export const WORK_STEPS_PER_ENERGY_DRAIN = 400;
export const WORK_STEPS_FATIGUE_DAILY_CAP = 30;

/** indoor passos: recarga leve. */
export const INDOOR_STEPS_PER_ENERGY = 750;
export const INDOOR_STEPS_ENERGY_DAILY_CAP = 12;

export const INTERACTION_EFFECTS = {
  POKE: { affection: 2, energy: -1 },
  FEED: { affection: 0, energy: 8 },
  PLAY: { affection: 6, energy: -4 },
  /** Chat: +afeto, −1 energia (cansa leve; resposta humanizada quando baixo). */
  CHAT: { affection: 4, energy: -1 },
  TEASE: { affection: 5, energy: -1 },
  IGNORE_CHECK: { affection: -4, energy: -2 },
} as const;

/**
 * PresenceStatus espelha LifeMode (sem ESP32/RSSI):
 * indoor→present, work→away, sleep→expedition (sonhos no feed).
 * Só `decayFrozen` (sleep) congela desgaste físico.
 */
export const PRESENCE_FROM_LIFE_MODE = {
  indoor: "present",
  work: "away",
  sleep: "expedition",
} as const;

/** @deprecated Prefer INDOOR_* / WORK_* — legado steps_ingest. */
export const STEPS_PER_ENERGY = 500;
export const STEPS_ENERGY_DAILY_CAP = 24;

/**
 * Life modes (comportamento + LLM + energy).
 * Portado em companion_apply_decay / companion_ingest_context / steps_ingest.
 */
export const LIFE_MODES = ["work", "indoor", "sleep"] as const;
export type LifeMode = (typeof LIFE_MODES)[number];

/** Madrugada / hora de dormir (America/Sao_Paulo). */
export const LIFE_BEDTIME_HOUR = 23;
/** Acorda de verdade só com app aberto a partir desta hora. */
export const LIFE_WAKE_HOUR = 6;
/** @deprecated Prefer LIFE_WAKE_HOUR — janela noturna começa em bedtime. */
export const LIFE_SLEEP_HOUR_START = 0;
export const LIFE_SLEEP_HOUR_END = 6;
/** Passos recentes abaixo disso + charging/parado → sleep (legado; sleep agora é por horário). */
export const LIFE_SLEEP_STEPS_RECENT_MAX = 80;
/** Horário comercial para modo trabalho/rua. */
export const LIFE_WORK_HOUR_START = 7;
export const LIFE_WORK_HOUR_END = 18;
/** Passos recentes altos fora de casa → work. */
export const LIFE_WORK_STEPS_RECENT_MIN = 120;

/** Cooldown mínimo entre pensamentos auto (mood/dream/rest/work) no SQL. */
export const THOUGHT_AUTO_COOLDOWN_MINUTES = 3;
