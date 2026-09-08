-- Quiz traits (vibe / archetype / focus / communicationStyle) as JSONB.
ALTER TABLE "Companion" ADD COLUMN IF NOT EXISTS "traits" JSONB;
