import * as fs from "fs";
import * as path from "path";
import { Mood } from "@prisma/client";

export interface StoredCompanion {
  id: string;
  name: string;
  personality: string;
  skin: string;
  /** baby | teen | adult */
  growthStage?: string;
  /** ISO — when current growthStage started */
  growthStageAt?: string;
  artStyle: string;
  backdrop: string;
  archetype: string;
  mood: Mood;
  energy: number;
  affection: number;
  lastDecayAt: string;
  lastInteractionAt: string;
  pendingAlert?: string;
  /** Memória curta: fatos lembrados (máx ~8). */
  memoryNotes?: string[];
  userDisplayName?: string;
  createdAt?: string;
}

export interface StoredInteraction {
  id: string;
  companionId: string;
  type: string;
  userMessage: string | null;
  reactionText: string;
  moodAfter: Mood;
  energyAfter: number;
  affectionAfter: number;
  createdAt: string;
}

interface StoreFile {
  companions: StoredCompanion[];
  interactions: StoredInteraction[];
}

function resolveDataDir(): string {
  if (process.env.COMPANION_DATA_DIR) {
    return path.resolve(process.env.COMPANION_DATA_DIR);
  }
  return path.join(__dirname, "../data");
}

function dataFile(): string {
  return path.join(resolveDataDir(), "companions.json");
}

function emptyStore(): StoreFile {
  return { companions: [], interactions: [] };
}

export function loadStore(): StoreFile {
  try {
    const file = dataFile();
    if (!fs.existsSync(file)) return emptyStore();
    return JSON.parse(fs.readFileSync(file, "utf8")) as StoreFile;
  } catch {
    return emptyStore();
  }
}

export function saveStore(store: StoreFile): void {
  const dir = resolveDataDir();
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(dataFile(), JSON.stringify(store, null, 2), "utf8");
}

export function toCompanion(row: StoredCompanion) {
  const createdAt = row.createdAt ? new Date(row.createdAt) : new Date(row.lastInteractionAt);
  const growthStageAt = row.growthStageAt
    ? new Date(row.growthStageAt)
    : createdAt;
  return {
    ...row,
    growthStage: row.growthStage ?? "baby",
    growthStageAt,
    lastDecayAt: new Date(row.lastDecayAt),
    lastInteractionAt: new Date(row.lastInteractionAt),
    createdAt,
  };
}
