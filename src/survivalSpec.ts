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

/** RSSI mínimo (mais próximo de 0 = melhor) para considerar “na mesa”. */
export const IOT_RSSI_PRESENT_THRESHOLD = -75;
/** Sem ping de presença → expedition (minutos). */
export const IOT_PRESENCE_TIMEOUT_MIN = 15;

/** Passos HealthKit → +1 energy a cada N passos (cap diário no Edge). */
export const STEPS_PER_ENERGY = 500;
export const STEPS_ENERGY_DAILY_CAP = 24;
