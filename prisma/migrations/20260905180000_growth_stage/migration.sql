-- AlterTable
ALTER TABLE "Companion" ADD COLUMN IF NOT EXISTS "growthStage" TEXT NOT NULL DEFAULT 'baby';
