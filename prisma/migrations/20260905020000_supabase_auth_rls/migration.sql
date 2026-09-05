-- Sync direto via Supabase Auth + RLS (sem JWT Express).
-- Drop legacy app User (passwordHash) and re-key companions/missions to auth.uid().

-- Clear cloud rows (breaking change: old Express JWT users are incompatible)
TRUNCATE TABLE "Interaction" CASCADE;
TRUNCATE TABLE "UserMissionProgress" CASCADE;
TRUNCATE TABLE "Companion" CASCADE;
TRUNCATE TABLE "User" CASCADE;

-- Drop FK to public.User
ALTER TABLE "Companion" DROP CONSTRAINT IF EXISTS "Companion_userId_fkey";
ALTER TABLE "UserMissionProgress" DROP CONSTRAINT IF EXISTS "UserMissionProgress_userId_fkey";

DROP TABLE IF EXISTS "User";

-- userId becomes auth.users id (uuid as text for PostgREST simplicity)
ALTER TABLE "Companion" ALTER COLUMN "userId" TYPE TEXT USING "userId"::text;
ALTER TABLE "UserMissionProgress" ALTER COLUMN "userId" TYPE TEXT USING "userId"::text;

-- Optional profile mirror (email for display); id = auth.uid()
CREATE TABLE IF NOT EXISTS "Profile" (
  "id" TEXT PRIMARY KEY,
  "email" TEXT NOT NULL UNIQUE,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- RLS
ALTER TABLE "Companion" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Interaction" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "UserMissionProgress" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Profile" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS companion_select ON "Companion";
DROP POLICY IF EXISTS companion_insert ON "Companion";
DROP POLICY IF EXISTS companion_update ON "Companion";
DROP POLICY IF EXISTS companion_delete ON "Companion";

CREATE POLICY companion_select ON "Companion"
  FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY companion_insert ON "Companion"
  FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY companion_update ON "Companion"
  FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY companion_delete ON "Companion"
  FOR DELETE USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS mission_select ON "UserMissionProgress";
DROP POLICY IF EXISTS mission_insert ON "UserMissionProgress";
DROP POLICY IF EXISTS mission_update ON "UserMissionProgress";
DROP POLICY IF EXISTS mission_delete ON "UserMissionProgress";

CREATE POLICY mission_select ON "UserMissionProgress"
  FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY mission_insert ON "UserMissionProgress"
  FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY mission_update ON "UserMissionProgress"
  FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY mission_delete ON "UserMissionProgress"
  FOR DELETE USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS interaction_select ON "Interaction";
DROP POLICY IF EXISTS interaction_insert ON "Interaction";
DROP POLICY IF EXISTS interaction_update ON "Interaction";
DROP POLICY IF EXISTS interaction_delete ON "Interaction";

CREATE POLICY interaction_select ON "Interaction"
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM "Companion" c
      WHERE c.id = "Interaction"."companionId" AND c."userId" = auth.uid()::text
    )
  );
CREATE POLICY interaction_insert ON "Interaction"
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM "Companion" c
      WHERE c.id = "Interaction"."companionId" AND c."userId" = auth.uid()::text
    )
  );
CREATE POLICY interaction_update ON "Interaction"
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM "Companion" c
      WHERE c.id = "Interaction"."companionId" AND c."userId" = auth.uid()::text
    )
  );
CREATE POLICY interaction_delete ON "Interaction"
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM "Companion" c
      WHERE c.id = "Interaction"."companionId" AND c."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS profile_select ON "Profile";
DROP POLICY IF EXISTS profile_insert ON "Profile";
DROP POLICY IF EXISTS profile_update ON "Profile";

CREATE POLICY profile_select ON "Profile"
  FOR SELECT USING ("id" = auth.uid()::text);
CREATE POLICY profile_insert ON "Profile"
  FOR INSERT WITH CHECK ("id" = auth.uid()::text);
CREATE POLICY profile_update ON "Profile"
  FOR UPDATE USING ("id" = auth.uid()::text);

-- Grant API roles
GRANT SELECT, INSERT, UPDATE, DELETE ON "Companion" TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Interaction" TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON "UserMissionProgress" TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Profile" TO authenticated, anon;
