import test from "node:test";
import assert from "node:assert/strict";
import {
  dayKey,
  missionsForDay,
  rotationIndex,
  createMissionStore,
  kindFromInteraction,
} from "./missionDay.mjs";

test("dayKey local America/Sao_Paulo", () => {
  // 2026-09-06 02:00 UTC = ainda 05/09 em SP (UTC-3/-4)
  const late = new Date("2026-09-06T02:00:00.000Z");
  const keySP = dayKey(late, "America/Sao_Paulo");
  const keyUTC = late.toISOString().slice(0, 10);
  assert.equal(keySP, "2026-09-05");
  assert.notEqual(keySP, keyUTC);
});

test("mesmo dayKey → mesmo set de kinds", () => {
  const key = "2026-09-05";
  const a = missionsForDay(key);
  const b = missionsForDay(key);
  assert.deepEqual(
    a.map((m) => m.kind),
    b.map((m) => m.kind)
  );
  assert.equal(a.length, 3);
  assert.equal(rotationIndex(key), (2026 + 9 + 5) % 3);
});

test("virada de dia reseta progress e muda ids", () => {
  const store = createMissionStore("2026-09-04", missionsForDay("2026-09-04"));
  store.bump("POKE_COUNT", 2, "2026-09-04");
  assert.equal(store.box.missions.find((m) => m.kind === "POKE_COUNT").progress, 2);

  const next = store.ensureToday("2026-09-05");
  assert.equal(store.box.dayKey, "2026-09-05");
  assert.ok(next.every((m) => m.progress === 0));
  assert.ok(next[0].id.includes("2026-09-05"));
});

test("bump clamp + claim por kind; claimed não sobe", () => {
  const key = "2026-09-05";
  const store = createMissionStore(key, missionsForDay(key));
  const kinds = store.box.missions.map((m) => m.kind);
  const kind = kinds.includes("CHAT_COUNT") ? "CHAT_COUNT" : kinds[0];
  const target = store.box.missions.find((m) => m.kind === kind).target;

  store.bump(kind, 99, key);
  const m = store.box.missions.find((x) => x.kind === kind);
  assert.equal(m.progress, target);

  const claimed = store.claim(kind, key);
  assert.ok(claimed);
  assert.equal(claimed.missions.find((x) => x.kind === kind).claimed, true);

  store.bump(kind, 1, key);
  assert.equal(store.box.missions.find((x) => x.kind === kind).progress, target);
});

test("mergeSync preserva max progress", () => {
  const key = "2026-09-05";
  const store = createMissionStore(key, missionsForDay(key));
  const local = store.bump(store.box.missions[0].kind, 2, key);
  const remote = local.map((m, i) =>
    i === 0 ? { ...m, id: "msn_remote", progress: 1, claimed: false } : { ...m, id: "msn_" + i }
  );
  const merged = store.mergeSync(local, remote);
  assert.equal(merged[0].progress, 2);
  assert.equal(merged[0].id, "msn_remote");
});

test("kindFromInteraction", () => {
  assert.equal(kindFromInteraction("POKE"), "POKE_COUNT");
  assert.equal(kindFromInteraction("CHAT"), "CHAT_COUNT");
  assert.equal(kindFromInteraction("OPEN"), null);
});
