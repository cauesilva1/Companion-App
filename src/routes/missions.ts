import { Router } from "express";
import { prisma } from "../db";
import { AuthedRequest, requireAuth } from "../auth";
import { bumpMission, ensureTodayMissions } from "../missions";

export const missionsRouter = Router();

missionsRouter.use(requireAuth);

missionsRouter.get("/today", async (req: AuthedRequest, res) => {
  const userId = req.auth!.userId;
  const rows = await ensureTodayMissions(userId);
  return res.json({
    dayKey: rows[0]?.dayKey,
    missions: rows.map((m) => ({
      id: m.id,
      kind: m.kind,
      title: m.title,
      description: m.description,
      target: m.target,
      progress: m.progress,
      rewardEnergy: m.rewardEnergy,
      rewardAffection: m.rewardAffection,
      claimed: m.claimed,
      complete: m.progress >= m.target,
    })),
  });
});

missionsRouter.post("/:id/claim", async (req: AuthedRequest, res) => {
  const userId = req.auth!.userId;
  const mission = await prisma.userMissionProgress.findFirst({
    where: { id: req.params.id, userId },
  });
  if (!mission) return res.status(404).json({ error: "mission_not_found" });
  if (mission.claimed) return res.status(400).json({ error: "already_claimed" });
  if (mission.progress < mission.target) return res.status(400).json({ error: "incomplete" });

  const companion = await prisma.companion.findFirst({ where: { userId } });
  if (!companion) return res.status(404).json({ error: "no_companion" });

  const [updatedMission, updatedCompanion] = await prisma.$transaction([
    prisma.userMissionProgress.update({
      where: { id: mission.id },
      data: { claimed: true },
    }),
    prisma.companion.update({
      where: { id: companion.id },
      data: {
        energy: Math.min(100, companion.energy + mission.rewardEnergy),
        affection: Math.min(100, companion.affection + mission.rewardAffection),
      },
    }),
  ]);

  return res.json({
    mission: updatedMission,
    companion: {
      id: updatedCompanion.id,
      energy: updatedCompanion.energy,
      affection: updatedCompanion.affection,
    },
  });
});

missionsRouter.post("/open-app", async (req: AuthedRequest, res) => {
  const row = await bumpMission(req.auth!.userId, "OPEN_APP", 1);
  return res.json({ ok: true, progress: row?.progress ?? 0 });
});
