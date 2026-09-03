import { contextBridge, ipcRenderer } from "electron";

export type PresencePayload = {
  idleMinutes: number;
  timeOfDay: string;
  activity: string;
  listeningMusic: boolean;
  missedYou?: boolean;
  theme?: "dark" | "light";
  batteryPercent?: number | null;
  batteryLow?: boolean;
  trackTitle?: string;
};

export type SkinView = {
  id: string;
  name: string;
  source: string;
  license: string;
  render: "css" | "sprite";
  sprite?: { idle: string };
  unlock: string;
  available: boolean;
  spriteUrl?: string;
  url?: string;
};

contextBridge.exposeInMainWorld("companion", {
  getState: () => ipcRenderer.invoke("companion:getState"),
  interact: (type: string, message?: string) =>
    ipcRenderer.invoke("companion:interact", type, message),
  getFeed: (limit?: number) => ipcRenderer.invoke("companion:getFeed", limit),
  createCompanion: (body: object) => ipcRenderer.invoke("companion:createCompanion", body),
  getSession: () => ipcRenderer.invoke("companion:getSession"),
  setQuizMode: (on: boolean) => ipcRenderer.invoke("companion:setQuizMode", on),
  setCompact: (on: boolean) => ipcRenderer.invoke("companion:setCompact", on),
  setHabitat: (on: boolean) => ipcRenderer.invoke("companion:setHabitat", on),
  touchActivity: (kind?: string) => ipcRenderer.invoke("companion:touchActivity", kind),
  getPresence: () => ipcRenderer.invoke("companion:getPresence"),
  getConfig: () => ipcRenderer.invoke("companion:getConfig"),
  getSkins: () => ipcRenderer.invoke("companion:getSkins"),
  notify: (title: string, body: string) => ipcRenderer.invoke("companion:notify", title, body),
  minimize: () => ipcRenderer.invoke("companion:minimize"),
  resize: (expanded: boolean) => ipcRenderer.invoke("companion:resize", expanded),
  setSkin: (skin: string) => ipcRenderer.invoke("companion:setSkin", skin),
  media: (cmd: "prev" | "toggle" | "next") => ipcRenderer.invoke("companion:media", cmd),
  runPrank: (kind: string) => ipcRenderer.invoke("companion:runPrank", kind),
  onSkinChanged: (cb: (payload: { id: string; skin?: SkinView }) => void) => {
    ipcRenderer.on("companion:skinChanged", (_event, payload) => cb(payload));
  },
  onRestartQuiz: (cb: () => void) => {
    ipcRenderer.on("companion:restartQuiz", () => cb());
  },
  onSessionImported: (cb: () => void) => {
    ipcRenderer.on("companion:sessionImported", () => cb());
  },
  onModeChanged: (cb: (mode: {
    compact: boolean;
    soundMuted: boolean;
    pranksEnabled: boolean;
    habitat?: boolean;
    listeningMusic?: boolean;
  }) => void) => {
    ipcRenderer.on("companion:modeChanged", (_event, mode) => cb(mode));
  },
  onPlaySound: (cb: (kind: string) => void) => {
    ipcRenderer.on("companion:playSound", (_event, kind: string) => cb(kind));
  },
  onPresence: (cb: (payload: PresencePayload) => void) => {
    ipcRenderer.on("companion:presence", (_event, payload: PresencePayload) => cb(payload));
  },
  onLocalLine: (cb: (text: string) => void) => {
    ipcRenderer.on("companion:localLine", (_event, text: string) => cb(text));
  },
});
