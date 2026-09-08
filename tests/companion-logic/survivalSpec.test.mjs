import test from "node:test";
import assert from "node:assert/strict";
import {
  AFFECTION_DECAY_PER_HOUR,
  ENERGY_DECAY_PER_HOUR,
  INTERACTION_EFFECTS,
  IOT_RSSI_PRESENT_THRESHOLD,
  STEPS_PER_ENERGY,
} from "../../src/survivalSpec.ts";

test("survivalSpec constants match cloud SQL port", () => {
  assert.equal(AFFECTION_DECAY_PER_HOUR, 2 / 24);
  assert.equal(ENERGY_DECAY_PER_HOUR, 0.5);
  assert.equal(INTERACTION_EFFECTS.FEED.energy, 8);
  assert.equal(INTERACTION_EFFECTS.POKE.affection, 2);
  assert.equal(IOT_RSSI_PRESENT_THRESHOLD, -75);
  assert.equal(STEPS_PER_ENERGY, 500);
});
