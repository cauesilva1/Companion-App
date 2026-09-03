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
import { getFrontScreenContext, isSensitiveApp } from "./screenContext";

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
  notificationsMuted?: boolean;
  nudgeIntervalMin?: 5 | 15 | 30;
  focusUntil?: number;
  focusHours?: 1 | 2;
  rememberChats?: boolean;
  perceiveApp?: boolean;
  useWindowTitle?: boolean;
  commentMedia?: boolean;
  screenVision?: boolean;
  streakCount?: number;
  lastVisitDay?: string; // YYYY-MM-DD
  missionsDay?: string;
  missionsDone?: string[]; // play|chat|music
}

let companionId = "";
let currentSkinId = "dino-doux";
let lastAlert = "";
let mainWindow: BrowserWindow | null = null;
let toastWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let toastHideTimer: ReturnType<typeof setTimeout> | null = null;
let quizMode = false;
let compact = false;
let habitatMode = false;
let pranksEnabled = false;
let soundMuted = false;
let listeningMusic = false;
let listeningMusicManual = false;
let notificationsMuted = false;
let nudgeIntervalMin: 5 | 15 | 30 = 15;
let focusUntil = 0;
let focusHours: 1 | 2 = 1;
let rememberChats = true;
let perceiveApp = true;
let useWindowTitle = true;
let commentMedia = true;
let screenVision = false;
let streakCount = 0;
let lastVisitDay = "";
let missionsDay = "";
let missionsDone: string[] = [];
let lastScreenHint = "";
let lastScreenApp = "";
let lastScreenKind: string | undefined;
let lastScreenCommentAt = 0;
let screenTimer: ReturnType<typeof setInterval> | null = null;
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
let isQuitting = false;
let cachedAffection = 50;
let cachedEnergy = 80;
const IDLE_THRESHOLD_MIN = 3;

/** Ícone do companion (dino recortado) — tray, toast e notificação nativa. */
function buildCompanionImage(size: number): Electron.NativeImage {
  const candidates = [
    path.join(__dirname, `../../renderer/assets/skins/${currentSkinId}/idle.png`),
    path.join(__dirname, "../../renderer/assets/skins/dino-doux/idle.png"),
  ];
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    let img = nativeImage.createFromPath(file);
    if (img.isEmpty()) continue;
    try {
      const { width, height } = img.getSize();
      const buf = img.toBitmap();
      let minX = width;
      let minY = height;
      let maxX = 0;
      let maxY = 0;
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          const i = (y * width + x) * 4;
          const b = buf[i];
          const g = buf[i + 1];
          const r = buf[i + 2];
          const a = buf[i + 3];
          if (a < 8) continue;
          if (r <= 10 && g <= 10 && b <= 10) continue;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX > minX && maxY > minY) {
        const pad = 4;
        img = img.crop({
          x: Math.max(0, minX - pad),
          y: Math.max(0, minY - pad),
          width: Math.min(width - Math.max(0, minX - pad), maxX - minX + 1 + pad * 2),
          height: Math.min(height - Math.max(0, minY - pad), maxY - minY + 1 + pad * 2),
        });
      }
    } catch {
      /* mantém original */
    }
    return img.resize({ width: size, height: size, quality: "best" });
  }
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    "base64"
  );
  return nativeImage.createFromBuffer(png).resize({ width: size, height: size });
}

function buildTrayImage(): Electron.NativeImage {
  return buildCompanionImage(22);
}

function companionIconDataUrl(size = 72): string {
  const png = buildCompanionImage(size).toPNG();
  return `data:image/png;base64,${png.toString("base64")}`;
}

function updateTrayIcon() {
  if (!tray) return;
  tray.setImage(buildTrayImage());
  tray.setToolTip(companionName || "Companion");
}

function showMainWindow() {
  if (toastWindow && !toastWindow.isDestroyed()) toastWindow.hide();
  if (!mainWindow || mainWindow.isDestroyed()) {
    createWindow();
    return;
  }
  windowMinimized = false;
  if (process.platform === "darwin") {
    app.show();
    app.dock?.show();
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
  if (process.platform === "darwin") {
    app.focus({ steal: true });
  }
}

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
      notificationsMuted = !!data.notificationsMuted;
      if (data.nudgeIntervalMin === 5 || data.nudgeIntervalMin === 15 || data.nudgeIntervalMin === 30) {
        nudgeIntervalMin = data.nudgeIntervalMin;
      }
      focusUntil = typeof data.focusUntil === "number" ? data.focusUntil : 0;
      if (data.focusHours === 1 || data.focusHours === 2) focusHours = data.focusHours;
      rememberChats = data.rememberChats !== false;
      perceiveApp = data.perceiveApp !== false;
      useWindowTitle = data.useWindowTitle !== false;
      commentMedia = data.commentMedia !== false;
      screenVision = !!data.screenVision;
      streakCount = typeof data.streakCount === "number" ? data.streakCount : 0;
      lastVisitDay = typeof data.lastVisitDay === "string" ? data.lastVisitDay : "";
      missionsDay = typeof data.missionsDay === "string" ? data.missionsDay : "";
      missionsDone = Array.isArray(data.missionsDone) ? data.missionsDone.map(String) : [];
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
    notificationsMuted,
    nudgeIntervalMin,
    focusUntil,
    focusHours,
    rememberChats,
    perceiveApp,
    useWindowTitle,
    commentMedia,
    screenVision,
    streakCount,
    lastVisitDay,
    missionsDay,
    missionsDone,
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
  updateTrayIcon();
}

function windowSize(): { w: number; h: number } {
  if (quizMode) return { w: 520, h: 480 };
  if (habitatMode) return { w: 440, h: 380 };
  if (compact) return { w: 160, h: 160 };
  return { w: 440, h: 236 };
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function isFocusModeActive() {
  return focusUntil > Date.now();
}

function settingsPayload() {
  return {
    companionId,
    compact,
    soundMuted,
    notificationsMuted,
    nudgeIntervalMin,
    pranksEnabled,
    habitat: habitatMode,
    listeningMusic: listeningMusicManual,
    focusMode: isFocusModeActive(),
    focusUntil,
    focusHours,
    rememberChats,
    perceiveApp,
    useWindowTitle,
    commentMedia,
    screenVision,
    streakCount,
    missions: { day: missionsDay, done: missionsDone },
    screenHint: lastScreenHint,
    screenApp: lastScreenApp,
  };
}

function emitSettings() {
  mainWindow?.webContents.send("companion:settingsChanged", settingsPayload());
  emitMode();
}

function ensureDailyProgress() {
  const day = todayKey();
  if (lastVisitDay !== day) {
    if (lastVisitDay) {
      const prev = new Date(lastVisitDay + "T12:00:00");
      const cur = new Date(day + "T12:00:00");
      const diff = Math.round((cur.getTime() - prev.getTime()) / (24 * 3600 * 1000));
      streakCount = diff === 1 ? streakCount + 1 : 1;
    } else {
      streakCount = 1;
    }
    lastVisitDay = day;
  }
  if (missionsDay !== day) {
    missionsDay = day;
    missionsDone = [];
  }
  saveSession();
}

function markMission(id: "play" | "chat" | "music") {
  ensureDailyProgress();
  if (!missionsDone.includes(id)) {
    missionsDone = [...missionsDone, id];
    saveSession();
    emitSettings();
  }
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
    frontApp: lastScreenApp || undefined,
    screenHint: lastScreenHint || undefined,
    screenKind: lastScreenKind || undefined,
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
        markMission("music");
        const short = info.title || lastTrackTitle;
        mainWindow?.webContents.send(
          "companion:localLine",
          `Ouvindo “${short}”… curti.`
        );
        if (windowMinimized && lastTrackTitle !== lastNotifiedTrack && !notificationsMuted) {
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

async function refreshScreenContext() {
  if (!perceiveApp || isFocusModeActive()) {
    lastScreenHint = "";
    lastScreenApp = "";
    lastScreenKind = undefined;
    return;
  }
  const ctx = await getFrontScreenContext();
  if (!ctx || isSensitiveApp(ctx.appName)) {
    lastScreenHint = "";
    lastScreenApp = "";
    lastScreenKind = undefined;
    return;
  }
  const prevHint = lastScreenHint;
  lastScreenApp = ctx.appName;
  lastScreenKind = ctx.kind;
  lastScreenHint = useWindowTitle ? ctx.hint : `Junto no ${ctx.appName}.`;
  if (
    commentMedia &&
    (ctx.kind === "video" || ctx.kind === "reading" || ctx.kind === "music") &&
    lastScreenHint &&
    lastScreenHint !== prevHint &&
    mainWindow &&
    !mainWindow.isDestroyed() &&
    mainWindow.isVisible() &&
    !windowMinimized
  ) {
    const now = Date.now();
    if (now - lastScreenCommentAt > 90_000) {
      lastScreenCommentAt = now;
      mainWindow.webContents.send("companion:localLine", lastScreenHint);
    }
  }
  emitPresence();
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
    notificationsMuted,
    nudgeIntervalMin,
    rememberChats,
    focusMode: isFocusModeActive(),
    perceiveApp,
    screenVision,
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

/** Toast próprio — no macOS a notificação nativa falha fácil (sem assinatura / foco / permissão). */
function showFallbackToast(title: string, body: string) {
  const work = screen.getPrimaryDisplay().workArea;
  const w = 360;
  const h = 104;
  const x = work.x + work.width - w - 20;
  const y = work.y + 24;

  if (toastHideTimer) {
    clearTimeout(toastHideTimer);
    toastHideTimer = null;
  }

  if (!toastWindow || toastWindow.isDestroyed()) {
    toastWindow = new BrowserWindow({
      width: w,
      height: h,
      x,
      y,
      frame: false,
      transparent: true,
      alwaysOnTop: true,
      resizable: false,
      skipTaskbar: true,
      focusable: true,
      hasShadow: false,
      show: false,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
      },
    });
    toastWindow.setAlwaysOnTop(true, "floating");
    toastWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    toastWindow.on("closed", () => {
      toastWindow = null;
    });
    toastWindow.on("page-title-updated", (e, nextTitle) => {
      if (nextTitle !== "companion-toast-click") return;
      e.preventDefault();
      if (toastWindow && !toastWindow.isDestroyed()) toastWindow.hide();
      showMainWindow();
    });
  } else {
    toastWindow.setBounds({ x, y, width: w, height: h });
  }

  const safeTitle = escapeHtml(title);
  const safeBody = escapeHtml(body);
  const avatar = companionIconDataUrl(96);
  const html = `<!doctype html>
<html><head><meta charset="utf-8" />
<style>
  html, body { margin:0; background:transparent; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; overflow:hidden; }
  .toast {
    margin: 6px; padding: 10px 12px; border-radius: 16px;
    display: flex; gap: 12px; align-items: center;
    background: linear-gradient(145deg, rgba(28,32,48,.96), rgba(18,20,30,.96));
    color: #f4f4f8;
    box-shadow: 0 12px 32px rgba(0,0,0,.4), inset 0 1px 0 rgba(255,255,255,.06);
    border: 1px solid rgba(167, 139, 250, .28);
    cursor: pointer; user-select: none;
  }
  .avatar-wrap {
    width: 56px; height: 56px; flex-shrink: 0;
    border-radius: 14px;
    background: radial-gradient(circle at 40% 35%, #7dd3fc 0%, #1e3a5f 70%);
    border: 1px solid rgba(255,255,255,.18);
    display: grid; place-items: center;
    overflow: hidden;
  }
  .avatar {
    width: 48px; height: 48px;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }
  .copy { min-width: 0; flex: 1; }
  .eyebrow {
    font-size: 9px; letter-spacing: .08em; text-transform: uppercase;
    color: #c4b5fd; margin-bottom: 2px; font-weight: 700;
  }
  .title { font-weight: 700; font-size: 13px; margin-bottom: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .body { font-size: 12px; line-height: 1.35; opacity: .9; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
</style></head>
<body>
  <div class="toast" id="t">
    <div class="avatar-wrap"><img class="avatar" src="${avatar}" alt="" /></div>
    <div class="copy">
      <div class="eyebrow">Companion</div>
      <div class="title">${safeTitle}</div>
      <div class="body">${safeBody}</div>
    </div>
  </div>
  <script>
    document.getElementById('t').addEventListener('click', () => {
      document.title = 'companion-toast-click';
    });
  </script>
</body></html>`;

  void toastWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
  toastWindow.once("ready-to-show", () => {
    if (!toastWindow || toastWindow.isDestroyed()) return;
    toastWindow.showInactive();
  });

  toastHideTimer = setTimeout(() => {
    if (toastWindow && !toastWindow.isDestroyed()) toastWindow.hide();
    toastHideTimer = null;
  }, 5500);
}

function escapeHtml(s: string) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function showCompanionNotification(title: string, body: string, opts?: { forceToast?: boolean }) {
  if (notificationsMuted) return;

  const forceToast = opts?.forceToast ?? windowMinimized;

  // Toast próprio sempre que estiver minimizado — confiável no macOS
  if (forceToast) {
    showFallbackToast(title, body);
    if (process.platform === "darwin") {
      try {
        app.dock?.bounce("informational");
      } catch {
        /* ignore */
      }
    }
  }

  if (!Notification.isSupported()) {
    if (!forceToast) showFallbackToast(title, body);
    return;
  }

  try {
    const n = new Notification({
      title,
      body,
      icon: buildCompanionImage(128),
      silent: soundMuted,
    });
    n.on("click", () => showMainWindow());
    n.on("failed", (_e, err) => {
      console.warn("[desktop] notificação nativa falhou:", err);
      if (!forceToast) showFallbackToast(title, body);
    });
    n.show();
  } catch (err) {
    console.warn("[desktop] notificação nativa erro:", err);
    if (!forceToast) showFallbackToast(title, body);
  }
}

function pickMinimizedNudge(): string {
  if (cachedEnergy < 25) {
    return "Sem energia… brinca comigo um pouco?";
  }
  if (cachedAffection < 28) {
    return "Tô com saudade. Um poke resolve.";
  }
  if (lastScreenHint && commentMedia && Math.random() < 0.55) {
    return lastScreenHint;
  }
  const idleMin = Math.floor((Date.now() - lastUserTouchAt) / 60_000);
  if (listeningMusic && lastTrackTitle) {
    const lines = [
      `Continuo ouvindo “${lastTrackTitle.split(" — ")[0]}” com você.`,
      `Essa faixa tá boa. Volta pra eu comentar.`,
      `Música rolando… e eu aqui no canto.`,
    ];
    return lines[Math.floor(Math.random() * lines.length)];
  }
  if (lastScreenHint && commentMedia) {
    const contextual = [
      lastScreenHint,
      `Ainda no ${lastScreenApp || "app"}… eu tô por aqui.`,
      "Vi o que você tá fazendo. Volta quando puder.",
    ];
    return contextual[Math.floor(Math.random() * contextual.length)];
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
  if (notificationsMuted || isFocusModeActive() || !windowMinimized || !companionId || quizMode) {
    return;
  }
  const now = Date.now();
  const interval = nudgeIntervalMin * 60_000;
  if (now - lastMinimizedNudgeAt < interval) return;
  lastMinimizedNudgeAt = now;
  showCompanionNotification(companionName, pickMinimizedNudge());
}

function minimizeToTray() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  windowMinimized = true;
  mainWindow.hide();
  updateTrayIcon();
  // No macOS, banner nativo some se o app ainda estiver em foco —
  // esconde o app e atrasa um pouco a notificação.
  if (process.platform === "darwin") {
    app.hide();
  }
  if (notificationsMuted) return;
  setTimeout(() => {
    showCompanionNotification(
      companionName,
      "Tô no tray (barra de menus). Clica no ícone do dino, no toast ou no Dock pra voltar.",
      { forceToast: true }
    );
  }, 450);
}

function toggleVisibility() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    showMainWindow();
    return;
  }
  if (mainWindow.isVisible() && !windowMinimized) {
    minimizeToTray();
  } else {
    showMainWindow();
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
  updateTrayIcon();
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: "Mostrar Companion", click: () => showMainWindow() },
      { label: "Esconder / minimizar", click: () => minimizeToTray() },
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
          emitSettings();
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
          emitSettings();
          rebuildTray();
        },
      },
      {
        label: "Notificações mudas",
        type: "checkbox",
        checked: notificationsMuted,
        click: (item) => {
          notificationsMuted = item.checked;
          saveSession();
          emitSettings();
          rebuildTray();
        },
      },
      {
        label: "Modo foco",
        type: "checkbox",
        checked: isFocusModeActive(),
        click: (item) => {
          if (item.checked) {
            focusUntil = Date.now() + focusHours * 3600_000;
            showCompanionNotification(companionName, "Modo foco ligado");
          } else {
            focusUntil = 0;
          }
          saveSession();
          emitSettings();
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
          emitSettings();
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
      {
        label: "Sair",
        click: () => {
          isQuitting = true;
          app.quit();
        },
      },
    ])
  );
}

function createTray() {
  if (tray) {
    tray.destroy();
    tray = null;
  }
  tray = new Tray(buildTrayImage());
  tray.setToolTip(companionName || "Companion");
  rebuildTray();
  // macOS: com context menu, clique esquerdo abre o menu; double-click / click ainda ajudam
  tray.on("click", () => showMainWindow());
  tray.on("double-click", () => showMainWindow());
  tray.on("right-click", () => {
    tray?.popUpContextMenu();
  });
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
      windowMinimized = true;
      mainWindow.hide();
      setTimeout(() => {
        if (!mainWindow || mainWindow.isDestroyed()) return;
        showMainWindow();
        showCompanionNotification(companionName, "Achei! 👀");
      }, 5000);
      break;
    }
  }
}

function maybeRandomPrank() {
  if (!pranksEnabled || quizMode || !companionId || isFocusModeActive()) return;
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
  // × do sistema / Cmd+W não deve matar o app — volta pro tray
  mainWindow.on("close", (e) => {
    if (isQuitting) return;
    e.preventDefault();
    minimizeToTray();
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

ipcMain.handle("companion:getSession", () => settingsPayload());

ipcMain.handle("companion:getSettings", () => settingsPayload());

function applySettingsPatch(patch: Record<string, unknown> = {}) {
  const prevCompact = compact;
  const prevHabitat = habitatMode;
  let focusToggledOn = false;

  if (typeof patch.compact === "boolean") {
    compact = patch.compact;
    if (compact) habitatMode = false;
  }
  if (typeof patch.habitat === "boolean") {
    habitatMode = patch.habitat;
    if (habitatMode) compact = false;
  }
  if (typeof patch.soundMuted === "boolean") soundMuted = patch.soundMuted;
  if (typeof patch.notificationsMuted === "boolean") notificationsMuted = patch.notificationsMuted;
  if (typeof patch.pranksEnabled === "boolean") pranksEnabled = patch.pranksEnabled;
  if (patch.nudgeIntervalMin === 5 || patch.nudgeIntervalMin === 15 || patch.nudgeIntervalMin === 30) {
    nudgeIntervalMin = patch.nudgeIntervalMin;
  }
  if (patch.focusHours === 1 || patch.focusHours === 2) focusHours = patch.focusHours;
  if (typeof patch.rememberChats === "boolean") rememberChats = patch.rememberChats;
  if (typeof patch.perceiveApp === "boolean") perceiveApp = patch.perceiveApp;
  if (typeof patch.useWindowTitle === "boolean") useWindowTitle = patch.useWindowTitle;
  if (typeof patch.commentMedia === "boolean") commentMedia = patch.commentMedia;
  if (typeof patch.screenVision === "boolean") screenVision = patch.screenVision;
  if (typeof patch.listeningMusic === "boolean") {
    listeningMusicManual = patch.listeningMusic;
    listeningMusic = patch.listeningMusic;
    if (!patch.listeningMusic) lastTrackTitle = "";
  }

  if (typeof patch.focusMode === "boolean") {
    if (patch.focusMode) {
      focusUntil = Date.now() + focusHours * 3600_000;
      focusToggledOn = true;
    } else {
      focusUntil = 0;
    }
  }

  if (!perceiveApp || isFocusModeActive()) {
    lastScreenHint = "";
    lastScreenApp = "";
    lastScreenKind = undefined;
  }

  saveSession();
  rebuildTray();
  emitSettings();

  if (prevCompact !== compact || prevHabitat !== habitatMode) {
    placeWindow();
  }

  if (focusToggledOn) {
    showCompanionNotification(companionName, "Modo foco ligado");
  }

  if (perceiveApp && !isFocusModeActive()) {
    void refreshScreenContext();
  }

  return settingsPayload();
}

ipcMain.handle("companion:setSettings", (_e, patch: Record<string, unknown> = {}) =>
  applySettingsPatch(patch ?? {})
);

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
    ensureDailyProgress();
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
    ensureDailyProgress();
    const data = (await fetchJSON(`/companion/${companionId}/state`)) as {
      alert?: string;
      name?: string;
      skin?: string;
      artStyle?: string;
      backdrop?: string;
      greeting?: string;
      affection?: number;
      energy?: number;
    };
    if (typeof data.affection === "number") cachedAffection = data.affection;
    if (typeof data.energy === "number") cachedEnergy = data.energy;
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
    if (type === "PLAY") markMission("play");
    if (type === "CHAT") markMission("chat");
    const body: Record<string, unknown> = {
      type,
      pranksEnabled,
      rememberChats,
      trackTitle: lastTrackTitle || undefined,
      screenHint: perceiveApp ? lastScreenHint || undefined : undefined,
    };
    if (message) body.message = message;
    const data = (await fetchJSON(`/companion/${companionId}/interact`, {
      method: "POST",
      body,
    })) as {
      prank?: PrankKind;
      companion?: { name?: string; affection?: number; energy?: number };
    };
    if (data.companion?.name) companionName = data.companion.name;
    if (typeof data.companion?.affection === "number") cachedAffection = data.companion.affection;
    if (typeof data.companion?.energy === "number") cachedEnergy = data.companion.energy;
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
  const h = expanded ? 286 : 236;
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

ipcMain.handle("companion:setSoundMuted", (_e, on: boolean) => {
  applySettingsPatch({ soundMuted: !!on });
  return { soundMuted };
});

ipcMain.handle("companion:runPrank", async (_e, kind: PrankKind) => {
  await runPrank(kind);
  return { ok: true };
});

app.whenReady().then(async () => {
  loadSession();
  ensureDailyProgress();
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
  void refreshScreenContext();
  screenTimer = setInterval(() => {
    if (perceiveApp) void refreshScreenContext();
  }, 15_000);
  nativeTheme.on("updated", () => emitPresence());
  app.on("activate", () => {
    // Dock click: janela escondida ainda existe — precisa show, não create
    showMainWindow();
  });
});

app.on("before-quit", () => {
  isQuitting = true;
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
  if (prankTimer) clearInterval(prankTimer);
  if (presenceTimer) clearInterval(presenceTimer);
  if (minimizedNotifyTimer) clearInterval(minimizedNotifyTimer);
  if (screenTimer) clearInterval(screenTimer);
  if (toastHideTimer) clearTimeout(toastHideTimer);
  if (toastWindow && !toastWindow.isDestroyed()) {
    toastWindow.destroy();
    toastWindow = null;
  }
  if (tray) {
    tray.destroy();
    tray = null;
  }
  saveSession();
});

app.on("window-all-closed", () => {
  // macOS: fica vivo no tray/Dock mesmo sem janela visível
  if (process.platform !== "darwin") app.quit();
});
