-- Wipe app data (public schema) — sem tabelas IoT (removidas)
TRUNCATE TABLE
  "CompanionThought",
  "Interaction",
  "Companion",
  "UserMissionProgress",
  "StepsLedger",
  "Profile"
RESTART IDENTITY CASCADE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'User'
  ) THEN
    EXECUTE 'TRUNCATE TABLE "User" RESTART IDENTITY CASCADE';
  END IF;
END $$;
