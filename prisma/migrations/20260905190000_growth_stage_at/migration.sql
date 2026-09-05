-- AlterTable
ALTER TABLE "Companion" ADD COLUMN IF NOT EXISTS "growthStageAt" TIMESTAMP(3);

UPDATE "Companion" SET "growthStageAt" = "createdAt" WHERE "growthStageAt" IS NULL;

ALTER TABLE "Companion" ALTER COLUMN "growthStageAt" SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "Companion" ALTER COLUMN "growthStageAt" SET NOT NULL;
