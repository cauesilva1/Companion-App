-- CreateEnum
CREATE TYPE "Mood" AS ENUM ('EXCITED', 'HAPPY', 'CONTENT', 'BORED', 'SLEEPY', 'SAD', 'LONELY');

-- CreateEnum
CREATE TYPE "InteractionType" AS ENUM ('POKE', 'FEED', 'CHAT', 'PLAY', 'TEASE', 'IGNORE_CHECK');

-- CreateEnum
CREATE TYPE "MissionKind" AS ENUM ('POKE_COUNT', 'FEED_COUNT', 'PLAY_COUNT', 'CHAT_COUNT', 'TEASE_COUNT', 'OPEN_APP');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Companion" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "personality" TEXT NOT NULL,
    "skin" TEXT NOT NULL DEFAULT 'dino-mort',
    "artStyle" TEXT NOT NULL DEFAULT 'pixel',
    "backdrop" TEXT NOT NULL DEFAULT 'sky',
    "archetype" TEXT NOT NULL DEFAULT 'curioso',
    "mood" "Mood" NOT NULL DEFAULT 'CONTENT',
    "energy" INTEGER NOT NULL DEFAULT 80,
    "affection" INTEGER NOT NULL DEFAULT 55,
    "lastDecayAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastInteractionAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "pendingAlert" TEXT,
    "memoryNotes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Companion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Interaction" (
    "id" TEXT NOT NULL,
    "companionId" TEXT NOT NULL,
    "type" "InteractionType" NOT NULL,
    "userMessage" TEXT,
    "reactionText" TEXT NOT NULL,
    "moodAfter" "Mood" NOT NULL,
    "energyAfter" INTEGER NOT NULL,
    "affectionAfter" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Interaction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserMissionProgress" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "dayKey" TEXT NOT NULL,
    "kind" "MissionKind" NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "target" INTEGER NOT NULL,
    "progress" INTEGER NOT NULL DEFAULT 0,
    "rewardEnergy" INTEGER NOT NULL DEFAULT 8,
    "rewardAffection" INTEGER NOT NULL DEFAULT 5,
    "claimed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserMissionProgress_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "Companion_userId_idx" ON "Companion"("userId");

-- CreateIndex
CREATE INDEX "Interaction_companionId_createdAt_idx" ON "Interaction"("companionId", "createdAt");

-- CreateIndex
CREATE INDEX "UserMissionProgress_userId_dayKey_idx" ON "UserMissionProgress"("userId", "dayKey");

-- CreateIndex
CREATE UNIQUE INDEX "UserMissionProgress_userId_dayKey_kind_key" ON "UserMissionProgress"("userId", "dayKey", "kind");

-- AddForeignKey
ALTER TABLE "Companion" ADD CONSTRAINT "Companion_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Interaction" ADD CONSTRAINT "Interaction_companionId_fkey" FOREIGN KEY ("companionId") REFERENCES "Companion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserMissionProgress" ADD CONSTRAINT "UserMissionProgress_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
