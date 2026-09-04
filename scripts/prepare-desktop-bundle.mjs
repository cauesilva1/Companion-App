#!/usr/bin/env node
/**
 * Prepara resources/api + icon para electron-builder.
 * Uso: node scripts/prepare-desktop-bundle.mjs
 */
import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const desktop = path.join(root, "apps/desktop");
const apiOut = path.join(desktop, "resources/api");
const buildDir = path.join(desktop, "build");
const iconPng = path.join(buildDir, "icon.png");
const mortIdle = path.join(desktop, "renderer/assets/skins/dino-mort/idle.png");

console.log("[prepare] compilando API…");
execSync("npx tsc -p tsconfig.json", { cwd: root, stdio: "inherit" });

fs.rmSync(apiOut, { recursive: true, force: true });
fs.mkdirSync(apiOut, { recursive: true });

console.log("[prepare] copiando dist → resources/api…");
copyDir(path.join(root, "dist"), apiOut);

const apiPkg = {
  name: "companion-api-bundle",
  version: "1.0.0",
  private: true,
  main: "server.js",
  dependencies: {
    "@prisma/client": "^5.22.0",
    cors: "^2.8.5",
    dotenv: "^16.4.5",
    express: "^4.21.1",
    zod: "^3.23.8",
  },
};
fs.writeFileSync(path.join(apiOut, "package.json"), JSON.stringify(apiPkg, null, 2));

console.log("[prepare] instalando deps da API…");
execSync("npm install --omit=dev", { cwd: apiOut, stdio: "inherit" });

// Prisma: reutiliza client já gerado na raiz (evita generate lento no bundle)
const rootPrismaClient = path.join(root, "node_modules/.prisma");
const rootPrismaPkg = path.join(root, "node_modules/@prisma/client");
if (fs.existsSync(rootPrismaClient) && fs.existsSync(rootPrismaPkg)) {
  fs.cpSync(rootPrismaClient, path.join(apiOut, "node_modules/.prisma"), { recursive: true });
  fs.cpSync(rootPrismaPkg, path.join(apiOut, "node_modules/@prisma/client"), { recursive: true });
  console.log("[prepare] @prisma/client copiado da raiz");
} else {
  const prismaSchema = path.join(root, "prisma");
  if (fs.existsSync(prismaSchema)) {
    fs.cpSync(prismaSchema, path.join(apiOut, "prisma"), { recursive: true });
    try {
      execSync("npx prisma generate", { cwd: apiOut, stdio: "inherit" });
    } catch (err) {
      console.warn("[prepare] prisma generate avisou:", err.message || err);
    }
  }
}

// .env pessoal (não versionar secrets no git — só no bundle local)
const envSrc = path.join(root, ".env");
const envDst = path.join(desktop, "resources", ".env");
fs.mkdirSync(path.dirname(envDst), { recursive: true });
if (fs.existsSync(envSrc)) {
  // Packaged = mock JSON; remove DATABASE_URL para forçar mock
  const raw = fs.readFileSync(envSrc, "utf8");
  const filtered = raw
    .split("\n")
    .filter((line) => !/^\s*DATABASE_URL\s*=/.test(line))
    .join("\n");
  fs.writeFileSync(envDst, filtered + "\n# forced mock in packaged app\n");
  console.log("[prepare] resources/.env copiado (sem DATABASE_URL)");
} else {
  console.warn("[prepare] .env não encontrado — chat LLM pode falhar no app empacotado");
}

// Seed de companions para primeira abertura do .app
const companionsSrc = path.join(root, "data/companions.json");
const companionsSeed = path.join(apiOut, "seed-companions.json");
if (fs.existsSync(companionsSrc)) {
  fs.copyFileSync(companionsSrc, companionsSeed);
  console.log("[prepare] seed-companions.json incluído");
}

// Ícone 1024 a partir do Mort
fs.mkdirSync(buildDir, { recursive: true });
if (fs.existsSync(mortIdle)) {
  console.log("[prepare] gerando build/icon.png (dino-mort)…");
  try {
    execSync(
      `sips -z 1024 1024 "${mortIdle}" --out "${iconPng}"`,
      { stdio: "inherit" }
    );
  } catch {
    fs.copyFileSync(mortIdle, iconPng);
    console.warn("[prepare] sips falhou — copiou idle.png cru");
  }
} else {
  console.warn("[prepare] idle do mort ausente — sem icon.png");
}

console.log("[prepare] ok");

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}
