/**
 * Espelho de Growth (Swift).
 * Manter alinhado com apps/ios/Shared/Growth.swift
 */

export function normalize(raw) {
  switch (String(raw ?? "baby").toLowerCase()) {
    case "teen":
      return "teen";
    case "adult":
      return "adult";
    default:
      return "baby";
  }
}

export function effective(raw, isEnabled) {
  return isEnabled ? normalize(raw) : "baby";
}

export function scale(stage, isEnabled) {
  if (!isEnabled) return 1;
  switch (stage) {
    case "baby":
      return 0.88;
    case "teen":
      return 1.0;
    case "adult":
      return 1.14;
    default:
      return 1;
  }
}

export function wordLimit(stage, isEnabled) {
  const s = isEnabled ? stage : "baby";
  switch (s) {
    case "teen":
      return 16;
    case "adult":
      return 22;
    default:
      return 10;
  }
}

export function shouldEvolve({ stage, stageStartedAt, affection, now = new Date(), isEnabled }) {
  if (!isEnabled) return null;
  const next = stage === "baby" ? "teen" : stage === "teen" ? "adult" : null;
  if (!next) return null;
  const dwell = stage === "baby" ? 7 : stage === "teen" ? 14 : Infinity;
  const needAff = stage === "baby" ? 55 : stage === "teen" ? 70 : 100;
  const days = (now.getTime() - stageStartedAt.getTime()) / (24 * 60 * 60 * 1000);
  if (days >= dwell && affection >= needAff) return next;
  return null;
}

export function evolveClip(from, to, isEnabled) {
  if (!isEnabled) return null;
  if (from === "baby" && to === "teen") return "evolveBabyTeen";
  if (from === "teen" && to === "adult") return "evolveTeenAdult";
  return null;
}
