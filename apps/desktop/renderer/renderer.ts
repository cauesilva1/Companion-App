type Archetype = "curioso" | "preguicoso" | "carinhoso" | "zoeiro" | "misterioso";
type ArtStyle = "pixel";
type Backdrop = "sky";

interface QuizOption {
  label: string;
  scores: { archetype: Partial<Record<Archetype, number>> };
}

interface QuizQuestion {
  id: string;
  prompt: string;
  options: QuizOption[];
}

interface CompanionDraft {
  name: string;
  personality: string;
  skin: string;
  artStyle: ArtStyle;
  backdrop: Backdrop;
  archetype: Archetype;
  blurb: string;
}

const QUIZ: QuizQuestion[] = [
  {
    id: "cafe-line",
    prompt: "Alguém fura a fila do café. Você…",
    options: [
      { label: "Chama a pessoa e pergunta a história toda", scores: { archetype: { curioso: 3 } } },
      { label: "Finge que não viu e continua no celular", scores: { archetype: { preguicoso: 3 } } },
      { label: "Puxa a pessoa de lado e oferece seu lugar", scores: { archetype: { carinhoso: 3 } } },
      { label: "Faz um comentário alto e irônico", scores: { archetype: { zoeiro: 3 } } },
      { label: "Observa em silêncio e anota o padrão", scores: { archetype: { misterioso: 3 } } },
    ],
  },
  {
    id: "secret",
    prompt: "Um amigo te conta um segredo pesado. Você…",
    options: [
      { label: "Faz mil perguntas até entender tudo", scores: { archetype: { curioso: 3 } } },
      { label: "Diz “ok” e volta a deitar no sofá", scores: { archetype: { preguicoso: 3 } } },
      { label: "Abraça e muda de assunto com carinho", scores: { archetype: { carinhoso: 3 } } },
      { label: "Espalha de brincadeira… e se arrepende", scores: { archetype: { zoeiro: 3 } } },
      { label: "Guarda. Nem confirma, nem nega", scores: { archetype: { misterioso: 3 } } },
    ],
  },
  {
    id: "gift",
    prompt: "Chega uma caixa surpresa com seu nome. Você…",
    options: [
      { label: "Abre na hora e investiga cada detalhe", scores: { archetype: { curioso: 3 } } },
      { label: "Deixa pro domingo — sem pressa", scores: { archetype: { preguicoso: 3 } } },
      { label: "Manda foto pra quem enviou, emocionado", scores: { archetype: { carinhoso: 3 } } },
      { label: "Faz um teatro inteiro antes de abrir", scores: { archetype: { zoeiro: 3 } } },
      { label: "Cheira a caixa, balança, sem abrir ainda", scores: { archetype: { misterioso: 3 } } },
    ],
  },
  {
    id: "conflict",
    prompt: "Alguém te corta no meio de uma conversa. Você…",
    options: [
      { label: "Pergunta o que a pessoa queria dizer", scores: { archetype: { curioso: 2, carinhoso: 1 } } },
      { label: "Desliga mentalmente e deixa rolar", scores: { archetype: { preguicoso: 3 } } },
      { label: "Volta depois com um “ei, eu ainda estou aqui”", scores: { archetype: { carinhoso: 3 } } },
      { label: "Responde com uma zoação na hora", scores: { archetype: { zoeiro: 3 } } },
      { label: "Fecha a cara e some da conversa", scores: { archetype: { misterioso: 3 } } },
    ],
  },
  {
    id: "mirror",
    prompt: "Se o companion te imitasse, ele seria…",
    options: [
      { label: "Perguntão, sempre no seu pé", scores: { archetype: { curioso: 4 } } },
      { label: "Lento, ácido, mestre do “depois”", scores: { archetype: { preguicoso: 4 } } },
      { label: "Colado em você, cheio de carinho", scores: { archetype: { carinhoso: 4 } } },
      { label: "Dramático e pronto pra zoar", scores: { archetype: { zoeiro: 4 } } },
      { label: "Calado, observando tudo", scores: { archetype: { misterioso: 4 } } },
    ],
  },
];

const PERSONALITY: Record<Archetype, string> = {
  curioso: "curioso e tagarela",
  preguicoso: "preguicoso e sarcastico",
  carinhoso: "carinhoso e grudento",
  zoeiro: "zoeiro e dramatico",
  misterioso: "misterioso e filosofico",
};

const NAMES: Record<Archetype, string> = {
  curioso: "Pip",
  preguicoso: "Mochi",
  carinhoso: "Nunu",
  zoeiro: "Nox",
  misterioso: "Vesper",
};

const DINO_BLURB: Record<Archetype, string> = {
  curioso: "Nasceu o Doux — amarelo, perguntão, sempre no seu pé.",
  preguicoso: "Nasceu o Olaf — azul, lento, e com opinião sobre tudo.",
  carinhoso: "Nasceu a Vita — verde, colada em você.",
  zoeiro: "Nasceu o Mort — rosa, dramático, pronto pra zoar.",
  misterioso: "Nasceu o Kuro — escuro, calado, observando.",
};

function pickMax<T extends string>(scores: Record<T, number>, fallback: T): T {
  let best = fallback;
  let n = -1;
  for (const [k, v] of Object.entries(scores) as [T, number][]) {
    if (v > n) {
      n = v;
      best = k;
    }
  }
  return best;
}

function deriveCompanion(choices: number[]): CompanionDraft {
  const archetype: Record<Archetype, number> = { curioso: 0, preguicoso: 0, carinhoso: 0, zoeiro: 0, misterioso: 0 };

  QUIZ.forEach((q, i) => {
    const opt = q.options[choices[i]];
    if (!opt) return;
    for (const [k, v] of Object.entries(opt.scores.archetype)) archetype[k as Archetype] += v ?? 0;
  });

  const arch = pickMax(archetype, "curioso");
  const skinByArch: Record<Archetype, string> = {
    curioso: "dino-doux",
    preguicoso: "dino-olaf",
    carinhoso: "dino-vita",
    zoeiro: "dino-mort",
    misterioso: "dino-kuro",
  };

  return {
    name: NAMES[arch],
    personality: PERSONALITY[arch],
    skin: skinByArch[arch],
    artStyle: "pixel",
    backdrop: "sky",
    archetype: arch,
    blurb: DINO_BLURB[arch],
  };
}

interface CompanionState {
  id: string;
  name: string;
  personality: string;
  skin: string;
  artStyle?: string;
  backdrop?: string;
  archetype?: string;
  mood: string;
  affection: number;
  energy?: number;
  lastInteractionAt: string | null;
  moodText?: string;
  alert?: string;
  greeting?: string;
  memoryNotes?: string[];
}

interface CompanionSettings {
  companionId?: string;
  compact?: boolean;
  soundMuted?: boolean;
  notificationsMuted?: boolean;
  nudgeIntervalMin?: number;
  pranksEnabled?: boolean;
  habitat?: boolean;
  listeningMusic?: boolean;
  focusMode?: boolean;
  focusUntil?: number;
  focusHours?: number;
  rememberChats?: boolean;
  perceiveApp?: boolean;
  useWindowTitle?: boolean;
  commentMedia?: boolean;
  screenVision?: boolean;
  streakCount?: number;
  missions?: { day?: string; done?: string[] };
  screenHint?: string;
  screenApp?: string;
}

const MISSION_IDS = ["play", "chat", "music"] as const;
const MISSION_LABELS: Record<(typeof MISSION_IDS)[number], string> = {
  play: "Brincar",
  chat: "Conversar",
  music: "Ouvir música",
};

interface InteractionResult {
  companion: CompanionState;
  reaction: string;
  prank?: string;
}

interface FeedItem {
  id: string;
  type: string;
  userMessage?: string | null;
  reactionText: string;
  moodAfter: string;
  createdAt: string;
  companionName?: string;
}

interface IpcResult<T> {
  ok: boolean;
  data?: T;
  error?: string;
}

interface PresencePayload {
  idleMinutes: number;
  timeOfDay: string;
  activity: string;
  listeningMusic: boolean;
  missedYou?: boolean;
  theme?: "dark" | "light";
  batteryPercent?: number | null;
  batteryLow?: boolean;
  trackTitle?: string;
  frontApp?: string;
  screenHint?: string;
  screenKind?: string;
}

interface SkinView {
  id: string;
  name: string;
  render: "css" | "sprite";
  available: boolean;
  spriteUrl?: string;
  unlock: string;
  pixel?: boolean;
  folder?: string;
}

interface CompanionWindow {
  companion: {
    getState: () => Promise<IpcResult<CompanionState>>;
    interact: (type: string, message?: string) => Promise<IpcResult<InteractionResult>>;
    getFeed: (limit?: number) => Promise<IpcResult<FeedItem[]>>;
    createCompanion: (body: object) => Promise<IpcResult<CompanionState>>;
    getSession: () => Promise<CompanionSettings>;
    getSettings: () => Promise<CompanionSettings>;
    setSettings: (patch: object) => Promise<CompanionSettings>;
    setQuizMode: (on: boolean) => Promise<void>;
    setCompact: (on: boolean) => Promise<{ compact: boolean }>;
    setHabitat: (on: boolean) => Promise<{ habitat: boolean }>;
    touchActivity: (kind?: string) => Promise<PresencePayload>;
    getPresence: () => Promise<PresencePayload>;
    getSkins: () => Promise<SkinView[]>;
    getConfig: () => Promise<{ skin?: string; companionId?: string }>;
    notify: (title: string, body: string) => Promise<void>;
    minimize: () => Promise<{ ok: boolean }>;
    setSoundMuted: (on: boolean) => Promise<{ soundMuted: boolean }>;
    resize: (expanded: boolean) => Promise<void>;
    setSkin: (skin: string) => Promise<SkinView | undefined>;
    media: (cmd: "prev" | "toggle" | "next") => Promise<{
      ok: boolean;
      reason?: string;
      presence?: PresencePayload;
    }>;
    onSkinChanged: (cb: (payload: { id: string; skin?: SkinView }) => void) => void;
    onRestartQuiz: (cb: () => void) => void;
    onSessionImported: (cb: () => void) => void;
    onModeChanged: (cb: (mode: {
      compact: boolean;
      soundMuted: boolean;
      pranksEnabled: boolean;
      habitat?: boolean;
      listeningMusic?: boolean;
      notificationsMuted?: boolean;
      nudgeIntervalMin?: number;
      rememberChats?: boolean;
      focusMode?: boolean;
      perceiveApp?: boolean;
      screenVision?: boolean;
    }) => void) => void;
    onSettingsChanged: (cb: (s: CompanionSettings) => void) => void;
    onPlaySound: (cb: (kind: string) => void) => void;
    onPresence: (cb: (payload: PresencePayload) => void) => void;
    onLocalLine: (cb: (text: string) => void) => void;
  };
}

const cw = window as unknown as CompanionWindow;

function $<T extends HTMLElement>(id: string): T {
  return document.getElementById(id) as T;
}

const MOOD_PARTICLES: Record<string, string[]> = {
  EXCITED: ["★", "✨", "⚡"],
  HAPPY: ["♪", "♫", "💚"],
  CONTENT: ["·", "○", "~"],
  BORED: ["…", ".", "−"],
  SLEEPY: ["z", "z", "💤"],
  SAD: ["💧", "·", "💧"],
  LONELY: ["?", "·", "?"],
};

const BAD_FEED = /user\s*says|thinking|analyze|user input|current mood|personality:|energy:|as an ai|fale agora|só a frase|so a frase/i;

const IDLE_MISS: Record<string, string[]> = {
  curioso: ["Sumiu? Eu fiquei inventando teorias.", "Voltou! Conta o que rolou."],
  preguicoso: ["...você demorou. Eu quase dormi.", "Ah, voltou. Sem pressa da próxima."],
  carinhoso: ["Senti sua falta de verdade.", "Finalmente! Fica um pouquinho."],
  zoeiro: ["Sumiu e eu quase aprontei sozinho.", "Olha quem lembrou que eu existo."],
  misterioso: ["O silêncio falou por você.", "Sua ausência deixou rastros."],
};

let isBusy = false;
let pollTimer: ReturnType<typeof setInterval> | null = null;
let retryTimer: ReturnType<typeof setInterval> | null = null;
let connected = false;
let quizStep = 0;
const quizChoices: number[] = [];
let draft: CompanionDraft | null = null;
let companionLabel = "Companion";
let companionArchetype = "curioso";
let lastMood = "HAPPY";
let lastAffection = 0;
let soundMuted = false;
let expanded = false;

function syncMuteButton() {
  document.body.classList.toggle("sound-muted", soundMuted);
}
let isCompact = false;
let isHabitat = false;
let greetingShown = false;
let missShown = false;
let currentActivity = "Presente";
let lastSkyPeriod = "";
let sfxAudio: HTMLAudioElement | null = null;

function dayWeatherStorm(): boolean {
  const d = new Date();
  const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) h = Math.imul(h ^ key.charCodeAt(i), 16777619);
  return (h >>> 0) % 7 === 0;
}

function skyFromTime(tod: string): string {
  if (dayWeatherStorm()) return "storm";
  if (tod === "morning") return "dawn";
  if (tod === "evening") return "evening";
  if (tod === "night") return "night";
  return "day";
}

function applySky(tod?: string) {
  const period = tod || lastSkyPeriod || "afternoon";
  lastSkyPeriod = period;
  document.body.dataset.sky = skyFromTime(period);
  if (activeSkinId) document.body.dataset.skinTint = activeSkinId;
}

function playSfx(name: string) {
  if (soundMuted) return;
  try {
    if (sfxAudio) {
      sfxAudio.pause();
      sfxAudio.currentTime = 0;
    }
    sfxAudio = new Audio(`assets/sfx/${name}.wav`);
    sfxAudio.volume = 0.45;
    void sfxAudio.play();
  } catch {
    /* ignore */
  }
}

function playClipSfx(clip: string) {
  if (clip === "crack") playSfx("rocks");
  else if (clip === "hatch") playSfx("roar");
  else if (clip === "move" || clip === "dash" || clip === "jump") playSfx(`step${1 + Math.floor(Math.random() * 4)}`);
  else if (clip === "bite" || clip === "kick") playSfx("hit");
  else if (clip === "hurt" || clip === "scan") playSfx(clip === "hurt" ? "hit" : "growl");
}

const PLAY_CLIPS = ["jump", "move", "dash", "bite", "kick"] as const;
const PLAY_LINES: Record<string, string[]> = {
  curioso: ["Pega! O que tem atrás da nuvem?", "Corrida de investigação!", "Dash e pergunta depois."],
  preguicoso: ["Ok… um pulo. Só um.", "Corrida? Preferia uma soneca.", "Dash curto. Já cansei."],
  carinhoso: ["Brinca comigo!", "Corre pra cá — eu te espero.", "Pula e me dá colo depois."],
  zoeiro: ["Olha o show!", "Dash dramático ativado.", "Mordida de brincadeira. Relaxa."],
  misterioso: ["Um passo. Sem explicação.", "Dash na sombra.", "O jogo começa sem palavras."],
};

let ambientTimer: ReturnType<typeof setTimeout> | null = null;
let pendingHatch = false;

function clearAmbientTimer() {
  if (ambientTimer) clearTimeout(ambientTimer);
  ambientTimer = null;
}

function scheduleAmbientLife() {
  clearAmbientTimer();
  if (document.body.classList.contains("quiz-open")) return;
  if (!dinoPlayer.running) return;
  const excited = lastMood === "EXCITED";
  const sleepy = lastMood === "SLEEPY";
  if (sleepy) return;
  const delay = (excited ? 6000 : 9000) + Math.floor(Math.random() * (excited ? 4000 : 6000));
  ambientTimer = setTimeout(() => {
    ambientTimer = null;
    if (document.body.classList.contains("quiz-open")) return;
    if (!dinoPlayer.running) return;
    if (dinoPlayer.clip !== "idle" || !dinoPlayer.loop) {
      scheduleAmbientLife();
      return;
    }
    const clip = Math.random() < 0.55 ? "move" : "dash";
    void dinoPlay(clip, false);
    playClipSfx(clip);
    scheduleAmbientLife();
  }, delay);
}

async function showStaticEgg(folder: string) {
  stopDinoLife();
  clearAmbientTimer();
  const canvas = $<HTMLCanvasElement>("dinoCanvas");
  const hCanvas = $<HTMLCanvasElement>("habitatDinoCanvas");
  canvas.hidden = false;
  hCanvas.hidden = false;
  try {
    const img = await loadSheet(`assets/dinos/${folder}/egg/move.png`);
    drawDinoFrame(img, 0);
  } catch {
    /* ignore */
  }
}

function activityText(p: PresencePayload): string {
  if (p.batteryLow) return p.batteryPercent != null ? `Bateria ${p.batteryPercent}%` : "Bateria baixa";
  if (p.trackTitle) return p.trackTitle;
  if (p.activity === "listening_music" || p.listeningMusic) return "Ouvindo música…";
  if (p.activity === "idle") return "Ocioso";
  if (p.activity === "playing") return "Brincando";
  if (p.activity === "chatting") return "Conversando";
  if (p.timeOfDay === "morning") return "Manhã tranquila";
  if (p.timeOfDay === "evening") return "Entardecer";
  if (p.timeOfDay === "night") return "Noite calma";
  return "Presente";
}

function updateParticles(mood: string) {
  const container = $<HTMLDivElement>("moodParticles");
  container.innerHTML = "";
  (MOOD_PARTICLES[mood] ?? []).forEach((p, i) => {
    const el = document.createElement("span");
    el.className = "particle";
    el.textContent = p;
    el.style.left = `${20 + i * 25}px`;
    el.style.top = `${60 - i * 8}px`;
    el.style.animationDelay = `${i * 0.6}s`;
    container.appendChild(el);
  });
}

let activeSkinId = "dino-doux";
let activeSkin: SkinView | null = null;
let companionIdForHatch = "";

type DinoClip = { file: string; fps: number };

const DINO_CLIPS: Record<string, DinoClip> = {
  idle: { file: "base/idle.png", fps: 5 },
  move: { file: "base/move.png", fps: 10 },
  jump: { file: "base/jump.png", fps: 8 },
  dash: { file: "base/dash.png", fps: 12 },
  hurt: { file: "base/hurt.png", fps: 10 },
  kick: { file: "base/kick.png", fps: 10 },
  bite: { file: "base/bite.png", fps: 10 },
  scan: { file: "base/scan.png", fps: 8 },
  avoid: { file: "base/avoid.png", fps: 6 },
  eggMove: { file: "egg/move.png", fps: 6 },
  crack: { file: "egg/crack.png", fps: 7 },
  hatch: { file: "egg/hatch.png", fps: 7 },
};

const sheetCache = new Map<string, HTMLImageElement>();

function dinoFolder(skin: SkinView | null): string | null {
  if (!skin) return null;
  if (skin.folder) return skin.folder;
  if (skin.id.startsWith("dino-")) return skin.id.slice(5);
  return null;
}

function loadSheet(src: string): Promise<HTMLImageElement> {
  const hit = sheetCache.get(src);
  if (hit && hit.complete && hit.naturalWidth) return Promise.resolve(hit);
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      sheetCache.set(src, img);
      resolve(img);
    };
    img.onerror = () => reject(new Error(src));
    img.src = src;
  });
}

interface DinoPlayerState {
  folder: string;
  clip: string;
  frame: number;
  acc: number;
  loop: boolean;
  queue: string[];
  running: boolean;
}

const dinoPlayer: DinoPlayerState = {
  folder: "doux",
  clip: "idle",
  frame: 0,
  acc: 0,
  loop: true,
  queue: [],
  running: false,
};

let lastDinoTs = 0;
let dinoRaf = 0;

function dinoCanvases(): HTMLCanvasElement[] {
  return ["dinoCanvas", "habitatDinoCanvas"]
    .map((id) => document.getElementById(id) as HTMLCanvasElement | null)
    .filter((el): el is HTMLCanvasElement => !!el);
}

function drawDinoFrame(img: HTMLImageElement, frame: number) {
  const fh = img.naturalHeight;
  const fw = fh;
  const frames = Math.max(1, Math.floor(img.naturalWidth / fw));
  const i = ((frame % frames) + frames) % frames;
  for (const canvas of dinoCanvases()) {
    const ctx = canvas.getContext("2d");
    if (!ctx) continue;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const pad = 8;
    const size = canvas.width - pad * 2;
    ctx.drawImage(img, i * fw, 0, fw, fh, pad, pad, size, size);
  }
}

async function dinoPlay(clip: string, loop: boolean, enqueue = false) {
  if (enqueue && dinoPlayer.clip !== "idle") {
    dinoPlayer.queue.push(clip);
    return;
  }
  dinoPlayer.clip = clip;
  dinoPlayer.loop = loop;
  dinoPlayer.frame = 0;
  dinoPlayer.acc = 0;
}

function dinoIdleByMood(_mood: string) {
  return dinoPlay("idle", true);
}

async function dinoTick(ts: number) {
  if (!dinoPlayer.running) return;
  const spec = DINO_CLIPS[dinoPlayer.clip] ?? DINO_CLIPS.idle;
  const src = `assets/dinos/${dinoPlayer.folder}/${spec.file}`;
  let img: HTMLImageElement;
  try {
    img = await loadSheet(src);
  } catch {
    if (dinoPlayer.running) dinoRaf = requestAnimationFrame(dinoTick);
    return;
  }
  if (!dinoPlayer.running) return;
  const dt = lastDinoTs ? (ts - lastDinoTs) / 1000 : 0;
  lastDinoTs = ts;
  const fh = img.naturalHeight || 24;
  const frames = Math.max(1, Math.floor(img.naturalWidth / fh));
  const fps = lastMood === "SLEEPY" && dinoPlayer.clip === "idle" ? 2 : spec.fps;
  dinoPlayer.acc += dt;
  const frameDur = 1 / fps;
  if (dinoPlayer.acc >= frameDur) {
    dinoPlayer.acc = 0;
    dinoPlayer.frame += 1;
    if (dinoPlayer.frame >= frames) {
      if (dinoPlayer.loop) {
        dinoPlayer.frame = 0;
      } else if (dinoPlayer.queue.length) {
        const next = dinoPlayer.queue.shift()!;
        dinoPlayer.clip = next;
        dinoPlayer.loop = next === "idle";
        dinoPlayer.frame = 0;
        playClipSfx(next);
        if (next === "idle" && companionIdForHatch) {
          localStorage.setItem(hatchKey(), "1");
        }
        if (next === "idle") scheduleAmbientLife();
      } else {
        void dinoIdleByMood(lastMood);
        scheduleAmbientLife();
      }
    }
  }
  drawDinoFrame(img, dinoPlayer.frame);
  dinoRaf = requestAnimationFrame(dinoTick);
}

async function startDinoLife(skin: SkinView, hatch: boolean) {
  const folder = dinoFolder(skin);
  if (!folder) return;
  stopDinoLife();
  dinoPlayer.folder = folder;
  dinoPlayer.running = true;
  lastDinoTs = 0;
  dinoPlayer.queue = [];
  dinoPlayer.frame = 0;
  dinoPlayer.acc = 0;
  if (hatch) {
    dinoPlayer.clip = "eggMove";
    dinoPlayer.loop = false;
    dinoPlayer.queue.push("crack", "hatch", "idle");
    playClipSfx("eggMove");
  } else {
    void dinoIdleByMood(lastMood);
  }
  dinoRaf = requestAnimationFrame(dinoTick);
  if (!hatch) scheduleAmbientLife();
}

function stopDinoLife() {
  dinoPlayer.running = false;
  clearAmbientTimer();
  if (dinoRaf) cancelAnimationFrame(dinoRaf);
  dinoRaf = 0;
}

function hatchKey() {
  return `companion-hatched:${companionIdForHatch || activeSkinId}`;
}

function shouldHatch(): boolean {
  if (document.body.classList.contains("quiz-open")) return false;
  if (pendingHatch) return true;
  if (!companionIdForHatch) return false;
  return localStorage.getItem(hatchKey()) !== "1";
}

function applySpriteMode(skin: SkinView | null | undefined) {
  const sprite = $<HTMLDivElement>("sprite");
  const img = $<HTMLImageElement>("spriteImg");
  const pet = $<HTMLDivElement>("habitatPet");
  const petImg = $<HTMLImageElement>("habitatSpriteImg");
  const canvas = $<HTMLCanvasElement>("dinoCanvas");
  const hCanvas = $<HTMLCanvasElement>("habitatDinoCanvas");
  const folder = dinoFolder(skin ?? null);
  const useDino = !!folder;
  const quizOpen = document.body.classList.contains("quiz-open");
  sprite.classList.toggle("sprite-png", useDino);
  pet.classList.toggle("sprite-png", useDino);
  sprite.classList.toggle("sprite-pixel", useDino);
  pet.classList.toggle("sprite-pixel", useDino);
  img.hidden = true;
  petImg.hidden = true;
  canvas.hidden = !useDino;
  hCanvas.hidden = !useDino;
  if (useDino && skin && folder) {
    if (quizOpen) {
      void showStaticEgg(folder);
      return;
    }
    const hatch = shouldHatch();
    if (dinoPlayer.running && dinoPlayer.folder === folder && !hatch) {
      scheduleAmbientLife();
      return;
    }
    void startDinoLife(skin, hatch);
    if (hatch) pendingHatch = false;
  } else {
    stopDinoLife();
  }
}

function applyLook(state: Pick<CompanionState, "skin" | "artStyle" | "backdrop">) {
  const sprite = $<HTMLDivElement>("sprite");
  const skinId = activeSkinId || (state.skin === "default" ? "dino-doux" : state.skin);
  sprite.dataset.skin = skinId;
  $<HTMLDivElement>("habitatPet").dataset.skin = skinId;
  document.body.dataset.style = "pixel";
  document.body.dataset.skinTint = skinId;
  applySpriteMode(activeSkin);
  applySky();
}

function setMediaTrack(text: string) {
  const label = text || "Parado";
  const a = document.getElementById("mediaTrack");
  const b = document.getElementById("habitatMediaTrack");
  if (a) a.textContent = label;
  if (b) b.textContent = label;
}

function applyCompactUi(on: boolean) {
  isCompact = on;
  document.body.classList.toggle("compact", on);
}

function applyHabitatUi(on: boolean) {
  isHabitat = on;
  document.body.classList.toggle("habitat", on);
  const panel = $<HTMLDivElement>("habitatPanel");
  const row = $<HTMLDivElement>("bodyRow");
  panel.hidden = !on;
  row.hidden = on;
  if (on) syncHabitat();
}

function syncHabitat() {
  $<HTMLSpanElement>("habitatName").textContent = companionLabel;
  $<HTMLSpanElement>("habitatPct").textContent = `${Math.round(lastAffection)}%`;
  $<HTMLSpanElement>("habitatMood").textContent = lastMood;
  $<HTMLSpanElement>("habitatActivity").textContent = currentActivity;
  const pet = $<HTMLDivElement>("habitatPet");
  pet.dataset.mood = lastMood;
  const mainSkin = $<HTMLDivElement>("sprite").dataset.skin;
  if (mainSkin) pet.dataset.skin = mainSkin;
}

function setActivityUi(label: string) {
  currentActivity = label;
  const chip = $<HTMLSpanElement>("activityChip");
  chip.textContent = label;
  chip.hidden = !label || isCompact;
  if (isHabitat) $<HTMLSpanElement>("habitatActivity").textContent = label;
}

function applyState(state: CompanionState) {
  companionLabel = state.name;
  if (state.archetype) companionArchetype = state.archetype;
  lastMood = state.mood;
  lastAffection = state.affection;
  if (state.id) companionIdForHatch = state.id;
  $<HTMLSpanElement>("companionName").textContent = state.name;
  const sprite = $<HTMLDivElement>("sprite");
  sprite.dataset.mood = state.mood;
  updateParticles(state.mood);
  applyLook(state);
  const looping = dinoPlayer.loop && dinoPlayer.clip === "idle";
  if (dinoPlayer.running && looping) void dinoIdleByMood(lastMood);
  $<HTMLSpanElement>("moodBadge").textContent = state.moodText ?? state.mood;
  const affection = Math.round(state.affection);
  $<HTMLDivElement>("affectionBar").style.width = `${affection}%`;
  $<HTMLSpanElement>("affectionValue").textContent = `${affection}`;
  const energy = Math.round(state.energy ?? 80);
  $<HTMLDivElement>("energyBar").style.width = `${energy}%`;
  $<HTMLSpanElement>("energyValue").textContent = `${energy}`;
  if (isHabitat) syncHabitat();
  if (state.greeting && !greetingShown) {
    greetingShown = true;
    showSpeech(state.greeting, 5000);
  }
}

function forceBlink() {
  document.querySelectorAll<HTMLElement>(".eyes").forEach((el) => {
    el.classList.remove("blink-now");
    void el.offsetWidth;
    el.classList.add("blink-now");
    setTimeout(() => el.classList.remove("blink-now"), 300);
  });
}

function playReact(type: string) {
  const hatching = ["eggMove", "crack", "hatch"].includes(dinoPlayer.clip);
  if (dinoPlayer.running && !hatching) {
    if (type === "PLAY") {
      const clip = PLAY_CLIPS[Math.floor(Math.random() * PLAY_CLIPS.length)];
      void dinoPlay(clip, false);
      playClipSfx(clip);
      const lines = PLAY_LINES[companionArchetype] ?? PLAY_LINES.curioso;
      showSpeech(lines[Math.floor(Math.random() * lines.length)], 2800);
      scheduleAmbientLife();
      return;
    }
    if (type === "POKE") {
      void dinoPlay("hurt", false);
      playActionSound(type);
      scheduleAmbientLife();
      return;
    }
    if (type === "CHAT") {
      void dinoPlay("scan", false);
      playActionSound(type);
      scheduleAmbientLife();
      return;
    }
    playActionSound(type);
    return;
  }
  const sprite = $<HTMLDivElement>("sprite");
  sprite.classList.remove("reacting", "reacting-play", "reacting-chat", "reacting-poke");
  void sprite.offsetWidth;
  const cls =
    type === "PLAY"
      ? "reacting-play"
      : type === "CHAT"
        ? "reacting-chat"
        : type === "POKE"
          ? "reacting-poke"
          : "reacting";
  sprite.classList.add(cls);
  forceBlink();
  setTimeout(() => sprite.classList.remove(cls), 450);
  playActionSound(type);
}

function playActionSound(type: string) {
  if (type === "PLAY") {
    playSfx(`step${1 + Math.floor(Math.random() * 4)}`);
  } else if (type === "POKE") {
    playSfx("hit");
  } else if (type === "CHAT" || type === "tease") {
    playSfx("growl");
  }
}

function showSpeech(text: string, durationMs = 4000) {
  $<HTMLSpanElement>("speechText").textContent = text;
  $<HTMLDivElement>("speechBubble").hidden = false;
  setTimeout(() => {
    $<HTMLDivElement>("speechBubble").hidden = true;
  }, durationMs);
}

function setLoading(on: boolean) {
  const el = $<HTMLDivElement>("loadingOverlay");
  el.hidden = !on;
  el.style.display = on ? "flex" : "none";
}

function waitForApi(retries = 40): Promise<void> {
  return new Promise((resolve, reject) => {
    const tick = () => {
      if ((window as unknown as CompanionWindow).companion) {
        resolve();
        return;
      }
      if (retries-- <= 0) {
        reject(new Error("Preload não carregou"));
        return;
      }
      setTimeout(tick, 50);
    };
    tick();
  });
}

function showError(msg: string, waiting = false) {
  $<HTMLParagraphElement>("errorMsg").textContent = waiting
    ? "Aguardando backend..."
    : msg;
  $<HTMLDivElement>("errorOverlay").hidden = false;
  $<HTMLButtonElement>("btnRetry").hidden = waiting;
}

function hideError() {
  $<HTMLDivElement>("errorOverlay").hidden = true;
}

function isConnectionError(msg?: string) {
  return !!msg && /ECONNREFUSED|ENOTFOUND|ETIMEDOUT/.test(msg);
}

function stopRetry() {
  if (retryTimer) clearInterval(retryTimer);
  retryTimer = null;
}

function startRetry() {
  if (retryTimer) return;
  retryTimer = setInterval(() => void init({ silent: true }), 3000);
}

function setActionsBusy(on: boolean) {
  isBusy = on;
  document.querySelectorAll<HTMLButtonElement>(".action-btn").forEach((b) => {
    b.disabled = on;
  });
}

function escapeHtml(s: string) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function isBadFeedText(text: string) {
  return !text || BAD_FEED.test(text) || /^User\s*says/i.test(text);
}

function pickMiss(): string {
  const list = IDLE_MISS[companionArchetype] ?? IDLE_MISS.curioso;
  return list[Math.floor(Math.random() * list.length)];
}

function handlePresence(p: PresencePayload) {
  document.body.classList.toggle("theme-light", p.theme === "light");
  document.body.classList.toggle("battery-low", !!p.batteryLow);
  applySky(p.timeOfDay);
  const listening = !!(p.listeningMusic || p.trackTitle || p.activity === "listening_music");
  document.body.classList.toggle("listening", listening);
  if (p.screenHint || p.frontApp) {
    const short =
      (p.screenHint && p.screenHint.slice(0, 40)) ||
      (p.frontApp ? `No ${p.frontApp}` : "");
    if (short) setActivityUi(short);
  } else {
    setActivityUi(activityText(p));
  }
  if (listening) {
    setMediaTrack(p.trackTitle || "Ouvindo com você…");
  } else {
    setMediaTrack("Sem música");
  }
  if (p.missedYou && !missShown) {
    missShown = true;
    showSpeech(pickMiss(), 4500);
    forceBlink();
    setTimeout(() => {
      missShown = false;
    }, 20_000);
  }
}

function applySettingsToForm(settings: CompanionSettings) {
  soundMuted = !!settings.soundMuted;
  syncMuteButton();

  const setCheck = (id: string, on: boolean) => {
    const el = document.getElementById(id) as HTMLInputElement | null;
    if (el) el.checked = on;
  };
  const setSelect = (id: string, value: string | number) => {
    const el = document.getElementById(id) as HTMLSelectElement | null;
    if (el) el.value = String(value);
  };

  setCheck("cfgSoundMuted", !!settings.soundMuted);
  setCheck("cfgNotificationsMuted", !!settings.notificationsMuted);
  setSelect("cfgNudgeInterval", settings.nudgeIntervalMin ?? 15);
  setCheck("cfgFocusMode", !!settings.focusMode);
  setSelect("cfgFocusHours", settings.focusHours ?? 1);
  setCheck("cfgPranks", !!settings.pranksEnabled);
  setCheck("cfgCompact", !!settings.compact);
  setCheck("cfgListeningMusic", !!settings.listeningMusic);
  setCheck("cfgRememberChats", settings.rememberChats !== false);
  setCheck("cfgPerceiveApp", settings.perceiveApp !== false);
  setCheck("cfgWindowTitle", settings.useWindowTitle !== false);
  setCheck("cfgCommentMedia", settings.commentMedia !== false);
  setCheck("cfgScreenVision", !!settings.screenVision);

  const eye = document.getElementById("screenEye") as HTMLElement | null;
  if (eye) eye.hidden = !(settings.perceiveApp !== false);

  document.body.classList.toggle("focus-mode", !!settings.focusMode);

  const streak = settings.streakCount ?? 0;
  const done = settings.missions?.done ?? [];
  const missionsExist = !!settings.missions && (done.length > 0 || !!settings.missions.day);
  const strip = document.getElementById("missionsStrip") as HTMLElement | null;
  if (strip) strip.hidden = !(streak > 0 || missionsExist || done.length > 0);

  const streakEl = document.getElementById("missionsStreak");
  if (streakEl) streakEl.textContent = streak > 0 ? `${streak} dias` : "";

  const list = document.getElementById("missionsList");
  if (list) {
    list.innerHTML = "";
    for (const id of MISSION_IDS) {
      const li = document.createElement("li");
      li.textContent = MISSION_LABELS[id];
      if (done.includes(id)) li.classList.add("done");
      list.appendChild(li);
    }
  }

  const hint = document.getElementById("streakHint");
  if (hint) {
    hint.textContent =
      streak > 0
        ? `Sequência de ${streak} dia${streak === 1 ? "" : "s"}.`
        : "Complete missões para manter a sequência.";
  }

  if (typeof settings.compact === "boolean") applyCompactUi(settings.compact);
  if (typeof settings.habitat === "boolean") applyHabitatUi(settings.habitat);
}

function closeSettingsPanel() {
  const panel = document.getElementById("settingsPanel") as HTMLElement | null;
  if (panel) panel.hidden = true;
}

function toggleSettingsPanel() {
  const panel = $<HTMLDivElement>("settingsPanel");
  const opening = panel.hidden;
  panel.hidden = !opening;
  if (opening) {
    const feed = document.getElementById("feedPanel") as HTMLElement | null;
    if (feed) feed.hidden = true;
  }
}

function bindSettingsPanel() {
  $<HTMLButtonElement>("btnSettings").addEventListener("click", () => {
    toggleSettingsPanel();
  });
  $<HTMLButtonElement>("btnCloseSettings").addEventListener("click", () => {
    closeSettingsPanel();
  });

  const bindCheck = (id: string, key: string) => {
    const el = document.getElementById(id) as HTMLInputElement | null;
    if (!el) return;
    el.addEventListener("change", () => {
      void cw.companion.setSettings({ [key]: el.checked });
    });
  };
  const bindSelect = (id: string, key: string, asNumber = true) => {
    const el = document.getElementById(id) as HTMLSelectElement | null;
    if (!el) return;
    el.addEventListener("change", () => {
      const raw = el.value;
      void cw.companion.setSettings({ [key]: asNumber ? Number(raw) : raw });
    });
  };

  bindCheck("cfgSoundMuted", "soundMuted");
  bindCheck("cfgNotificationsMuted", "notificationsMuted");
  bindSelect("cfgNudgeInterval", "nudgeIntervalMin");
  bindCheck("cfgFocusMode", "focusMode");
  bindSelect("cfgFocusHours", "focusHours");
  bindCheck("cfgPranks", "pranksEnabled");
  bindCheck("cfgCompact", "compact");
  bindCheck("cfgListeningMusic", "listeningMusic");
  bindCheck("cfgRememberChats", "rememberChats");
  bindCheck("cfgPerceiveApp", "perceiveApp");
  bindCheck("cfgWindowTitle", "useWindowTitle");
  bindCheck("cfgCommentMedia", "commentMedia");
  bindCheck("cfgScreenVision", "screenVision");

  $<HTMLButtonElement>("cfgOpenHabitat").addEventListener("click", () => {
    closeSettingsPanel();
    void cw.companion.setHabitat(true);
  });
  $<HTMLButtonElement>("cfgToggleSize").addEventListener("click", () => {
    if (isCompact) {
      void cw.companion.setCompact(false);
      return;
    }
    if (isHabitat) return;
    expanded = !expanded;
    document.body.classList.toggle("expanded", expanded);
    void cw.companion.resize(expanded);
  });
}

async function refreshSettings() {
  try {
    const settings = await cw.companion.getSettings();
    applySettingsToForm(settings);
  } catch {
    /* ignore */
  }
}

async function sendMedia(cmd: "prev" | "toggle" | "next") {
  const result = await cw.companion.media(cmd);
  if (result.presence) handlePresence(result.presence);
  if (!result.ok && result.reason === "no_player") {
    showSpeech("Põe uma música no Spotify ou Music — eu escuto junto.", 4000);
    setMediaTrack("Sem música");
  } else if (!result.ok && result.reason === "no_permission") {
    showSpeech("Me dá Automação: Ajustes → Privacidade → Automação → Companion.", 5500);
  }
}

async function interact(type: string, message?: string) {
  if (isBusy) return;
  setActionsBusy(true);
  void cw.companion.touchActivity(type);
  const result = await cw.companion.interact(type, message);
  if (result.ok && result.data) {
    applyState(result.data.companion);
    playReact(type);
    if (type !== "PLAY") showSpeech(result.data.reaction);
    if (type === "PLAY") setActivityUi("Brincando");
    if (type === "CHAT") setActivityUi("Conversando");
  } else {
    showSpeech("*silêncio*");
  }
  setActionsBusy(false);
}

function startPoll() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(async () => {
    const result = await cw.companion.getState();
    if (result.ok && result.data) {
      connected = true;
      hideError();
      stopRetry();
      applyState(result.data);
    } else if (connected && result.error !== "NO_COMPANION") {
      connected = false;
      showError(result.error ?? "Backend offline", isConnectionError(result.error));
      startRetry();
    }
  }, 60_000);
}

const QUIZ_REV = "personality-v2";

function quizCompleted(): boolean {
  try {
    return localStorage.getItem("companion-quiz-rev") === QUIZ_REV;
  } catch {
    return false;
  }
}

function markQuizCompleted() {
  try {
    localStorage.setItem("companion-quiz-rev", QUIZ_REV);
  } catch {
    /* ignore */
  }
}

function clearHatchFlags() {
  try {
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && k.startsWith("companion-hatched:")) keys.push(k);
    }
    keys.forEach((k) => localStorage.removeItem(k));
  } catch {
    /* ignore */
  }
}

function showQuiz() {
  clearHatchFlags();
  pendingHatch = false;
  stopDinoLife();
  $<HTMLDivElement>("quizOverlay").hidden = false;
  document.body.classList.add("quiz-open");
  setLoading(false);
  hideError();
  applyCompactUi(false);
  applyHabitatUi(false);
  void cw.companion?.setQuizMode?.(true);
  quizStep = 0;
  quizChoices.length = 0;
  draft = null;
  greetingShown = false;
  $<HTMLDivElement>("quizReveal").hidden = true;
  const folder = dinoFolder(activeSkin) ?? "doux";
  void showStaticEgg(folder);
  renderQuizStep();
}

function hideQuiz() {
  $<HTMLDivElement>("quizOverlay").hidden = true;
  document.body.classList.remove("quiz-open");
  void cw.companion?.setQuizMode?.(false);
}

function renderQuizEggs() {
  const el = document.getElementById("quizEggs");
  if (!el) return;
  el.innerHTML = "";
  const filled = quizStep >= QUIZ.length ? QUIZ.length : quizStep;
  for (let i = 0; i < QUIZ.length; i++) {
    const span = document.createElement("span");
    span.className = "quiz-egg" + (i < filled ? " done" : i === quizStep ? " current" : "");
    el.appendChild(span);
  }
}

function renderQuizStep() {
  renderQuizEggs();
  const reveal = $<HTMLDivElement>("quizReveal");
  const optionsEl = $<HTMLDivElement>("quizOptions");
  if (quizStep >= QUIZ.length) {
    draft = deriveCompanion(quizChoices);
    optionsEl.innerHTML = "";
    $<HTMLParagraphElement>("quizProgress").textContent = "Pronto";
    $<HTMLHeadingElement>("quizPrompt").textContent = "Esse é o seu dino";
    reveal.hidden = false;
    $<HTMLParagraphElement>("quizBlurb").textContent = draft.blurb;
    $<HTMLInputElement>("quizName").value = draft.name;
    activeSkinId = draft.skin;
    activeSkin = {
      id: draft.skin,
      name: draft.skin,
      render: "sprite",
      available: true,
      unlock: "starter",
      folder: draft.skin.replace(/^dino-/, ""),
    };
    applyLook({
      skin: draft.skin,
      artStyle: draft.artStyle,
      backdrop: draft.backdrop,
    });
    const folder = draft.skin.replace(/^dino-/, "");
    void showStaticEgg(folder);
    $<HTMLDivElement>("sprite").dataset.mood = "HAPPY";
    return;
  }

  reveal.hidden = true;
  const q = QUIZ[quizStep];
  $<HTMLParagraphElement>("quizProgress").textContent = `${quizStep + 1} / ${QUIZ.length}`;
  $<HTMLHeadingElement>("quizPrompt").textContent = q.prompt;
  optionsEl.innerHTML = "";
  q.options.forEach((opt, idx) => {
    const btn = document.createElement("button");
    btn.className = "quiz-option";
    btn.type = "button";
    btn.textContent = opt.label;
    btn.addEventListener("click", () => {
      quizChoices[quizStep] = idx;
      quizStep += 1;
      renderQuizStep();
    });
    optionsEl.appendChild(btn);
  });
}

async function confirmQuiz() {
  if (!draft) return;
  const name = $<HTMLInputElement>("quizName").value.trim() || draft.name;
  const result = await cw.companion.createCompanion({
    name,
    personality: draft.personality,
    skin: draft.skin,
    artStyle: draft.artStyle,
    backdrop: draft.backdrop,
    archetype: draft.archetype,
  });
  if (!result.ok || !result.data) {
    showError(result.error ?? "Não deu pra criar o companion");
    return;
  }
  hideQuiz();
  markQuizCompleted();
  pendingHatch = true;
  companionIdForHatch = result.data.id;
  applyState(result.data);
  startPoll();
}

async function init(options: { silent?: boolean } = {}) {
  try {
    if (!options.silent) {
      setLoading(true);
      hideError();
    }

    const session = await cw.companion.getSession();
    console.log("[renderer] session", session);
    if (session?.companionId) companionIdForHatch = session.companionId;
    if (session?.soundMuted !== undefined) soundMuted = session.soundMuted;
    syncMuteButton();
    applyCompactUi(!!session?.compact);
    applyHabitatUi(!!session?.habitat);
    applySettingsToForm(session);
    try {
      await refreshSettings();
    } catch {
      /* ignore */
    }
    try {
      const skins = await cw.companion.getSkins();
      const cfg = await cw.companion.getConfig();
      const id = (cfg as { skin?: string })?.skin ?? "dino-doux";
      activeSkinId = id;
      activeSkin = skins.find((s) => s.id === id) ?? skins.find((s) => s.id === "dino-doux") ?? null;
      applySpriteMode(activeSkin);
    } catch {
      /* ignore */
    }

    if (!session?.companionId) {
      showQuiz();
      return;
    }

    const result = await cw.companion.getState();
    if (!result.ok || !result.data) {
      if (result.error === "NO_COMPANION" || String(result.error).includes("404")) {
        showQuiz();
        return;
      }
      connected = false;
      setLoading(false);
      showError(result.error ?? "Falha ao conectar", isConnectionError(result.error));
      startRetry();
      return;
    }

    connected = true;
    stopRetry();
    applyState(result.data);
    setLoading(false);
    hideError();
    const presence = await cw.companion.getPresence();
    handlePresence(presence);
    if (!quizCompleted()) {
      showQuiz();
      return;
    }
    hideQuiz();
    if (!pollTimer) startPoll();
  } catch (err) {
    setLoading(false);
    showError(String(err), isConnectionError(String(err)));
    startRetry();
  }
}

document.addEventListener("DOMContentLoaded", () => {
  applySky();
  showQuiz();
  void waitForApi()
    .then(() => {
      cw.companion.onSkinChanged((payload) => {
        activeSkinId = payload.id;
        activeSkin = payload.skin ?? null;
        $<HTMLDivElement>("sprite").dataset.skin = payload.id;
        $<HTMLDivElement>("habitatPet").dataset.skin = payload.id;
        applySpriteMode(payload.skin);
        applySky();
      });
      cw.companion.onLocalLine((line) => showSpeech(line, 5000));
      cw.companion.onRestartQuiz(() => {
        try {
          localStorage.removeItem("companion-quiz-rev");
        } catch {
          /* ignore */
        }
        showQuiz();
      });
      cw.companion.onSessionImported(() => {
        greetingShown = false;
        void init();
      });
      cw.companion.onModeChanged((mode) => {
        soundMuted = mode.soundMuted;
        syncMuteButton();
        applyCompactUi(mode.compact);
        if (typeof mode.habitat === "boolean") applyHabitatUi(mode.habitat);
        if (mode.listeningMusic) setActivityUi("Ouvindo música…");
        if (typeof mode.focusMode === "boolean") {
          document.body.classList.toggle("focus-mode", mode.focusMode);
        }
        void refreshSettings();
      });
      cw.companion.onSettingsChanged((s) => applySettingsToForm(s));
      cw.companion.onPlaySound((kind) => playActionSound(kind));
      cw.companion.onPresence((p) => handlePresence(p));
      return init();
    })
    .catch((err) => {
      setLoading(false);
      showError(String(err));
    });

  bindSettingsPanel();

  ["btnPlay", "btnPoke"].forEach((id) => {
    const btn = $<HTMLButtonElement>(id);
    btn.addEventListener("click", () => interact(btn.dataset.type!));
  });

  const chatInputArea = $<HTMLDivElement>("chatInputArea");
  const chatInput = $<HTMLInputElement>("chatInput");
  const btnSendChat = $<HTMLButtonElement>("btnSendChat");
  $<HTMLButtonElement>("btnChat").addEventListener("click", () => {
    if (isCompact || isHabitat) return;
    chatInputArea.hidden = !chatInputArea.hidden;
    if (!chatInputArea.hidden) chatInput.focus();
  });
  btnSendChat.addEventListener("click", () => {
    const msg = chatInput.value.trim();
    if (!msg) return;
    chatInput.value = "";
    chatInputArea.hidden = true;
    void interact("CHAT", msg);
  });
  chatInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") btnSendChat.click();
  });

  $<HTMLButtonElement>("btnFeedToggle").addEventListener("click", async () => {
    if (isCompact || isHabitat) return;
    closeSettingsPanel();
    const feedPanel = $<HTMLDivElement>("feedPanel");
    const feedList = $<HTMLUListElement>("feedList");
    feedPanel.hidden = false;
    feedList.innerHTML = `<li style="padding:12px;font-family:var(--font-ui);font-size:11px;color:var(--text-dim)">Carregando...</li>`;
    const result = await cw.companion.getFeed(20);
    feedList.innerHTML = "";
    const items = (result.data ?? []).filter((item) => !isBadFeedText(item.reactionText));
    if (!result.ok || !items.length) {
      feedList.innerHTML = `<li style="padding:12px;font-family:var(--font-ui);font-size:11px;color:var(--text-dim)">Nada ainda</li>`;
      return;
    }
    for (const item of items) {
      const li = document.createElement("li");
      li.className = "feed-item";
      const name = item.companionName || companionLabel;
      const bits: string[] = [];
      if (item.type === "CHAT" && item.userMessage && !isBadFeedText(item.userMessage)) {
        bits.push(
          `<div class="feed-line feed-user"><span class="feed-who">Você:</span> ${escapeHtml(item.userMessage)}</div>`
        );
      }
      bits.push(
        `<div class="feed-line feed-bot"><span class="feed-who">${escapeHtml(name)}:</span> ${escapeHtml(item.reactionText)}</div>`
      );
      if (item.type !== "CHAT") {
        bits.unshift(`<div class="feed-item-type">${escapeHtml(item.type)}</div>`);
      }
      li.innerHTML = bits.join("");
      feedList.appendChild(li);
    }
  });

  $<HTMLButtonElement>("btnCloseFeed").addEventListener("click", () => {
    $<HTMLDivElement>("feedPanel").hidden = true;
  });
  $<HTMLButtonElement>("btnClose").addEventListener("click", () => {
    void cw.companion.minimize();
  });
  $<HTMLButtonElement>("btnMinimize").addEventListener("click", () => {
    void cw.companion.minimize();
  });
  $<HTMLButtonElement>("btnRetry").addEventListener("click", () => {
    stopRetry();
    void init();
  });

  $<HTMLButtonElement>("btnCloseHabitat").addEventListener("click", () => {
    void cw.companion.setHabitat(false);
  });

  $<HTMLDivElement>("sprite").addEventListener("click", () => {
    if (isCompact) {
      void cw.companion.setCompact(false);
      return;
    }
    void cw.companion.setHabitat(true);
  });

  const media = (cmd: "prev" | "toggle" | "next") => () => void sendMedia(cmd);
  $<HTMLButtonElement>("btnMediaPrev").addEventListener("click", media("prev"));
  $<HTMLButtonElement>("btnMediaToggle").addEventListener("click", media("toggle"));
  $<HTMLButtonElement>("btnMediaNext").addEventListener("click", media("next"));
  $<HTMLButtonElement>("btnHabMediaPrev").addEventListener("click", media("prev"));
  $<HTMLButtonElement>("btnHabMediaToggle").addEventListener("click", media("toggle"));
  $<HTMLButtonElement>("btnHabMediaNext").addEventListener("click", media("next"));

  $<HTMLButtonElement>("quizConfirm").addEventListener("click", () => void confirmQuiz());
});
