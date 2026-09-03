import {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  nativeImage,
  screen,
  Notification,
  globalShortcut,
  dialog,
  nativeTheme,
} from "electron";
import * as path from "path";
import * as fs from "fs";
import * as https from "https";
import * as http from "http";
import * as url from "url";
import { findSkin, isValidSkinId, listSkins, normalizeSkinId, SkinView } from "./skinCatalog";
import { getNowPlaying, mediaCommand } from "./mediaMac";

require("dotenv").config({ path: path.join(__dirname, "../../../../.env") });
require("dotenv").config({ path: path.join(__dirname, "../../.env") });

const API_URL = (process.env.API_URL ?? "http://127.0.0.1:3333").replace(
  "://localhost",
  "://127.0.0.1"
);
console.log("[desktop] API_URL =", API_URL);

const SESSION_PATH = path.join(__dirname, "../../data/session.json");
type PrankKind = "shake" | "bounce" | "notify" | "tease-sound" | "hide-and-seek";

interface SessionData {
  companionId?: string;
  x?: number;
  y?: number;
  compact?: boolean;
  pranksEnabled?: boolean;
  soundMuted?: boolean;
  listeningMusic?: boolean;
  skinId?: string;
}

let companionId = "";
let currentSkinId = "dino-doux";
let lastAlert = "";
let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let quizMode = false;
let compact = false;
let habitatMode = false;
let pranksEnabled = false;
let soundMuted = false;
let listeningMusic = false;
let listeningMusicManual = false;
let savedX: number | undefined;
let savedY: number | undefined;
let prankTimer: ReturnType<typeof setInterval> | null = null;
let presenceTimer: ReturnType<typeof setInterval> | null = null;
let minimizedNotifyTimer: ReturnType<typeof setInterval> | null = null;
let companionName = "Companion";
let lastUserTouchAt = Date.now();
let wasIdle = false;
let lastActivityKind = "present";
let lastTrackTitle = "";
let lastNotifiedTrack = "";
let batteryLowWarned = false;
let windowMinimized = false;
let lastMinimizedNudgeAt = 0;
const IDLE_THRESHOLD_MIN = 3;

function loadSession() {
  try {
    if (fs.existsSync(SESSION_PATH)) {
      const data = JSON.parse(fs.readFileSync(SESSION_PATH, "utf8")) as SessionData;
      companionId = data.companionId ?? "";
      compact = !!data.compact;
      pranksEnabled = !!data.pranksEnabled;
      soundMuted = data.soundMuted === true;
      listeningMusic = !!data.listeningMusic;
      listeningMusicManual = listeningMusic;
      if (data.skinId && isValidSkinId(data.skinId)) currentSkinId = normalizeSkinId(data.skinId);
      savedX = typeof data.x === "number" ? data.x : undefined;
      savedY = typeof data.y === "number" ? data.y : undefined;
    }
  } catch {
    companionId = "";
  }
}

function saveSession() {
  fs.mkdirSync(path.dirname(SESSION_PATH), { recursive: true });
  const payload: SessionData = {
    companionId,
    compact,
    pranksEnabled,
    soundMuted,
    listeningMusic: listeningMusicManual,
    skinId: currentSkinId,
  };
  if (mainWindow && !mainWindow.isDestroyed()) {
    const [x, y] = mainWindow.getPosition();
    payload.x = x;
    payload.y = y;
    savedX = x;
    savedY = y;
  } else {
    if (typeof savedX === "number") payload.x = savedX;
    if (typeof savedY === "number") payload.y = savedY;
  }
  fs.writeFileSync(SESSION_PATH, JSON.stringify(payload, null, 2), "utf8");
}

function fetchJSON<T>(
  endpoint: string,
  options: { method?: string; body?: object } = {}
): Promise<T> {
  return new Promise((resolve, reject) => {
    const fullUrl = `${API_URL}${endpoint}`;
    const parsed = new url.URL(fullUrl);
    const isHttps = parsed.protocol === "https:";
    const transport = isHttps ? https : http;
    const req = transport.request(
      {
        hostname: parsed.hostname,
        port: parsed.port || (isHttps ? 443 : 80),
        path: parsed.pathname + parsed.search,
        method: options.method ?? "GET",
        headers: { "Content-Type": "application/json" },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(data || `HTTP ${res.statusCode}`));
            return;
          }
          try {
            resolve(JSON.parse(data) as T);
          } catch {
            reject(new Error(`Resposta inválida: ${data}`));
          }
        });
      }
    );
    req.on("error", reject);
    if (options.body) req.write(JSON.stringify(options.body));
    req.end();
  });
}

function applySkinToWindow() {
  const skin = findSkin(currentSkinId);
  mainWindow?.webContents.send("companion:skinChanged", {
    id: currentSkinId,
    skin,
  });
}

function windowSize(): { w: number; h: number } {
  if (quizMode) return { w: 520, h: 480 };
  if (habitatMode) return { w: 440, h: 380 };
  if (compact) return { w: 160, h: 160 };
  return { w: 440, h: 210 };
}

function timeOfDay(): string {
  const h = new Date().getHours();
  if (h >= 5 && h < 12) return "morning";
  if (h >= 12 && h < 18) return "afternoon";
  if (h >= 18 && h < 21) return "evening";
  return "night";
}

function getBatteryPercent(): number | null {
  return cachedBatteryPercent;
}

let cachedBatteryPercent: number | null = null;
let cachedOnBattery = false;

async function refreshBattery() {
  if (process.platform !== "darwin") {
    cachedBatteryPercent = null;
    return;
  }
  try {
    const { execFile } = require("child_process") as typeof import("child_process");
    const { promisify } = require("util") as typeof import("util");
    const execFileAsync = promisify(execFile);
    const { stdout } = await execFileAsync("pmset", ["-g", "batt"], { timeout: 2000 });
    const text = String(stdout);
    cachedOnBattery = /discharging/i.test(text);
    const m = text.match(/(\d+)%/);
    cachedBatteryPercent = m ? Number(m[1]) : null;
  } catch {
    cachedBatteryPercent = null;
  }
}

function presencePayload(extra?: { missedYou?: boolean }) {
  const idleMinutes = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
  let activity = lastActivityKind;
  const autoListening = listeningMusic && !listeningMusicManual ? true : listeningMusic;
  if (autoListening || listeningMusic) activity = "listening_music";
  else if (idleMinutes >= IDLE_THRESHOLD_MIN) activity = "idle";
  else if (activity === "idle" || activity === "listening_music") activity = "present";

  const batteryPercent = getBatteryPercent();
  const batteryLow = batteryPercent != null && batteryPercent <= 20 && cachedOnBattery;

  return {
    idleMinutes,
    timeOfDay: timeOfDay(),
    activity,
    listeningMusic: listeningMusic || listeningMusicManual,
    missedYou: extra?.missedYou,
    theme: nativeTheme.shouldUseDarkColors ? "dark" : "light",
    batteryPercent,
    batteryLow,
    trackTitle: lastTrackTitle || undefined,
  };
}

async function refreshNowPlaying() {
  try {
    const info = await getNowPlaying();
    const prev = lastTrackTitle;
    if (info?.playing) {
      listeningMusic = true;
      lastTrackTitle = [info.title, info.artist].filter(Boolean).join(" — ");
      if (lastTrackTitle && lastTrackTitle !== prev) {
        const short = info.title || lastTrackTitle;
        mainWindow?.webContents.send(
          "companion:localLine",
          `Ouvindo “${short}”… curti.`
        );
        if (windowMinimized && lastTrackTitle !== lastNotifiedTrack) {
          lastNotifiedTrack = lastTrackTitle;
          showCompanionNotification(companionName, `Agora tocando: ${short}`);
        }
      }
    } else if (!listeningMusicManual) {
      listeningMusic = false;
      lastTrackTitle = info?.title
        ? [info.title, info.artist].filter(Boolean).join(" — ")
        : "";
    }
  } catch {
    /* ignore */
  }
}

function emitPresence(extra?: { missedYou?: boolean }) {
  const payload = presencePayload(extra);
  mainWindow?.webContents.send("companion:presence", payload);
  if (payload.batteryLow && !batteryLowWarned) {
    batteryLowWarned = true;
    mainWindow?.webContents.send("companion:localLine", "Bateria baixa… me leva perto de uma tomada?");
    if (windowMinimized) {
      showCompanionNotification(companionName, "Bateria baixa… me leva perto de uma tomada?");
    }
  }
  if (!payload.batteryLow) batteryLowWarned = false;
}

function touchUserActivity(kind?: string) {
  const idleMinutes = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
  const missedYou = wasIdle || idleMinutes >= IDLE_THRESHOLD_MIN;
  lastUserTouchAt = Date.now();
  wasIdle = false;
  if (kind === "PLAY") lastActivityKind = "playing";
  else if (kind === "CHAT") lastActivityKind = "chatting";
  else if (kind) lastActivityKind = "present";
  emitPresence(missedYou ? { missedYou: true } : undefined);
}

function emitMode() {
  mainWindow?.webContents.send("companion:modeChanged", {
    compact,
    soundMuted,
    pranksEnabled,
    habitat: habitatMode,
    listeningMusic,
  });
}

function clampToWorkArea(x: number, y: number, w: number, h: number) {
  const { x: wx, y: wy, width: sw, height: sh } = screen.getPrimaryDisplay().workArea;
  return {
    x: Math.min(Math.max(x, wx), wx + sw - w),
    y: Math.min(Math.max(y, wy), wy + sh - h),
  };
}

function placeWindow(opts?: { preservePos?: boolean }) {
  if (!mainWindow) return;
  const { w, h } = windowSize();
  const preserve = opts?.preservePos !== false;
  let x: number;
  let y: number;
  if (preserve && typeof savedX === "number" && typeof savedY === "number") {
    ({ x, y } = clampToWorkArea(savedX, savedY, w, h));
  } else {
    const { width: sw, height: sh } = screen.getPrimaryDisplay().workAreaSize;
    x = sw - w - 16;
    y = sh - h - 16;
  }
  mainWindow.setSize(w, h);
  mainWindow.setPosition(x, y);
  savedX = x;
  savedY = y;
  saveSession();
  emitMode();
  emitPresence();
}

function showCompanionNotification(title: string, body: string) {
  if (!Notification.isSupported()) return;
  const n = new Notification({ title, body, silent: soundMuted });
  n.on("click", () => {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    windowMinimized = false;
    mainWindow.show();
    mainWindow.focus();
  });
  n.show();
}

function pickMinimizedNudge(): string {
  const idleMin = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
  if (listeningMusic && lastTrackTitle) {
    const lines = [
      `Continuo ouvindo “${lastTrackTitle.split(" — ")[0]}” com você.`,
      `Essa faixa tá boa. Volta pra eu comentar.`,
      `Música rolando… e eu aqui no canto.`,
    ];
    return lines[Math.floor(Math.random() * lines.length)];
  }
  if (idleMin >= IDLE_THRESHOLD_MIN) {
    const lines = [
      "Sumiu? Eu tô aqui no tray…",
      "Senti sua falta. Clica em mim.",
      "Ainda tô esperando um poke.",
    ];
    return lines[Math.floor(Math.random() * lines.length)];
  }
  const tod = timeOfDay();
  if (tod === "night") return "Noite calma. Eu fico de olho por você.";
  if (tod === "morning") return "Bom dia! Minimizado, mas acordado.";
  const generic = [
    "Tô no tray. Me chama quando quiser.",
    "Continuo por aqui — só um clique.",
    "Minimizado, mas não esquecido.",
  ];
  return generic[Math.floor(Math.random() * generic.length)];
}

function maybeMinimizedNudge() {
  if (!windowMinimized || !companionId || quizMode) return;
  const now = Date.now();
  if (now - lastMinimizedNudgeAt < 4 * 60_000) return;
  lastMinimizedNudgeAt = now;
  showCompanionNotification(companionName, pickMinimizedNudge());
}

function minimizeToTray() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  windowMinimized = true;
  mainWindow.hide();
  showCompanionNotification(companionName, "Tô no tray. Clica aqui ou no ícone pra voltar.");
}

function toggleVisibility() {
  if (!mainWindow) return;
  if (mainWindow.isVisible()) {
    minimizeToTray();
  } else {
    windowMinimized = false;
    mainWindow.show();
    mainWindow.focus();
  }
}

async function exportCompanions() {
  const result = await dialog.showSaveDialog({
    title: "Exportar companions",
    defaultPath: "companions-export.json",
    filters: [{ name: "JSON", extensions: ["json"] }],
  });
  if (result.canceled || !result.filePath) return;
  try {
    const data = await fetchJSON("/companion/export");
    fs.writeFileSync(result.filePath, JSON.stringify(data, null, 2), "utf8");
  } catch (err) {
    // Fallback: export session + note
    fs.writeFileSync(
      result.filePath,
      JSON.stringify({ companionId, compact, pranksEnabled, soundMuted, x: savedX, y: savedY }, null, 2),
      "utf8"
    );
    console.warn("[desktop] export API falhou, salvou session:", err);
  }
}

async function importCompanions() {
  const result = await dialog.showOpenDialog({
    title: "Importar companions",
    filters: [{ name: "JSON", extensions: ["json"] }],
    properties: ["openFile"],
  });
  if (result.canceled || !result.filePaths[0]) return;
  try {
    const raw = JSON.parse(fs.readFileSync(result.filePaths[0], "utf8"));
    if (raw.companionId) {
      companionId = raw.companionId;
      if (typeof raw.compact === "boolean") compact = raw.compact;
      if (typeof raw.pranksEnabled === "boolean") pranksEnabled = raw.pranksEnabled;
      if (typeof raw.soundMuted === "boolean") soundMuted = raw.soundMuted;
      saveSession();
      rebuildTray();
      mainWindow?.webContents.send("companion:sessionImported");
      placeWindow();
      return;
    }
    await fetchJSON("/companion/import", { method: "POST", body: raw });
    mainWindow?.webContents.send("companion:sessionImported");
  } catch (err) {
    console.warn("[desktop] import falhou:", err);
  }
}

function rebuildTray() {
  if (!tray) return;
  tray.setContextMenu(
    Menu.buildFromTemplate([
      {
        label: "Mostrar Companion",
        click: () => {
          mainWindow?.show();
          mainWindow?.focus();
        },
      },
      { label: "Esconder / minimizar", click: () => minimizeToTray() },
      { label: "Mostrar", click: () => {
        windowMinimized = false;
        mainWindow?.show();
        mainWindow?.focus();
      } },
      {
        label: compact ? "Expandir" : "Modo mínimo",
        click: () => {
          if (quizMode || habitatMode) return;
          compact = !compact;
          saveSession();
          placeWindow();
          rebuildTray();
        },
      },
      {
        label: "Abrir quarto",
        click: () => {
          if (quizMode) return;
          habitatMode = true;
          compact = false;
          placeWindow();
          rebuildTray();
        },
      },
      { type: "separator" },
      {
        label: "Permitir pegadinhas",
        type: "checkbox",
        checked: pranksEnabled,
        click: (item) => {
          pranksEnabled = item.checked;
          saveSession();
          emitMode();
          rebuildTray();
        },
      },
      {
        label: "Som mudo",
        type: "checkbox",
        checked: soundMuted,
        click: (item) => {
          soundMuted = item.checked;
          saveSession();
          emitMode();
          rebuildTray();
        },
      },
      {
        label: "Ouvindo música",
        type: "checkbox",
        checked: listeningMusicManual,
        click: (item) => {
          listeningMusicManual = item.checked;
          listeningMusic = item.checked;
          if (!item.checked) lastTrackTitle = "";
          saveSession();
          emitMode();
          emitPresence();
          rebuildTray();
        },
      },
      { type: "separator" },
      {
        label: "Exportar JSON…",
        click: () => void exportCompanions(),
      },
      {
        label: "Importar JSON…",
        click: () => void importCompanions(),
      },
      {
        label: "Criar novo companion…",
        click: () => {
          companionId = "";
          saveSession();
          mainWindow?.webContents.send("companion:restartQuiz");
        },
      },
      { type: "separator" },
      { label: "Sair", click: () => app.quit() },
    ])
  );
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty());
  tray.setToolTip("Companion");
  rebuildTray();
  tray.on("click", () => toggleVisibility());
}

function playTeaseSound() {
  if (soundMuted) return;
  mainWindow?.webContents.send("companion:playSound", "tease");
}

async function runPrank(kind: PrankKind) {
  if (!pranksEnabled || !mainWindow || mainWindow.isDestroyed() || quizMode) return;

  switch (kind) {
    case "shake": {
      const [ox, oy] = mainWindow.getPosition();
      for (let i = 0; i < 8; i++) {
        const dx = (i % 2 === 0 ? 1 : -1) * (6 + (i % 3));
        mainWindow.setPosition(ox + dx, oy + ((i % 2) * 2 - 1));
        await new Promise((r) => setTimeout(r, 40));
      }
      mainWindow.setPosition(ox, oy);
      break;
    }
    case "bounce": {
      const { w, h } = windowSize();
      const area = screen.getPrimaryDisplay().workArea;
      const corners = [
        { x: area.x + 16, y: area.y + 16 },
        { x: area.x + area.width - w - 16, y: area.y + 16 },
        { x: area.x + 16, y: area.y + area.height - h - 16 },
        { x: area.x + area.width - w - 16, y: area.y + area.height - h - 16 },
      ];
      const pick = corners[Math.floor(Math.random() * corners.length)];
      mainWindow.setPosition(pick.x, pick.y);
      savedX = pick.x;
      savedY = pick.y;
      saveSession();
      break;
    }
    case "notify": {
      showCompanionNotification(companionName, `${companionName} sumiu… brincadeira 👻`);
      break;
    }
    case "tease-sound":
      playTeaseSound();
      break;
    case "hide-and-seek": {
      mainWindow.hide();
      setTimeout(() => {
        if (!mainWindow || mainWindow.isDestroyed()) return;
        mainWindow.show();
        windowMinimized = false;
        showCompanionNotification(companionName, "Achei! 👀");
      }, 5000);
      break;
    }
  }
}

function maybeRandomPrank() {
  if (!pranksEnabled || quizMode || !companionId) return;
  if (Math.random() > 0.15) return;
  const pool: PrankKind[] = ["shake", "bounce", "notify", "tease-sound", "hide-and-seek"];
  void runPrank(pool[Math.floor(Math.random() * pool.length)]);
}

function createWindow() {
  const { w, h } = windowSize();
  quizMode = !companionId;
  const size = quizMode ? { w: 520, h: 480 } : { w, h };
  let x: number;
  let y: number;
  if (typeof savedX === "number" && typeof savedY === "number") {
    ({ x, y } = clampToWorkArea(savedX, savedY, size.w, size.h));
  } else {
    const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;
    x = screenWidth - size.w - 16;
    y = screenHeight - size.h - 16;
  }

  mainWindow = new BrowserWindow({
    width: size.w,
    height: size.h,
    x,
    y,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    resizable: false,
    skipTaskbar: true,
    hasShadow: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, "../../renderer/index.html"));
  mainWindow.on("hide", () => {
    windowMinimized = true;
  });
  mainWindow.on("show", () => {
    windowMinimized = false;
  });
  mainWindow.webContents.on("did-finish-load", () => {
    applySkinToWindow();
    emitMode();
    emitPresence();
  });
  mainWindow.on("focus", () => {
    const idleMinutes = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
    if (idleMinutes >= IDLE_THRESHOLD_MIN || wasIdle) {
      emitPresence({ missedYou: true });
    }
  });
  mainWindow.on("moved", () => {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    const [px, py] = mainWindow.getPosition();
    savedX = px;
    savedY = py;
    saveSession();
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

ipcMain.handle("companion:getSession", () => ({
  companionId,
  compact,
  soundMuted,
  pranksEnabled,
  habitat: habitatMode,
  listeningMusic,
}));

ipcMain.handle("companion:setQuizMode", (_e, on: boolean) => {
  quizMode = on;
  if (on) {
    compact = false;
    habitatMode = false;
  }
  placeWindow({ preservePos: true });
});

ipcMain.handle("companion:setCompact", (_e, on: boolean) => {
  if (quizMode) return { compact };
  compact = !!on;
  if (compact) habitatMode = false;
  saveSession();
  placeWindow();
  rebuildTray();
  return { compact };
});

ipcMain.handle("companion:setHabitat", (_e, on: boolean) => {
  if (quizMode) return { habitat: habitatMode };
  habitatMode = !!on;
  if (habitatMode) compact = false;
  placeWindow();
  rebuildTray();
  return { habitat: habitatMode };
});

ipcMain.handle("companion:touchActivity", (_e, kind?: string) => {
  touchUserActivity(kind);
  return presencePayload();
});

ipcMain.handle("companion:getPresence", () => presencePayload());

ipcMain.handle("companion:createCompanion", async (_e, body: object) => {
  try {
    const data = (await fetchJSON("/companion", { method: "POST", body })) as {
      id: string;
      skin?: string;
      name?: string;
    };
    companionId = data.id;
    if (data.name) companionName = data.name;
    if (data.skin && isValidSkinId(data.skin)) {
      currentSkinId = normalizeSkinId(data.skin);
      applySkinToWindow();
    }
    quizMode = false;
    compact = false;
    habitatMode = false;
    touchUserActivity();
    saveSession();
    rebuildTray();
    placeWindow();
    return { ok: true, data };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
});

ipcMain.handle("companion:getState", async () => {
  if (!companionId) return { ok: false, error: "NO_COMPANION" };
  try {
    const data = (await fetchJSON(`/companion/${companionId}/state`)) as {
      alert?: string;
      name?: string;
      skin?: string;
      artStyle?: string;
      backdrop?: string;
      greeting?: string;
    };
    if (data.name) companionName = data.name;
    if (data.skin && isValidSkinId(data.skin) && data.skin !== currentSkinId) {
      // keep session skin preference; don't override collectible choice from API form
    }
    if (data.alert && data.alert !== lastAlert) {
      lastAlert = data.alert;
      showCompanionNotification(data.name ?? companionName, data.alert);
    }
    return { ok: true, data };
  } catch (err) {
    const msg = String(err);
    if (msg.includes("não encontrado") || msg.includes("404")) {
      return { ok: false, error: "NO_COMPANION" };
    }
    return { ok: false, error: msg };
  }
});

ipcMain.handle("companion:interact", async (_e, type: string, message?: string) => {
  if (!companionId) return { ok: false, error: "NO_COMPANION" };
  try {
    touchUserActivity(type);
    const body: Record<string, unknown> = { type, pranksEnabled };
    if (message) body.message = message;
    const data = (await fetchJSON(`/companion/${companionId}/interact`, {
      method: "POST",
      body,
    })) as { prank?: PrankKind; companion?: { name?: string } };
    if (data.companion?.name) companionName = data.companion.name;
    if (data.prank) void runPrank(data.prank);
    return { ok: true, data };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
});

ipcMain.handle("companion:getFeed", async (_e, limit = 20) => {
  if (!companionId) return { ok: false, error: "NO_COMPANION" };
  try {
    const data = await fetchJSON(`/companion/${companionId}/feed?limit=${limit}`);
    return { ok: true, data };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
});

ipcMain.handle("companion:getConfig", () => ({
  companionId,
  apiUrl: API_URL,
  skin: currentSkinId,
  compact,
  soundMuted,
  pranksEnabled,
  habitat: habitatMode,
  listeningMusic,
}));
ipcMain.handle("companion:getSkins", () => listSkins());
ipcMain.handle("companion:getSkin", () => findSkin(currentSkinId));
ipcMain.handle("companion:setSkin", (_e, skinId: string) => {
  const skin = findSkin(skinId);
  if (!skin) return findSkin(currentSkinId);
  if (skin.render === "sprite" && !skin.available) return findSkin(currentSkinId);
  currentSkinId = skin.id;
  saveSession();
  applySkinToWindow();
  rebuildTray();
  return skin;
});

ipcMain.handle("companion:media", async (_e, cmd: "prev" | "toggle" | "next") => {
  const result = await mediaCommand(cmd);
  if (result.info?.playing) {
    listeningMusic = true;
    lastTrackTitle = [result.info.title, result.info.artist].filter(Boolean).join(" — ");
  } else if (!listeningMusicManual) {
    listeningMusic = false;
    lastTrackTitle = result.info?.title
      ? [result.info.title, result.info.artist].filter(Boolean).join(" — ")
      : "";
  }
  emitPresence();
  return {
    ok: result.ok,
    info: result.info,
    reason: result.reason,
    presence: presencePayload(),
  };
});

ipcMain.handle("companion:resize", (_e, expanded: boolean) => {
  if (quizMode || compact || habitatMode) return;
  const { width: sw, height: sh } = screen.getPrimaryDisplay().workAreaSize;
  const w = expanded ? 520 : 440;
  const h = expanded ? 260 : 210;
  const x = typeof savedX === "number" ? savedX : sw - w - 16;
  const y = typeof savedY === "number" ? savedY : sh - h - 16;
  const pos = clampToWorkArea(x, y, w, h);
  mainWindow?.setSize(w, h);
  mainWindow?.setPosition(pos.x, pos.y);
});

ipcMain.handle("companion:notify", (_e, title: string, body: string) => {
  showCompanionNotification(title, body);
});

ipcMain.handle("companion:minimize", () => {
  minimizeToTray();
  return { ok: true };
});

ipcMain.handle("companion:runPrank", async (_e, kind: PrankKind) => {
  await runPrank(kind);
  return { ok: true };
});

app.whenReady().then(async () => {
  loadSession();
  await refreshBattery();
  await refreshNowPlaying();
  createWindow();
  createTray();
  globalShortcut.register("CommandOrControl+Shift+C", () => toggleVisibility());
  prankTimer = setInterval(() => maybeRandomPrank(), 5 * 60_000);
  presenceTimer = setInterval(() => {
    void (async () => {
      await refreshBattery();
      await refreshNowPlaying();
      const idleMinutes = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
      if (idleMinutes >= IDLE_THRESHOLD_MIN) wasIdle = true;
      emitPresence();
      maybeMinimizedNudge();
    })();
  }, 10_000);
  minimizedNotifyTimer = setInterval(() => maybeMinimizedNudge(), 5 * 60_000);
  nativeTheme.on("updated", () => emitPresence());
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
  if (prankTimer) clearInterval(prankTimer);
  if (presenceTimer) clearInterval(presenceTimer);
  if (minimizedNotifyTimer) clearInterval(minimizedNotifyTimer);
  saveSession();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
