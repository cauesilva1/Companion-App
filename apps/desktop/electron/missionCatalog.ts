/** Missões diárias — espelha apps/ios/Shared/MissionCatalog.swift e src/missions.ts */

export type MissionKind =
  | "POKE_COUNT"
  | "FEED_COUNT"
  | "PLAY_COUNT"
  | "CHAT_COUNT"
  | "TEASE_COUNT"
  | "OPEN_APP";

export type LocalMission = {
  id: string;
  kind: MissionKind;
  title: string;
  description: string;
  target: number;
  progress: number;
  rewardEnergy: number;
  rewardAffection: number;
  claimed: boolean;
};

type MissionDef = {
  kind: MissionKind;
  title: string;
  description: string;
  target: number;
  rewardEnergy: number;
  rewardAffection: number;
};

const ROTATION: MissionDef[][] = [
  [
    { kind: "POKE_COUNT", title: "Cutucadas", description: "Cutuca o dino 3 vezes", target: 3, rewardEnergy: 6, rewardAffection: 4 },
    { kind: "FEED_COUNT", title: "Lanche", description: "Alimente 2 vezes", target: 2, rewardEnergy: 10, rewardAffection: 3 },
    { kind: "PLAY_COUNT", title: "Brincadeira", description: "Brinque 1 vez", target: 1, rewardEnergy: 8, rewardAffection: 6 },
  ],
  [
    { kind: "CHAT_COUNT", title: "Conversa", description: "Mande 1 mensagem", target: 1, rewardEnergy: 5, rewardAffection: 8 },
    { kind: "TEASE_COUNT", title: "Piadinha", description: "Mande 1 piada", target: 1, rewardEnergy: 7, rewardAffection: 7 },
    { kind: "OPEN_APP", title: "Visita", description: "Abra o app 2 vezes hoje", target: 2, rewardEnergy: 4, rewardAffection: 5 },
  ],
  [
    { kind: "POKE_COUNT", title: "Carinho", description: "Cutuca 5 vezes", target: 5, rewardEnergy: 8, rewardAffection: 5 },
    { kind: "FEED_COUNT", title: "Banquete", description: "Alimente 3 vezes", target: 3, rewardEnergy: 12, rewardAffection: 4 },
    { kind: "TEASE_COUNT", title: "Zoeira", description: "2 piadas no dia", target: 2, rewardEnergy: 9, rewardAffection: 9 },
  ],
];

/** dayKey local YYYY-MM-DD (espelha iOS Calendar.current). */
export function dayKey(date = new Date(), timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const y = parts.find((p) => p.type === "year")!.value;
  const m = parts.find((p) => p.type === "month")!.value;
  const d = parts.find((p) => p.type === "day")!.value;
  return `${y}-${m}-${d}`;
}

export function displayDayLabel(date = new Date()): string {
  const key = dayKey(date);
  const parts = key.split("-");
  if (parts.length !== 3) return "Hoje";
  return `Hoje · ${parts[2]}/${parts[1]}`;
}

function defsForDay(key: string): MissionDef[] {
  const n = key.split("-").reduce((a, p) => a + Number(p), 0);
  return ROTATION[n % ROTATION.length];
}

export function buildMissionsForDay(key: string): LocalMission[] {
  return defsForDay(key).map((d) => ({
    id: `local-${key}-${d.kind}`,
    kind: d.kind,
    title: d.title,
    description: d.description,
    target: d.target,
    progress: 0,
    rewardEnergy: d.rewardEnergy,
    rewardAffection: d.rewardAffection,
    claimed: false,
  }));
}

export function ensureToday(
  day: string,
  existingDay: string,
  existing: LocalMission[]
): { day: string; missions: LocalMission[] } {
  if (existingDay === day && existing.length > 0) {
    return { day, missions: existing };
  }
  return { day, missions: buildMissionsForDay(day) };
}

export function bump(
  missions: LocalMission[],
  kind: MissionKind,
  amount = 1
): LocalMission[] {
  const idx = missions.findIndex((m) => m.kind === kind);
  if (idx < 0) return missions;
  if (missions[idx].claimed) return missions;
  const next = missions.map((m, i) =>
    i === idx
      ? { ...m, progress: Math.min(m.target, m.progress + amount) }
      : m
  );
  return next;
}

export function kindFromInteraction(type: string): MissionKind | null {
  switch (String(type).toUpperCase()) {
    case "POKE":
      return "POKE_COUNT";
    case "FEED":
      return "FEED_COUNT";
    case "PLAY":
      return "PLAY_COUNT";
    case "CHAT":
      return "CHAT_COUNT";
    case "TEASE":
      return "TEASE_COUNT";
    default:
      return null;
  }
}

export function claim(
  missions: LocalMission[],
  idOrKind: string
): { missions: LocalMission[]; rewardEnergy: number; rewardAffection: number } | null {
  let idx = missions.findIndex((m) => m.id === idOrKind);
  if (idx < 0) idx = missions.findIndex((m) => m.kind === idOrKind);
  if (idx < 0) idx = missions.findIndex((m) => idOrKind.includes(m.kind));
  if (idx < 0) return null;
  const m = missions[idx];
  if (m.claimed || m.progress < m.target) return null;
  const next = missions.map((row, i) => (i === idx ? { ...row, claimed: true } : row));
  return { missions: next, rewardEnergy: m.rewardEnergy, rewardAffection: m.rewardAffection };
}
