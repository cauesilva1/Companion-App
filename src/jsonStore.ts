import * as fs from "fs";
import * as path from "path";
import { Mood } from "@prisma/client";

export interface StoredCompanion {
  id: string;
  name: string;
  personality: string;
  skin: string;
  artStyle: string;
  backdrop: string;
  archetype: string;
  mood: Mood;
  energy: number;
  affection: number;
  lastDecayAt: string;
  lastInteractionAt: string;
  pendingAlert?: string;
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

const DATA_DIR = path.join(__dirname, "../data");
const DATA_FILE = path.join(DATA_DIR, "companions.json");

function emptyStore(): StoreFile {
  return { companions: [], interactions: [] };
}

export function loadStore(): StoreFile {
  try {
    if (!fs.existsSync(DATA_FILE)) return emptyStore();
    return JSON.parse(fs.readFileSync(DATA_FILE, "utf8")) as StoreFile;
  } catch {
    return emptyStore();
  }
}

export function saveStore(store: StoreFile): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(DATA_FILE, JSON.stringify(store, null, 2), "utf8");
}

export function toCompanion(row: StoredCompanion) {
  return {
    ...row,
    lastDecayAt: new Date(row.lastDecayAt),
    lastInteractionAt: new Date(row.lastInteractionAt),
  };
}
