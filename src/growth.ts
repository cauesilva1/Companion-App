/**
 * Growth stage helpers — shared semantics for API / desktop / iOS.
 * baby = Arks `base/` art; teen/adult = optional folders with base/ fallback.
 * Dwell time is measured from growthStageAt (time in current stage), not birth.
 *
 * GROWTH_ENABLED = false: no evolve, no teen/adult art (cores Gemini ainda escuras).
 * Código e assets ficam prontos; ligar de novo quando a arte estiver ok.
 */

export type GrowthStage = "baby" | "teen" | "adult";

/**
 * Visual growth + evolve strips paused until Mort teen/adult colors look right.
 * Voice/dwell helpers stay; progression and stage folders stay off.
 */
export const GROWTH_ENABLED = false;

export const GROWTH_STAGES: GrowthStage[] = ["baby", "teen", "adult"];

/** Days required in the current stage before the next evolve is allowed. */
export const STAGE_DWELL_DAYS: Record<GrowthStage, number> = {
  baby: 7,
  teen: 14,
  adult: Infinity,
};

/** Affection gate for leaving each stage. */
export const STAGE_AFFECTION_MIN: Record<GrowthStage, number> = {
  baby: 55,
  teen: 70,
  adult: 100,
};

export function normalizeGrowthStage(raw: unknown): GrowthStage {
  const s = String(raw ?? "baby").toLowerCase();
  if (s === "teen" || s === "adult" || s === "baby") return s;
  return "baby";
}

/** Stage used for sprites / scale / evolve. Forced to baby while growth is off. */
export function effectiveGrowthStage(raw: unknown): GrowthStage {
  if (!GROWTH_ENABLED) return "baby";
  return normalizeGrowthStage(raw);
}

/** Visual scale relative to current canvas (baby slightly smaller). */
export function growthScale(stage: GrowthStage): number {
  if (!GROWTH_ENABLED) return 1;
  switch (stage) {
    case "baby":
      return 0.88;
    case "teen":
      return 1.0;
    case "adult":
      return 1.14;
  }
}

export function nextGrowthStage(stage: GrowthStage): GrowthStage | null {
  if (stage === "baby") return "teen";
  if (stage === "teen") return "adult";
  return null;
}

export function evolveClip(from: GrowthStage, to: GrowthStage): string | null {
  if (!GROWTH_ENABLED) return null;
  if (from === "baby" && to === "teen") return "evolveBabyTeen";
  if (from === "teen" && to === "adult") return "evolveTeenAdult";
  return null;
}

function toDate(value: Date | string): Date {
  return value instanceof Date ? value : new Date(value);
}

/**
 * Slow progression: days spent in the current stage + affection gate.
 * Uses stageStartedAt (growthStageAt), falling back to createdAt for legacy rows.
 */
export function shouldEvolve(params: {
  stage: GrowthStage;
  stageStartedAt: Date | string;
  affection: number;
  now?: Date;
}): GrowthStage | null {
  if (!GROWTH_ENABLED) return null;

  const now = params.now ?? new Date();
  const started = toDate(params.stageStartedAt);
  const days = (now.getTime() - started.getTime()) / (24 * 60 * 60 * 1000);
  const next = nextGrowthStage(params.stage);
  if (!next) return null;

  const needDays = STAGE_DWELL_DAYS[params.stage];
  const needAffection = STAGE_AFFECTION_MIN[params.stage];
  if (days >= needDays && params.affection >= needAffection) return next;
  return null;
}

/** Max words for LLM / local lines by stage. */
export function stageWordLimit(stage: GrowthStage): number {
  const s = GROWTH_ENABLED ? stage : "baby";
  switch (s) {
    case "baby":
      return 10;
    case "teen":
      return 16;
    case "adult":
      return 22;
  }
}

/** Extra system-prompt voice for the current size/stage. */
export function stageVoiceHint(stage: GrowthStage): string {
  const s = GROWTH_ENABLED ? stage : "baby";
  switch (s) {
    case "baby":
      return `Fase: bebe. Fale simples, grudento e inocente; gíria mínima. No maximo ${stageWordLimit(s)} palavras.`;
    case "teen":
      return `Fase: adolescente. Mais atitude e energia; espelhe o arquétipo. No maximo ${stageWordLimit(s)} palavras.`;
    case "adult":
      return `Fase: adulto. Mais maduro e calmo, ainda fiel ao arquétipo. No maximo ${stageWordLimit(s)} palavras.`;
  }
}

/** Folder under assets/dinos/<skin>/ for a stage. While growth is off → always base. */
export function stageAssetFolder(stage: GrowthStage): string {
  if (!GROWTH_ENABLED) return "base";
  return stage;
}
