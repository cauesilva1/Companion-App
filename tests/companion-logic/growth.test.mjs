import test from "node:test";
import assert from "node:assert/strict";
import {
  effective,
  scale,
  wordLimit,
  shouldEvolve,
  evolveClip,
} from "./growth.mjs";

test("growth OFF → sempre baby / scale 1 / sem evolve", () => {
  assert.equal(effective("teen", false), "baby");
  assert.equal(effective("adult", false), "baby");
  assert.equal(scale("adult", false), 1);
  assert.equal(wordLimit("adult", false), 10);
  assert.equal(
    shouldEvolve({
      stage: "baby",
      stageStartedAt: new Date(0),
      affection: 100,
      isEnabled: false,
    }),
    null
  );
  assert.equal(evolveClip("baby", "teen", false), null);
});

test("growth ON → effective e evolve possíveis", () => {
  assert.equal(effective("teen", true), "teen");
  assert.equal(scale("adult", true), 1.14);
  assert.equal(wordLimit("adult", true), 22);
  assert.equal(
    shouldEvolve({
      stage: "baby",
      stageStartedAt: new Date(0),
      affection: 100,
      isEnabled: true,
    }),
    "teen"
  );
  assert.equal(evolveClip("baby", "teen", true), "evolveBabyTeen");
});
