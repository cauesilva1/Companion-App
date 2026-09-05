import dotenv from "dotenv";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import cors from "cors";

if (process.env.DOTENV_CONFIG_PATH) {
  dotenv.config({ path: process.env.DOTENV_CONFIG_PATH });
} else {
  dotenv.config();
}

const app = express();
app.use(cors());
app.use(express.json({ limit: "32kb" }));

const hitBuckets = new Map<string, number[]>();
function rateLimit(max: number, windowMs: number) {
  return (req: Request, res: Response, next: NextFunction) => {
    const key = `${req.ip || "local"}:${req.path}`;
    const now = Date.now();
    const windowStart = now - windowMs;
    const recent = (hitBuckets.get(key) || []).filter((t) => t > windowStart);
    if (recent.length >= max) {
      res.status(429).json({ error: "too_many_requests" });
      return;
    }
    recent.push(now);
    hitBuckets.set(key, recent);
    next();
  };
}

app.get("/health", (_req, res) =>
  res.json({
    ok: true,
    mode: process.env.DATABASE_URL ? "postgres" : "mock",
  })
);

const limitInteract = rateLimit(40, 60_000);
app.use((req, res, next) => {
  if (req.method === "POST" && /\/interact\/?$/.test(req.path)) {
    return limitInteract(req, res, next);
  }
  next();
});

const useMock = process.env.EXPRESS_LEGACY !== "1";

if (useMock) {
  if (process.env.SUPABASE_URL) {
    console.warn(
      "ℹ️  Sync cloud = clientes → Supabase direto. Express em mock local."
    );
  } else {
    console.warn("⚠️  Express mock (JSON). Sync iPhone↔PC = Supabase Auth nos clients.");
  }
  const { mockRouter, tickMockCompanions } = require("./routes/mockCompanion");
  app.use("/companion", mockRouter);
  setInterval(() => tickMockCompanions(), 5 * 60 * 1000);
} else {
  // Legacy Express+JWT (EXPRESS_LEGACY=1) — schema antigo
  const { authRouter } = require("./routes/auth");
  const { companionRouter } = require("./routes/companion");
  const { missionsRouter } = require("./routes/missions");
  const { prisma } = require("./db");
  const { applyTimeDecay } = require("./moodEngine");

  app.use("/auth", authRouter);
  app.use("/companion", companionRouter);
  app.use("/missions", missionsRouter);

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
const HOST = process.env.HOST || "127.0.0.1";
app.listen(PORT, HOST, () => {
  console.log(`Companion engine em http://${HOST}:${PORT} (${useMock ? "mock" : "postgres"})`);
});
