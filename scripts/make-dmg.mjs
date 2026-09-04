#!/usr/bin/env node
/**
 * Cria DMG via hdiutil (evita bug do 7zip-bin no electron-builder).
 */
import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const desktop = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../apps/desktop");
const release = path.join(desktop, "release");
const appPath = path.join(release, "mac/Companion.app");
const stage = "/tmp/Companion-dmg-stage";
const rw = "/tmp/Companion-rw.dmg";
const out = path.join(release, "Companion-1.0.0-mac.dmg");

if (!fs.existsSync(appPath)) {
  console.error("Companion.app não encontrado em", appPath);
  process.exit(1);
}

fs.rmSync(stage, { recursive: true, force: true });
fs.mkdirSync(stage, { recursive: true });
execSync(`cp -R "${appPath}" "${stage}/"`);
try {
  fs.symlinkSync("/Applications", path.join(stage, "Applications"));
} catch {
  /* ignore */
}

fs.rmSync(rw, { force: true });
fs.rmSync(out, { force: true });

execSync(
  `hdiutil create -volname "Companion" -srcfolder "${stage}" -ov -format UDRW "${rw}"`,
  { stdio: "inherit" }
);
execSync(
  `hdiutil convert "${rw}" -format UDZO -imagekey zlib-level=9 -o "${out}"`,
  { stdio: "inherit" }
);

fs.rmSync(rw, { force: true });
fs.rmSync(stage, { recursive: true, force: true });
console.log("[make-dmg] pronto:", out);
