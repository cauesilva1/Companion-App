import test from "node:test";
import assert from "node:assert/strict";
import {
  isMoodBurst,
  isOffTopic,
  isMusicTopic,
  isFalseEvolution,
  acceptReply,
} from "./speechFilters.mjs";

test("isMoodBurst rejeita Uhul / foguete / alegria curta", () => {
  assert.equal(isMoodBurst("Uhul!"), true);
  assert.equal(isMoodBurst("Uhuul!"), true);
  assert.equal(isMoodBurst("Tô no modo foguete!"), true);
  assert.equal(isMoodBurst("Que alegria!"), true);
  assert.equal(isMoodBurst(""), true);
});

test("isMoodBurst aceita fala com conteúdo", () => {
  assert.equal(isMoodBurst("Tô feliz, mas quero saber do tempo"), false);
  assert.equal(isMoodBurst("Design é difícil mesmo, sem pressa"), false);
});

test("isOffTopic: design do user vs reply de rap/música", () => {
  const user =
    "fiz bastante coisa para melhorar voce, mas nao sou bom em design entao nao consigo criar evolucoes para vc";
  const bad =
    "Uhul! Que alegria! Acho que foi só uma expressão espontânea de entusiasmo, né? Mas fico feliz em saber que você curtiu a sugestão do rap! Quer algo mais pra ouvir?";
  assert.equal(isMusicTopic(user), false);
  assert.equal(isOffTopic(bad, user), true);
  assert.equal(acceptReply(bad, user, { growthEnabled: false }), false);
});

test("isOffTopic: música OK se user falou de música", () => {
  assert.equal(isOffTopic("Essa faixa é foda", "o que acha dessa música?"), false);
  assert.equal(acceptReply("Essa faixa é foda", "o que acha dessa música?"), true);
});

test("isFalseEvolution com growth OFF", () => {
  assert.equal(isFalseEvolution("Mas você já evoluiu, viu? É assim, cresce sozinho!", false), true);
  assert.equal(isFalseEvolution("Tô aqui, evolui, só falta teu toque mágico!", false), true);
  assert.equal(isFalseEvolution("Design é difícil, sem pressa com a arte", false), false);
  assert.equal(isFalseEvolution("Você já evoluiu!", true), false);
});

test("caso do print: rejeita reply falsa de evolução", () => {
  const user = "MAs eu n fiz nada quase";
  const reply = "Mas você já evoluiu, viu? É assim, cresce sozinho! 🌱✨";
  assert.equal(acceptReply(reply, user, { growthEnabled: false }), false);
});
