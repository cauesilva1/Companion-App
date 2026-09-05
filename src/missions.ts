import { MissionKind, Prisma } from "@prisma/client";
import { prisma } from "./db";

export function dayKey(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

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

function defsForDay(key: string): MissionDef[] {
  const n = key.split("-").reduce((a, p) => a + Number(p), 0);
  return ROTATION[n % ROTATION.length];
}

export async function ensureTodayMissions(userId: string) {
  const key = dayKey();
  const existing = await prisma.userMissionProgress.findMany({
    where: { userId, dayKey: key },
  });
  if (existing.length > 0) return existing;

  const defs = defsForDay(key);
  await prisma.userMissionProgress.createMany({
    data: defs.map((d) => ({
      userId,
      dayKey: key,
      kind: d.kind,
      title: d.title,
      description: d.description,
      target: d.target,
      rewardEnergy: d.rewardEnergy,
      rewardAffection: d.rewardAffection,
    })),
  });
  return prisma.userMissionProgress.findMany({ where: { userId, dayKey: key } });
}

export async function bumpMission(
  userId: string,
  kind: MissionKind,
  amount = 1
) {
  await ensureTodayMissions(userId);
  const key = dayKey();
  const row = await prisma.userMissionProgress.findUnique({
    where: { userId_dayKey_kind: { userId, dayKey: key, kind } },
  });
  if (!row || row.claimed) return row;
  return prisma.userMissionProgress.update({
    where: { id: row.id },
    data: { progress: Math.min(row.target, row.progress + amount) },
  });
}

export function kindFromInteraction(type: string): MissionKind | null {
  switch (type) {
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

export type MissionRow = Prisma.UserMissionProgressGetPayload<object>;
