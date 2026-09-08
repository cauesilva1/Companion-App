-- Full wipe for clean slate (dev reset).
-- Order matters because of FKs.

TRUNCATE TABLE
  "IotPresenceEvent",
  "IotInteractEvent",
  "Interaction",
  "Companion",
  "UserMissionProgress",
  "StepsLedger",
  "IotDevice",
  "Profile"
RESTART IDENTITY CASCADE;

-- Legacy Express users (if table still exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'User'
  ) THEN
    EXECUTE 'TRUNCATE TABLE "User" RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- Auth users + sessions (Supabase Auth) — contas sumen; pode criar email de novo.
TRUNCATE TABLE
  auth.refresh_tokens,
  auth.sessions,
  auth.mfa_amr_claims,
  auth.mfa_challenges,
  auth.mfa_factors,
  auth.identities,
  auth.users
RESTART IDENTITY CASCADE;
