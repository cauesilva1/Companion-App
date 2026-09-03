import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

export type ScreenContext = {
  appName: string;
  windowTitle: string;
  kind: "browser" | "video" | "reading" | "code" | "music" | "other";
  hint: string;
};

const SENSITIVE_APPS = [
  "1password",
  "keychain",
  "bitwarden",
  "lastpass",
  "banking",
  "terminal",
  "iterm",
];

function classify(appName: string, title: string): ScreenContext["kind"] {
  const a = appName.toLowerCase();
  const t = title.toLowerCase();
  if (a.includes("spotify") || a.includes("music")) return "music";
  if (
    t.includes("youtube") ||
    t.includes("netflix") ||
    t.includes("twitch") ||
    a.includes("vlc") ||
    a.includes("iina")
  ) {
    return "video";
  }
  if (
    a.includes("preview") ||
    a.includes("books") ||
    a.includes("kindle") ||
    t.endsWith(".pdf") ||
    t.includes(".epub")
  ) {
    return "reading";
  }
  if (
    a.includes("code") ||
    a.includes("cursor") ||
    a.includes("xcode") ||
    a.includes("terminal") ||
    a.includes("iterm")
  ) {
    return "code";
  }
  if (
    a.includes("safari") ||
    a.includes("chrome") ||
    a.includes("firefox") ||
    a.includes("arc") ||
    a.includes("brave") ||
    a.includes("edge")
  ) {
    return "browser";
  }
  return "other";
}

function hintFor(kind: ScreenContext["kind"], appName: string, title: string): string {
  const shortTitle = title.length > 48 ? `${title.slice(0, 45)}…` : title;
  switch (kind) {
    case "video":
      return shortTitle ? `Parece um vídeo: “${shortTitle}”.` : `Você tá em ${appName} — mode vídeo?`;
    case "reading":
      return shortTitle ? `Lendo “${shortTitle}”?` : `Modo leitura no ${appName}.`;
    case "code":
      return `Codando no ${appName}. Eu fico quietinho… ou não.`;
    case "music":
      return `Música no ar via ${appName}.`;
    case "browser":
      return shortTitle ? `Navegando: “${shortTitle}”.` : `No ${appName} com você.`;
    default:
      return `Junto no ${appName}.`;
  }
}

export function isSensitiveApp(appName: string): boolean {
  const a = appName.toLowerCase();
  return SENSITIVE_APPS.some((s) => a.includes(s));
}

/**
 * Camadas 1–2: app frontmost + título da janela (macOS).
 * Sem Screen Recording.
 */
export async function getFrontScreenContext(): Promise<ScreenContext | null> {
  if (process.platform !== "darwin") return null;
  try {
    const { stdout } = await execFileAsync(
      "osascript",
      [
        "-e",
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ],
      { timeout: 2500 }
    );
    const appName = String(stdout).trim();
    if (!appName || /electron|companion/i.test(appName)) return null;

    let windowTitle = "";
    try {
      const { stdout: titleOut } = await execFileAsync(
        "osascript",
        [
          "-e",
          `tell application "System Events" to tell process "${appName.replace(/"/g, '\\"')}" to get name of front window`,
        ],
        { timeout: 2500 }
      );
      windowTitle = String(titleOut).trim();
    } catch {
      windowTitle = "";
    }

    const kind = classify(appName, windowTitle);
    return {
      appName,
      windowTitle,
      kind,
      hint: hintFor(kind, appName, windowTitle),
    };
  } catch {
    return null;
  }
}
