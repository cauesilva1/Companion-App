import dotenv from "dotenv";
import express from "express";
import cors from "cors";

if (process.env.DOTENV_CONFIG_PATH) {
  dotenv.config({ path: process.env.DOTENV_CONFIG_PATH });
} else {
  dotenv.config();
}

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => res.json({ ok: true }));

const useMock = !process.env.DATABASE_URL;

if (useMock) {
  console.warn("⚠️  DATABASE_URL não definida — persistência em data/companions.json (modo mock).");
  console.warn("   Sem companion salvo: o Electron abre o quiz. POST /companion cria um novo.");
  const { mockRouter, tickMockCompanions } = require("./routes/mockCompanion");
  app.use("/companion", mockRouter);
  setInterval(() => {
    tickMockCompanions();
  }, 5 * 60 * 1000);
} else {
  const { companionRouter } = require("./routes/companion");
  const { prisma } = require("./db");
  const { applyTimeDecay } = require("./moodEngine");
  app.use("/companion", companionRouter);
  setInterval(async () => {
    const now = new Date();
    const companions = await prisma.companion.findMany();
    for (const companion of companions) {
      const decayed = applyTimeDecay(companion, now);
      await prisma.companion.update({
        where: { id: companion.id },
        data: {
          energy: decayed.energy,
          affection: decayed.affection,
          mood: decayed.mood,
          lastDecayAt: now,
        },
      });
    }
  }, 5 * 60 * 1000);
}

const PORT = process.env.PORT ? Number(process.env.PORT) : 3333;
app.listen(PORT, () => {
  console.log(`Companion engine rodando em http://127.0.0.1:${PORT}`);
});
