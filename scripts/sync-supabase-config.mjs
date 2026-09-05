#!/usr/bin/env node
/**
 * Lê SUPABASE_URL + SUPABASE_ANON_KEY do .env da raiz e propaga para:
 * - apps/desktop/.env
 * - apps/ios/Companion/Info.plist (chaves embutidas no app — usuários não digitam)
 * - apps/ios/Companion/Generated/SupabaseDefaults.plist (cópia legível)
 *
 * Uso: node scripts/sync-supabase-config.mjs
 */
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function parseEnv(file) {
  const vals = {};
  if (!fs.existsSync(file)) return vals;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#") || !t.includes("=")) continue;
    const i = t.indexOf("=");
    const k = t.slice(0, i).trim();
    let v = t.slice(i + 1).trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    vals[k] = v;
  }
  return vals;
}

function upsertEnv(file, patch) {
  let lines = fs.existsSync(file) ? fs.readFileSync(file, "utf8").split("\n") : [];
  const keys = new Set(Object.keys(patch));
  const seen = new Set();
  lines = lines.map((line) => {
    const t = line.trim();
    if (!t || t.startsWith("#") || !t.includes("=")) return line;
    const k = t.split("=", 1)[0].trim();
    if (!keys.has(k)) return line;
    seen.add(k);
    return `${k}=${patch[k]}`;
  });
  for (const k of keys) {
    if (!seen.has(k) && patch[k]) lines.push(`${k}=${patch[k]}`);
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.filter((l, i, a) => !(l === "" && a[i - 1] === "")).join("\n").replace(/\n*$/, "\n"));
}

function setPlistKey(plist, key, value) {
  const keyTag = `\t<key>${key}</key>`;
  const valTag = `\t<string>${escapeXml(value)}</string>`;
  if (plist.includes(`<key>${key}</key>`)) {
    return plist.replace(
      new RegExp(`<key>${key}<\\/key>\\s*<string>[^<]*<\\/string>`),
      `<key>${key}</key>\n\t<string>${escapeXml(value)}</string>`
    );
  }
  return plist.replace("</dict>\n</plist>", `${keyTag}\n${valTag}\n</dict>\n</plist>`);
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const rootEnv = parseEnv(path.join(root, ".env"));
let url = (rootEnv.SUPABASE_URL || "").trim();
let anon = (rootEnv.SUPABASE_ANON_KEY || "").trim();

// Derive URL from pooler project ref if missing
if (!url && rootEnv.DATABASE_URL) {
  const m = rootEnv.DATABASE_URL.match(/postgres\.([a-z0-9]+):/i);
  if (m) url = `https://${m[1]}.supabase.co`;
}

if (!url) {
  console.error("Falta SUPABASE_URL no .env (ou DATABASE_URL com project ref).");
  process.exit(1);
}
if (!anon || anon === "eyJ..." || anon.length < 40) {
  console.error(
    "Falta SUPABASE_ANON_KEY no .env.\n" +
      "Pegue em: Supabase Dashboard → Settings → API → anon public.\n" +
      "Depois rode de novo: node scripts/sync-supabase-config.mjs"
  );
  // Still write URL so desktop/iOS get the project
}

const patch = { SUPABASE_URL: url };
if (anon && anon.length >= 40) patch.SUPABASE_ANON_KEY = anon;

upsertEnv(path.join(root, ".env"), patch);
upsertEnv(path.join(root, "apps/desktop/.env"), {
  ...parseEnv(path.join(root, "apps/desktop/.env")),
  ...patch,
  API_URL: parseEnv(path.join(root, "apps/desktop/.env")).API_URL || "http://127.0.0.1:3333",
});

const infoPath = path.join(root, "apps/ios/Companion/Info.plist");
let plist = fs.readFileSync(infoPath, "utf8");
plist = setPlistKey(plist, "SUPABASE_URL", url);
plist = setPlistKey(plist, "SUPABASE_ANON_KEY", anon && anon.length >= 40 ? anon : "");
fs.writeFileSync(infoPath, plist);

const genDir = path.join(root, "apps/ios/Companion/Generated");
fs.mkdirSync(genDir, { recursive: true });
fs.writeFileSync(
  path.join(genDir, "SupabaseDefaults.plist"),
  `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>SUPABASE_URL</key>
\t<string>${escapeXml(url)}</string>
\t<key>SUPABASE_ANON_KEY</key>
\t<string>${escapeXml(anon && anon.length >= 40 ? anon : "")}</string>
</dict>
</plist>
`
);

console.log("OK Supabase sync");
console.log("  URL:", url);
console.log("  anon:", anon && anon.length >= 40 ? `ok (${anon.length} chars)` : "AUSENTE — cole no .env e rode de novo");
console.log("  → apps/desktop/.env");
console.log("  → apps/ios/Companion/Info.plist");
