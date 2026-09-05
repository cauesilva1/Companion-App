/**
 * Espelho de MissionCatalog (Swift) — dayKey, rotação, bump, claim.
 * Manter alinhado com apps/ios/Shared/MissionCatalog.swift
 */

export const ROTATION = [
  [
    { kind: "POKE_COUNT", title: "Cutucadas", description: "Cutuca o dino 3 vezes", target: 3, e: 6, a: 4 },
    { kind: "FEED_COUNT", title: "Lanche", description: "Alimente 2 vezes", target: 2, e: 10, a: 3 },
    { kind: "PLAY_COUNT", title: "Brincadeira", description: "Brinque 1 vez", target: 1, e: 8, a: 6 },
  ],
  [
    { kind: "CHAT_COUNT", title: "Conversa", description: "Mande 1 mensagem", target: 1, e: 5, a: 8 },
    { kind: "TEASE_COUNT", title: "Piadinha", description: "Mande 1 piada", target: 1, e: 7, a: 7 },
    { kind: "OPEN_APP", title: "Visita", description: "Abra o app 2 vezes hoje", target: 2, e: 4, a: 5 },
  ],
  [
    { kind: "POKE_COUNT", title: "Carinho", description: "Cutuca 5 vezes", target: 5, e: 8, a: 5 },
    { kind: "FEED_COUNT", title: "Banquete", description: "Alimente 3 vezes", target: 3, e: 12, a: 4 },
    { kind: "TEASE_COUNT", title: "Zoeira", description: "2 piadas no dia", target: 2, e: 9, a: 9 },
  ],
];

/** dayKey local YYYY-MM-DD (espelha Calendar.current). */
export function dayKey(date = new Date(), timeZone = "America/Sao_Paulo") {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const y = parts.find((p) => p.type === "year").value;
  const m = parts.find((p) => p.type === "month").value;
  const d = parts.find((p) => p.type === "day").value;
  return `${y}-${m}-${d}`;
}

export function rotationIndex(key) {
  const n = key.split("-").map(Number).reduce((a, b) => a + b, 0);
  return n % ROTATION.length;
}

export function missionsForDay(key) {
  const defs = ROTATION[rotationIndex(key)];
  return defs.map((d) => ({
    id: `local-${key}-${d.kind}`,
    kind: d.kind,
    title: d.title,
    description: d.description,
    target: d.target,
    progress: 0,
    rewardEnergy: d.e,
    rewardAffection: d.a,
    claimed: false,
  }));
}

/** Store em memória para testes (substitui UserDefaults). */
export function createMissionStore(initialDayKey, initialMissions) {
  let box =
    initialDayKey && initialMissions
      ? { dayKey: initialDayKey, missions: structuredClone(initialMissions) }
      : null;

  function ensureToday(nowKey) {
    if (box && box.dayKey === nowKey) return structuredClone(box.missions);
    const missions = missionsForDay(nowKey);
    box = { dayKey: nowKey, missions: structuredClone(missions) };
    return structuredClone(missions);
  }

  function bump(kind, amount = 1, nowKey = dayKey()) {
    let missions = ensureToday(nowKey);
    const idx = missions.findIndex((m) => m.kind === kind);
    if (idx < 0) return missions;
    if (missions[idx].claimed) return missions;
    missions[idx].progress = Math.min(missions[idx].target, missions[idx].progress + amount);
    box = { dayKey: nowKey, missions: structuredClone(missions) };
    return missions;
  }

  function claim(idOrKind, nowKey = dayKey()) {
    let missions = ensureToday(nowKey);
    let idx = missions.findIndex((m) => m.id === idOrKind);
    if (idx < 0) idx = missions.findIndex((m) => m.kind === idOrKind);
    if (idx < 0) idx = missions.findIndex((m) => idOrKind.includes(m.kind));
    if (idx < 0) return null;
    const m = missions[idx];
    if (m.claimed || m.progress < m.target) return null;
    missions[idx].claimed = true;
    box = { dayKey: nowKey, missions: structuredClone(missions) };
    return { missions, rewardEnergy: m.rewardEnergy, rewardAffection: m.rewardAffection };
  }

  /** Merge cloud: max progress por kind, nunca zerar se local tem progresso. */
  function mergeSync(local, remote) {
    return local.map((m) => {
      const hit = remote.find((r) => r.kind === m.kind);
      return {
        ...m,
        id: hit?.id ?? m.id,
        progress: Math.max(m.progress, hit?.progress ?? 0),
        claimed: m.claimed || (hit?.claimed ?? false),
      };
    });
  }

  return {
    get box() {
      return box ? structuredClone(box) : null;
    },
    ensureToday,
    bump,
    claim,
    mergeSync,
  };
}

export function kindFromInteraction(type) {
  switch (String(type).toUpperCase()) {
    case "POKE":
      return "POKE_COUNT";
    case "FEED":
      return "FEED_COUNT";
    case "PLAY":
      return "PLAY_COUNT";
    case "CHAT":
      return "CHAT_COUNT";
    case "TEASE":
      return "TEASE_COUNT";
    default:
      return null;
  }
}
