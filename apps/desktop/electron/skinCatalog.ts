import * as fs from "fs";
import * as path from "path";

export type SkinRender = "css" | "sprite";

export interface SkinEntry {
  id: string;
  name: string;
  source: string;
  license: string;
  render: SkinRender;
  sprite?: { idle: string };
  unlock: "starter" | "collectible";
  url?: string;
  pixel?: boolean;
  folder?: string;
}

export interface SkinView extends SkinEntry {
  available: boolean;
  spriteUrl?: string;
}

const CATALOG_PATH = path.join(__dirname, "../../renderer/skins/catalog.json");
const RENDERER_ROOT = path.join(__dirname, "../../renderer");

let catalogCache: SkinEntry[] | null = null;

export function loadCatalog(): SkinEntry[] {
  if (catalogCache) return catalogCache;
  try {
    catalogCache = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8")) as SkinEntry[];
  } catch {
    catalogCache = [
      { id: "dino-doux", name: "Doux", source: "arks-dino-characters", license: "itch", render: "sprite", sprite: { idle: "assets/dinos/doux/base/idle.png" }, unlock: "starter", pixel: true, folder: "doux" },
    ];
  }
  return catalogCache;
}

export function resolveSkinFile(entry: SkinEntry): string | null {
  if (entry.render !== "sprite" || !entry.sprite?.idle) return null;
  const abs = path.join(RENDERER_ROOT, entry.sprite.idle);
  return fs.existsSync(abs) ? abs : null;
}

export function listSkins(): SkinView[] {
  return loadCatalog().map((entry) => {
    if (entry.render === "css") {
      return { ...entry, available: true };
    }
    const abs = resolveSkinFile(entry);
    return {
      ...entry,
      available: !!abs,
      spriteUrl: entry.sprite?.idle ?? undefined,
    };
  });
}

const LEGACY_SKIN_IDS: Record<string, string> = {
  blob: "dino-doux",
  cat: "dino-vita",
  slime: "dino-olaf",
  ghost: "dino-kuro",
  mushi: "dino-doux",
  pip: "dino-olaf",
  zot: "dino-mort",
  dino: "dino-doux",
  "dino-fam": "dino-vita",
  candy: "dino-vita",
  moss: "dino-kuro",
  "kenney-curioso": "dino-doux",
  "kenney-preguicoso": "dino-olaf",
  "kenney-carinhoso": "dino-vita",
  "kenney-zoeiro": "dino-mort",
  "kenney-misterioso": "dino-kuro",
};

export function normalizeSkinId(id: string): string {
  return LEGACY_SKIN_IDS[id] ?? id;
}

export function findSkin(id: string): SkinView | undefined {
  const normalized = normalizeSkinId(id);
  return listSkins().find((s) => s.id === normalized);
}

export function isValidSkinId(id: string): boolean {
  const normalized = normalizeSkinId(id);
  return loadCatalog().some((s) => s.id === normalized);
}

/** Invalidate cache after catalog edits in dev */
export function reloadCatalog(): SkinEntry[] {
  catalogCache = null;
  return loadCatalog();
}
