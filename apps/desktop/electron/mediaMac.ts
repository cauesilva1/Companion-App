import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

export type MediaInfo = {
  playing: boolean;
  title?: string;
  artist?: string;
  app?: string;
};

function clean(s: string) {
  return s.replace(/\r/g, "").trim();
}

async function osa(script: string, timeout = 4000): Promise<string> {
  const { stdout } = await execFileAsync("osascript", ["-e", script], {
    timeout,
    maxBuffer: 64 * 1024,
  });
  return clean(String(stdout ?? ""));
}

/** Nunca abre o app — só consulta se já estiver rodando. */
async function isAppRunning(appName: "Music" | "Spotify"): Promise<boolean> {
  try {
    const out = await osa(
      `tell application "System Events" to (name of processes) contains "${appName}"`
    );
    return out.toLowerCase() === "true";
  } catch {
    return false;
  }
}

async function readPlayer(app: "Music" | "Spotify"): Promise<MediaInfo | null> {
  if (!(await isAppRunning(app))) return null;
  try {
    // Uma chamada só — mais rápido e menos permissão frágil
    const out = await osa(
      `tell application "${app}"
  if it is not running then return "off|||"
  set st to player state as string
  set t to ""
  set a to ""
  try
    set t to name of current track as string
    set a to artist of current track as string
  end try
  return st & "|" & t & "|" & a
end tell`
    );
    if (!out || out.startsWith("off")) return { playing: false, app };
    const [state, title, artist] = out.split("|");
    const playing = state === "playing";
    return {
      playing,
      title: title || undefined,
      artist: artist || undefined,
      app,
    };
  } catch {
    return null;
  }
}

export async function getNowPlaying(): Promise<MediaInfo | null> {
  if (process.platform !== "darwin") return null;
  const spotify = await readPlayer("Spotify");
  if (spotify?.playing) return spotify;
  const music = await readPlayer("Music");
  if (music?.playing) return music;
  if (spotify) return spotify;
  if (music) return music;
  return null;
}

/**
 * Só controla player que JÁ está aberto.
 * Nunca chama `tell application` se o processo não existir (isso abriria o app).
 */
export async function mediaCommand(
  cmd: "prev" | "toggle" | "next"
): Promise<{ ok: boolean; info: MediaInfo | null; reason?: string }> {
  if (process.platform !== "darwin") {
    return { ok: false, info: null, reason: "unsupported" };
  }

  const action: Record<string, string> = {
    toggle: "playpause",
    next: "next track",
    prev: "previous track",
  };
  const verb = action[cmd];
  if (!verb) return { ok: false, info: null, reason: "bad_cmd" };

  const now = await getNowPlaying();
  const order: ("Spotify" | "Music")[] =
    now?.app === "Music" ? ["Music", "Spotify"] : ["Spotify", "Music"];

  let ok = false;
  let lastErr = "";

  for (const app of order) {
    if (!(await isAppRunning(app))) continue;
    try {
      await osa(`tell application "${app}" to ${verb}`, 5000);
      ok = true;
      break;
    } catch (err) {
      lastErr = String(err);
    }
  }

  // Pequena pausa para o player atualizar o título
  await new Promise((r) => setTimeout(r, 250));
  const info = await getNowPlaying();
  if (!ok) {
    return {
      ok: false,
      info,
      reason: lastErr.includes("(-1743)") || lastErr.toLowerCase().includes("not authorized")
        ? "no_permission"
        : "no_player",
    };
  }
  return { ok: true, info };
}
