#!/usr/bin/env node
/**
 * Registra um dispositivo IoT (ESP32) via Edge Function iot-register.
 *
 * Como obter o JWT (access_token) provisório:
 *
 *   1) Login email/senha (recomendado):
 *      curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
 *        -H "apikey: $SUPABASE_ANON_KEY" \
 *        -H "Content-Type: application/json" \
 *        -d '{"email":"SEU@EMAIL","password":"SUA_SENHA"}' | jq -r .access_token
 *
 *   2) Cole o token em SUPABASE_USER_JWT no .env (NÃO commit) ou passe --token=
 *
 * Uso:
 *   node scripts/register-esp32.mjs --label=mesa
 *   node scripts/register-esp32.mjs --token='eyJ...' --label=mesa
 *
 * Guarde o deviceKey impresso no firmware (header X-Device-Key).
 */

import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function loadEnvFile(path) {
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split("\n")) {
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
    if (!process.env[k]) process.env[k] = v;
  }
}

loadEnvFile(resolve(root, ".env"));

function arg(name, fallback = undefined) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  if (hit) return hit.slice(name.length + 3);
  if (process.argv.includes(`--${name}`)) return true;
  return fallback;
}

if (arg("help") || arg("h")) {
  console.log(`Usage: node scripts/register-esp32.mjs [--token=JWT] [--label=mesa]

Env:
  SUPABASE_URL          (required)
  SUPABASE_USER_JWT     user access_token (or --token=)
  SUPABASE_ANON_KEY     only needed if you fetch the token yourself via curl

Get JWT:
  curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \\
    -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \\
    -d '{"email":"...","password":"..."}' | jq -r .access_token
`);
  process.exit(0);
}

const url = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const token = arg("token") || process.env.SUPABASE_USER_JWT || "";
const label = arg("label") || "mesa";

if (!url.startsWith("http")) {
  console.error("Missing SUPABASE_URL in .env");
  process.exit(1);
}
if (!token || token.length < 20) {
  console.error(
    "Missing JWT. Set SUPABASE_USER_JWT or pass --token=...\n" +
      "See: node scripts/register-esp32.mjs --help"
  );
  process.exit(1);
}

const endpoint = `${url}/functions/v1/iot-register`;
const res = await fetch(endpoint, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${token}`,
    apikey: process.env.SUPABASE_ANON_KEY || "",
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ label }),
});

const text = await res.text();
let body;
try {
  body = JSON.parse(text);
} catch {
  body = { raw: text };
}

if (!res.ok) {
  console.error("Register failed:", res.status, body);
  process.exit(1);
}

console.log("\n=== IoT device registered ===");
console.log("deviceId :", body.deviceId);
console.log("deviceKey:", body.deviceKey);
console.log("label    :", label);
console.log("\nSalve deviceKey no ESP32 (header X-Device-Key). Não é reexibido.");
console.log(
  `\nSmoke presence:\n  curl -s -X POST '${url}/functions/v1/iot-presence' \\\n` +
    `    -H 'X-Device-Key: ${body.deviceKey}' -H 'Content-Type: application/json' \\\n` +
    `    -d '{"rssi":-60}'\n`
);
