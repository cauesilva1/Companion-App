-- Cloud-First survival + IoT presence / expedition freeze

CREATE TYPE "PresenceStatus" AS ENUM ('present', 'away', 'expedition');

ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "presenceStatus" "PresenceStatus" NOT NULL DEFAULT 'present',
  ADD COLUMN IF NOT EXISTS "lastPresenceAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS "presenceRssi" INTEGER,
  ADD COLUMN IF NOT EXISTS "decayFrozen" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "Companion_decayFrozen_idx" ON "Companion"("decayFrozen");

CREATE TABLE IF NOT EXISTS "IotDevice" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "deviceKeyHash" TEXT NOT NULL,
  "label" TEXT NOT NULL DEFAULT 'mesa',
  "lastSeenAt" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IotDevice_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "IotDevice_userId_idx" ON "IotDevice"("userId");
CREATE INDEX IF NOT EXISTS "IotDevice_deviceKeyHash_idx" ON "IotDevice"("deviceKeyHash");

CREATE TABLE IF NOT EXISTS "IotPresenceEvent" (
  "id" TEXT NOT NULL,
  "deviceId" TEXT NOT NULL,
  "rssi" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IotPresenceEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "IotPresenceEvent_deviceId_createdAt_idx"
  ON "IotPresenceEvent"("deviceId", "createdAt");

CREATE TABLE IF NOT EXISTS "IotInteractEvent" (
  "id" TEXT NOT NULL,
  "deviceId" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IotInteractEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "IotInteractEvent_deviceId_createdAt_idx"
  ON "IotInteractEvent"("deviceId", "createdAt");

ALTER TABLE "IotPresenceEvent"
  DROP CONSTRAINT IF EXISTS "IotPresenceEvent_deviceId_fkey";
ALTER TABLE "IotPresenceEvent"
  ADD CONSTRAINT "IotPresenceEvent_deviceId_fkey"
  FOREIGN KEY ("deviceId") REFERENCES "IotDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "IotInteractEvent"
  DROP CONSTRAINT IF EXISTS "IotInteractEvent_deviceId_fkey";
ALTER TABLE "IotInteractEvent"
  ADD CONSTRAINT "IotInteractEvent_deviceId_fkey"
  FOREIGN KEY ("deviceId") REFERENCES "IotDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE IF NOT EXISTS "StepsLedger" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "dayKey" TEXT NOT NULL,
  "steps" INTEGER NOT NULL DEFAULT 0,
  "energyGranted" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StepsLedger_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StepsLedger_userId_dayKey_key"
  ON "StepsLedger"("userId", "dayKey");
CREATE INDEX IF NOT EXISTS "StepsLedger_userId_idx" ON "StepsLedger"("userId");

-- RLS IoT / steps (users read own; writes via service role / SECURITY DEFINER)
ALTER TABLE "IotDevice" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "IotPresenceEvent" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "IotInteractEvent" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "StepsLedger" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS iot_device_select ON "IotDevice";
CREATE POLICY iot_device_select ON "IotDevice"
  FOR SELECT USING ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS iot_presence_select ON "IotPresenceEvent";
CREATE POLICY iot_presence_select ON "IotPresenceEvent"
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM "IotDevice" d
      WHERE d.id = "IotPresenceEvent"."deviceId" AND d."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS iot_interact_select ON "IotInteractEvent";
CREATE POLICY iot_interact_select ON "IotInteractEvent"
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM "IotDevice" d
      WHERE d.id = "IotInteractEvent"."deviceId" AND d."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS steps_select ON "StepsLedger";
CREATE POLICY steps_select ON "StepsLedger"
  FOR SELECT USING ("userId" = auth.uid()::text);

GRANT SELECT ON "IotDevice" TO authenticated, anon;
GRANT SELECT ON "IotPresenceEvent" TO authenticated, anon;
GRANT SELECT ON "IotInteractEvent" TO authenticated, anon;
GRANT SELECT ON "StepsLedger" TO authenticated, anon;

-- Protect survival columns from client PATCH (Edge/service_role or RPC flag may write)
CREATE OR REPLACE FUNCTION companion_protect_survival()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('companion.allow_survival_write', true) = 'on' THEN
    RETURN NEW;
  END IF;
  IF coalesce(auth.role(), '') = 'service_role' THEN
    RETURN NEW;
  END IF;
  NEW.energy := OLD.energy;
  NEW.affection := OLD.affection;
  NEW.mood := OLD.mood;
  NEW."lastDecayAt" := OLD."lastDecayAt";
  NEW."presenceStatus" := OLD."presenceStatus";
  NEW."lastPresenceAt" := OLD."lastPresenceAt";
  NEW."presenceRssi" := OLD."presenceRssi";
  NEW."decayFrozen" := OLD."decayFrozen";
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companion_protect_survival ON "Companion";
CREATE TRIGGER trg_companion_protect_survival
  BEFORE UPDATE ON "Companion"
  FOR EACH ROW
  EXECUTE FUNCTION companion_protect_survival();

-- Mood / decay helpers (spec: src/survivalSpec.ts)
CREATE OR REPLACE FUNCTION companion_compute_mood(
  p_affection double precision,
  p_energy double precision,
  p_days_since double precision
) RETURNS "Mood"
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_days_since > 3 THEN RETURN 'LONELY'::"Mood"; END IF;
  IF p_energy < 18 THEN RETURN 'SLEEPY'::"Mood"; END IF;
  IF p_affection < 18 THEN RETURN 'SAD'::"Mood"; END IF;
  IF p_affection < 32 THEN RETURN 'BORED'::"Mood"; END IF;
  IF p_affection > 75 AND p_energy > 40 THEN RETURN 'EXCITED'::"Mood"; END IF;
  IF p_affection > 42 THEN RETURN 'HAPPY'::"Mood"; END IF;
  RETURN 'CONTENT'::"Mood";
END;
$$;

CREATE OR REPLACE FUNCTION companion_apply_decay(p_companion_id text, p_now timestamptz DEFAULT now())
RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  hours_since double precision;
  hours_idle double precision;
  new_aff double precision;
  new_en double precision;
  new_mood "Mood";
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'companion not found';
  END IF;
  IF coalesce(auth.role(), '') <> 'service_role'
     AND c."userId" IS DISTINCT FROM coalesce(auth.uid()::text, '') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF c."decayFrozen" OR c."presenceStatus" IN ('away'::"PresenceStatus", 'expedition'::"PresenceStatus") THEN
    RETURN c;
  END IF;

  hours_since := EXTRACT(EPOCH FROM (p_now - c."lastInteractionAt")) / 3600.0;
  hours_idle := GREATEST(0, hours_since - 1.0);
  new_aff := GREATEST(0, LEAST(100, c.affection - hours_idle * (2.0 / 24.0)));
  new_en := GREATEST(0, LEAST(100, c.energy - hours_idle * 0.5));
  new_mood := companion_compute_mood(new_aff, new_en, hours_since / 24.0);

  UPDATE "Companion" SET
    energy = ROUND(new_en)::int,
    affection = ROUND(new_aff)::int,
    mood = new_mood,
    "lastDecayAt" = p_now
  WHERE id = c.id
  RETURNING * INTO c;
  RETURN c;
END;
$$;

CREATE OR REPLACE FUNCTION companion_apply_interaction(
  p_companion_id text,
  p_type "InteractionType",
  p_message text DEFAULT NULL,
  p_reaction text DEFAULT '…'
)
RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  fx_aff int;
  fx_en int;
  new_aff int;
  new_en int;
  new_mood "Mood";
  now_ts timestamptz := now();
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  c := companion_apply_decay(p_companion_id, now_ts);

  fx_aff := CASE p_type
    WHEN 'POKE' THEN 2 WHEN 'FEED' THEN 0 WHEN 'PLAY' THEN 6
    WHEN 'CHAT' THEN 4 WHEN 'TEASE' THEN 5 WHEN 'IGNORE_CHECK' THEN -4
    ELSE 0 END;
  fx_en := CASE p_type
    WHEN 'POKE' THEN -1 WHEN 'FEED' THEN 8 WHEN 'PLAY' THEN -4
    WHEN 'CHAT' THEN -2 WHEN 'TEASE' THEN -2 WHEN 'IGNORE_CHECK' THEN -2
    ELSE 0 END;

  new_aff := GREATEST(0, LEAST(100, c.affection + fx_aff));
  new_en := GREATEST(0, LEAST(100, c.energy + fx_en));
  new_mood := companion_compute_mood(new_aff, new_en, 0);

  UPDATE "Companion" SET
    energy = new_en,
    affection = new_aff,
    mood = new_mood,
    "lastDecayAt" = now_ts,
    "lastInteractionAt" = now_ts,
    "pendingAlert" = NULL
  WHERE id = c.id
  RETURNING * INTO c;

  INSERT INTO "Interaction" (
    id, "companionId", type, "userMessage", "reactionText",
    "moodAfter", "energyAfter", "affectionAfter", "createdAt"
  ) VALUES (
    'act_' || substr(md5(random()::text || clock_timestamp()::text), 1, 16),
    c.id, p_type, p_message, coalesce(p_reaction, '…'),
    new_mood, new_en, new_aff, now_ts
  );

  RETURN c;
END;
$$;

CREATE OR REPLACE FUNCTION companion_set_presence(
  p_user_id text,
  p_status "PresenceStatus",
  p_rssi int DEFAULT NULL
)
RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  frozen boolean;
  cid text;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT id INTO cid FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF cid IS NULL THEN
    RAISE EXCEPTION 'companion not found for user';
  END IF;
  frozen := p_status IN ('away'::"PresenceStatus", 'expedition'::"PresenceStatus");
  UPDATE "Companion" SET
    "presenceStatus" = p_status,
    "lastPresenceAt" = CASE
      WHEN p_status = 'present'::"PresenceStatus" THEN now()
      ELSE "lastPresenceAt"
    END,
    "presenceRssi" = coalesce(p_rssi, "presenceRssi"),
    "decayFrozen" = frozen
  WHERE id = cid
  RETURNING * INTO c;
  RETURN c;
END;
$$;

CREATE OR REPLACE FUNCTION companion_tick_all()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  n int := 0;
  timeout_min int := 15;
BEGIN
  -- Auto-expedition when presence went stale while still marked present
  UPDATE "Companion" SET
    "presenceStatus" = 'expedition'::"PresenceStatus",
    "decayFrozen" = true
  WHERE "presenceStatus" = 'present'::"PresenceStatus"
    AND "lastPresenceAt" < now() - make_interval(mins => timeout_min)
    AND EXISTS (SELECT 1 FROM "IotDevice" d WHERE d."userId" = "Companion"."userId" AND d."revokedAt" IS NULL);

  FOR r IN
    SELECT id FROM "Companion" WHERE NOT "decayFrozen"
  LOOP
    PERFORM companion_apply_decay(r.id, now());
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION missions_day_key(p_tz text DEFAULT 'America/Sao_Paulo')
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT to_char(timezone(p_tz, now()), 'YYYY-MM-DD');
$$;

CREATE OR REPLACE FUNCTION missions_ensure_today(p_user_id text, p_tz text DEFAULT 'America/Sao_Paulo')
RETURNS SETOF "UserMissionProgress"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  key text := missions_day_key(p_tz);
  n int;
  rot int;
BEGIN
  SELECT count(*) INTO n FROM "UserMissionProgress" WHERE "userId" = p_user_id AND "dayKey" = key;
  IF n > 0 THEN
    RETURN QUERY SELECT * FROM "UserMissionProgress" WHERE "userId" = p_user_id AND "dayKey" = key;
    RETURN;
  END IF;

  rot := (
    coalesce((split_part(key, '-', 1))::int, 0)
    + coalesce((split_part(key, '-', 2))::int, 0)
    + coalesce((split_part(key, '-', 3))::int, 0)
  ) % 3;

  IF rot = 0 THEN
    INSERT INTO "UserMissionProgress" (id, "userId", "dayKey", kind, title, description, target, "rewardEnergy", "rewardAffection")
    VALUES
      ('msn_' || key || '_poke_' || substr(p_user_id, 1, 8), p_user_id, key, 'POKE_COUNT', 'Cutucadas', 'Cutuca o dino 3 vezes', 3, 6, 4),
      ('msn_' || key || '_feed_' || substr(p_user_id, 1, 8), p_user_id, key, 'FEED_COUNT', 'Lanche', 'Alimente 2 vezes', 2, 10, 3),
      ('msn_' || key || '_play_' || substr(p_user_id, 1, 8), p_user_id, key, 'PLAY_COUNT', 'Brincadeira', 'Brinque 1 vez', 1, 8, 6);
  ELSIF rot = 1 THEN
    INSERT INTO "UserMissionProgress" (id, "userId", "dayKey", kind, title, description, target, "rewardEnergy", "rewardAffection")
    VALUES
      ('msn_' || key || '_chat_' || substr(p_user_id, 1, 8), p_user_id, key, 'CHAT_COUNT', 'Conversa', 'Mande 1 mensagem', 1, 5, 8),
      ('msn_' || key || '_tease_' || substr(p_user_id, 1, 8), p_user_id, key, 'TEASE_COUNT', 'Piadinha', 'Mande 1 piada', 1, 7, 7),
      ('msn_' || key || '_open_' || substr(p_user_id, 1, 8), p_user_id, key, 'OPEN_APP', 'Visita', 'Abra o app 2 vezes hoje', 2, 4, 5);
  ELSE
    INSERT INTO "UserMissionProgress" (id, "userId", "dayKey", kind, title, description, target, "rewardEnergy", "rewardAffection")
    VALUES
      ('msn_' || key || '_poke_' || substr(p_user_id, 1, 8), p_user_id, key, 'POKE_COUNT', 'Carinho', 'Cutuca 5 vezes', 5, 8, 5),
      ('msn_' || key || '_feed_' || substr(p_user_id, 1, 8), p_user_id, key, 'FEED_COUNT', 'Banquete', 'Alimente 3 vezes', 3, 12, 4),
      ('msn_' || key || '_tease_' || substr(p_user_id, 1, 8), p_user_id, key, 'TEASE_COUNT', 'Zoeira', '2 piadas no dia', 2, 9, 9);
  END IF;

  RETURN QUERY SELECT * FROM "UserMissionProgress" WHERE "userId" = p_user_id AND "dayKey" = key;
END;
$$;

CREATE OR REPLACE FUNCTION missions_claim(p_mission_id text, p_user_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m "UserMissionProgress"%ROWTYPE;
  c "Companion"%ROWTYPE;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO m FROM "UserMissionProgress" WHERE id = p_mission_id AND "userId" = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission not found'; END IF;
  IF m.claimed THEN RAISE EXCEPTION 'already claimed'; END IF;
  IF m.progress < m.target THEN RAISE EXCEPTION 'not complete'; END IF;

  UPDATE "UserMissionProgress" SET claimed = true WHERE id = m.id RETURNING * INTO m;
  UPDATE "Companion" SET
    energy = LEAST(100, energy + m."rewardEnergy"),
    affection = LEAST(100, affection + m."rewardAffection")
  WHERE "userId" = p_user_id
  RETURNING * INTO c;

  RETURN json_build_object(
    'mission', row_to_json(m),
    'energy', c.energy,
    'affection', c.affection,
    'rewardEnergy', m."rewardEnergy",
    'rewardAffection', m."rewardAffection"
  );
END;
$$;

CREATE OR REPLACE FUNCTION steps_ingest(p_user_id text, p_day_key text, p_steps int)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ledger "StepsLedger"%ROWTYPE;
  steps_per int := 500;
  cap int := 24;
  should_grant int;
  delta int;
  c "Companion"%ROWTYPE;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  INSERT INTO "StepsLedger" (id, "userId", "dayKey", steps, "energyGranted", "updatedAt")
  VALUES (
    'stp_' || p_day_key || '_' || substr(p_user_id, 1, 8),
    p_user_id, p_day_key, GREATEST(0, p_steps), 0, now()
  )
  ON CONFLICT ("userId", "dayKey") DO UPDATE SET
    steps = GREATEST("StepsLedger".steps, EXCLUDED.steps),
    "updatedAt" = now()
  RETURNING * INTO ledger;

  should_grant := LEAST(cap, (ledger.steps / steps_per));
  delta := GREATEST(0, should_grant - ledger."energyGranted");
  IF delta > 0 THEN
    UPDATE "StepsLedger" SET "energyGranted" = ledger."energyGranted" + delta WHERE id = ledger.id
    RETURNING * INTO ledger;
    UPDATE "Companion" SET
      energy = LEAST(100, energy + delta),
      "lastInteractionAt" = now()
    WHERE "userId" = p_user_id
    RETURNING * INTO c;
  ELSE
    SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id LIMIT 1;
  END IF;

  RETURN json_build_object(
    'steps', ledger.steps,
    'energyGranted', ledger."energyGranted",
    'energyDelta', delta,
    'energy', coalesce(c.energy, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION companion_apply_decay(text, timestamptz) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_apply_interaction(text, "InteractionType", text, text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_set_presence(text, "PresenceStatus", int) TO service_role;
GRANT EXECUTE ON FUNCTION companion_tick_all() TO service_role;
GRANT EXECUTE ON FUNCTION missions_ensure_today(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION missions_claim(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION steps_ingest(text, text, int) TO authenticated, service_role;

-- Optional pg_cron (Supabase Pro). Safe no-op if extension missing.
-- Prefer Edge Function `tick-decay` scheduled in Dashboard if this fails.
DO $cronsetup$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
  PERFORM cron.schedule(
    'companion-tick-decay',
    '*/10 * * * *',
    'SELECT companion_tick_all()'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available — schedule Edge Function tick-decay instead: %', SQLERRM;
END;
$cronsetup$;
