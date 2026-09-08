import test from "node:test";
import assert from "node:assert/strict";
import {
  AFFECTION_DECAY_PER_HOUR,
  ENERGY_DECAY_PER_HOUR,
  INTERACTION_EFFECTS,
  STEPS_PER_ENERGY,
  LIFE_SLEEP_HOUR_END,
  LIFE_WORK_HOUR_START,
  LIFE_WORK_STEPS_RECENT_MIN,
  PRESENCE_FROM_LIFE_MODE,
} from "../../src/survivalSpec.ts";

test("survivalSpec constants match cloud SQL port", () => {
  assert.equal(AFFECTION_DECAY_PER_HOUR, 2 / 24);
  assert.equal(ENERGY_DECAY_PER_HOUR, 0.5);
  assert.equal(INTERACTION_EFFECTS.FEED.energy, 8);
  assert.equal(INTERACTION_EFFECTS.POKE.affection, 2);
  assert.equal(STEPS_PER_ENERGY, 500);
});

test("life mode thresholds are documented for SQL port", () => {
  assert.equal(LIFE_SLEEP_HOUR_END, 6);
  assert.equal(LIFE_WORK_HOUR_START, 7);
  assert.equal(LIFE_WORK_STEPS_RECENT_MIN, 120);
});

test("presenceStatus mirrors lifeMode (no IoT RSSI)", () => {
  assert.equal(PRESENCE_FROM_LIFE_MODE.indoor, "present");
  assert.equal(PRESENCE_FROM_LIFE_MODE.work, "away");
  assert.equal(PRESENCE_FROM_LIFE_MODE.sleep, "expedition");
});
