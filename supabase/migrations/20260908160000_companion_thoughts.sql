-- Cloud-authoritative passive thought feed

CREATE TABLE IF NOT EXISTS "CompanionThought" (
  "id" TEXT PRIMARY KEY,
  "companionId" TEXT NOT NULL REFERENCES "Companion"("id") ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "kind" TEXT NOT NULL DEFAULT 'mood',
  "zoneName" TEXT,
  "lifeMode" TEXT,
  "mediaHint" TEXT,
  "gamingStatus" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS "CompanionThought_userId_createdAt_idx"
  ON "CompanionThought"("userId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "CompanionThought_companionId_createdAt_idx"
  ON "CompanionThought"("companionId", "createdAt" DESC);

ALTER TABLE "CompanionThought" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS thought_select ON "CompanionThought";
CREATE POLICY thought_select ON "CompanionThought"
  FOR SELECT USING ("userId" = auth.uid()::text);

GRANT SELECT ON "CompanionThought" TO authenticated, anon;

-- Append thought (service_role / Edge)
CREATE OR REPLACE FUNCTION companion_append_thought(
  p_user_id text,
  p_text text,
  p_kind text DEFAULT 'mood',
  p_zone_name text DEFAULT NULL
) RETURNS "CompanionThought"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
  t "CompanionThought";
  tid text;
  body text;
BEGIN
  body := left(trim(COALESCE(p_text, '')), 280);
  IF length(body) = 0 THEN
    RAISE EXCEPTION 'empty_thought';
  END IF;

  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  tid := 'th_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);

  INSERT INTO "CompanionThought" (
    "id", "companionId", "userId", "text", "kind", "zoneName",
    "lifeMode", "mediaHint", "gamingStatus", "createdAt"
  ) VALUES (
    tid,
    c.id,
    p_user_id,
    body,
    COALESCE(NULLIF(trim(p_kind), ''), 'mood'),
    NULLIF(trim(COALESCE(p_zone_name, '')), ''),
    c."lifeMode"::text,
    c."mediaHint",
    c."gamingStatus",
    now()
  )
  RETURNING * INTO t;

  -- Cap: keep last 120 thoughts per companion
  DELETE FROM "CompanionThought"
  WHERE "companionId" = c.id
    AND "id" NOT IN (
      SELECT "id" FROM "CompanionThought"
      WHERE "companionId" = c.id
      ORDER BY "createdAt" DESC
      LIMIT 120
    );

  RETURN t;
END;
$$;

REVOKE ALL ON FUNCTION companion_append_thought(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_append_thought(text, text, text, text) TO service_role;

CREATE OR REPLACE FUNCTION companion_list_thoughts(
  p_user_id text,
  p_limit int DEFAULT 40
) RETURNS SETOF "CompanionThought"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM "CompanionThought"
  WHERE "userId" = p_user_id
  ORDER BY "createdAt" ASC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 120));
END;
$$;

REVOKE ALL ON FUNCTION companion_list_thoughts(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_list_thoughts(text, int) TO service_role;

-- When morning thought is seeded in ingest, also persist as a feed row (idempotent per day+kind)
CREATE OR REPLACE FUNCTION companion_seed_morning_thought_row(
  p_user_id text,
  p_text text,
  p_day_key text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
  exists_already boolean;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT EXISTS (
    SELECT 1 FROM "CompanionThought"
    WHERE "companionId" = c.id
      AND "kind" = 'morning'
      AND "createdAt"::date = p_day_key::date
  ) INTO exists_already;

  IF NOT exists_already AND length(trim(COALESCE(p_text, ''))) > 0 THEN
    PERFORM companion_append_thought(p_user_id, p_text, 'morning', NULL);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION companion_seed_morning_thought_row(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_seed_morning_thought_row(text, text, text) TO service_role;

-- Patch ingest to seed morning into CompanionThought when morning text is set
-- (redefine companion_ingest_context with seed call — keep wifi-unknown logic)
CREATE OR REPLACE FUNCTION companion_ingest_context(
  p_user_id text,
  p_on_home_wifi boolean DEFAULT NULL,
  p_ssid text DEFAULT NULL,
  p_steps_today int DEFAULT 0,
  p_steps_recent int DEFAULT 0,
  p_is_charging boolean DEFAULT false,
  p_local_hour int DEFAULT NULL,
  p_media_active boolean DEFAULT false,
  p_media_hint text DEFAULT NULL,
  p_gaming_status text DEFAULT NULL,
  p_now timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
  hour_local int;
  on_home boolean;
  new_mode "LifeMode";
  old_mode "LifeMode";
  new_presence "PresenceStatus";
  day_key text;
  morning text;
  frozen boolean;
  ctx jsonb;
  prev_media text;
  prev_gaming text;
  seeded_morning boolean := false;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  prev_media := c."mediaHint";
  prev_gaming := c."gamingStatus";

  hour_local := COALESCE(
    p_local_hour,
    EXTRACT(HOUR FROM (p_now AT TIME ZONE 'America/Sao_Paulo'))::int
  );

  IF p_on_home_wifi IS NOT NULL THEN
    on_home := p_on_home_wifi;
  ELSIF c."homeWifiSsid" IS NOT NULL AND p_ssid IS NOT NULL AND length(trim(p_ssid)) > 0 THEN
    on_home := lower(trim(c."homeWifiSsid")) = lower(trim(p_ssid));
  ELSE
    on_home := NULL;
  END IF;

  old_mode := c."lifeMode";

  IF hour_local >= 0 AND hour_local < 6
     AND COALESCE(p_steps_recent, 0) < 80
     AND (COALESCE(p_is_charging, false) OR COALESCE(p_steps_recent, 0) < 20) THEN
    new_mode := 'sleep'::"LifeMode";
  ELSIF on_home IS FALSE
        AND hour_local >= 7 AND hour_local < 18
        AND COALESCE(p_steps_recent, 0) >= 120 THEN
    new_mode := 'work'::"LifeMode";
  ELSIF on_home IS FALSE AND hour_local >= 7 AND hour_local < 19 THEN
    new_mode := 'work'::"LifeMode";
  ELSE
    new_mode := 'indoor'::"LifeMode";
  END IF;

  new_presence := CASE new_mode
    WHEN 'work'::"LifeMode" THEN 'away'::"PresenceStatus"
    WHEN 'sleep'::"LifeMode" THEN 'expedition'::"PresenceStatus"
    ELSE 'present'::"PresenceStatus"
  END;

  frozen := (new_mode = 'sleep'::"LifeMode");

  day_key := to_char((p_now AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  morning := c."morningThought";

  IF new_mode = 'sleep'::"LifeMode" AND (
    c."morningThoughtDayKey" IS NULL OR c."morningThoughtDayKey" <> day_key
  ) THEN
    morning := format(
      'Bom dia — %s guardou silêncio na madrugada. Energia %s%%, afeto %s%%.',
      c.name,
      c.energy::text,
      c.affection::text
    );
    seeded_morning := true;
  END IF;

  IF old_mode = 'sleep'::"LifeMode" AND new_mode <> 'sleep'::"LifeMode" THEN
    IF morning IS NULL OR c."morningThoughtDayKey" IS DISTINCT FROM day_key THEN
      morning := format(
        'Bom dia! %s acordou pensando em você (modo %s).',
        c.name,
        new_mode::text
      );
      seeded_morning := true;
    END IF;
  END IF;

  ctx := jsonb_build_object(
    'onHomeWifi', on_home,
    'ssid', p_ssid,
    'ssidUnknown', (p_ssid IS NULL OR length(trim(COALESCE(p_ssid, ''))) = 0),
    'stepsToday', COALESCE(p_steps_today, 0),
    'stepsRecent', COALESCE(p_steps_recent, 0),
    'isCharging', COALESCE(p_is_charging, false),
    'localHour', hour_local,
    'mediaActive', COALESCE(p_media_active, false),
    'computedAt', p_now
  );

  PERFORM set_config('companion.allow_survival_write', 'on', true);

  UPDATE "Companion" SET
    "lifeMode" = new_mode,
    "lifeModeAt" = CASE WHEN new_mode IS DISTINCT FROM old_mode THEN p_now ELSE "lifeModeAt" END,
    "presenceStatus" = new_presence,
    "lastPresenceAt" = CASE
      WHEN new_presence = 'present'::"PresenceStatus" THEN p_now
      ELSE "lastPresenceAt"
    END,
    "decayFrozen" = frozen,
    "mediaHint" = CASE
      WHEN p_media_hint IS NOT NULL AND length(trim(p_media_hint)) > 0 THEN left(trim(p_media_hint), 160)
      WHEN COALESCE(p_media_active, false) THEN "mediaHint"
      ELSE NULL
    END,
    "gamingStatus" = CASE
      WHEN p_gaming_status IS NOT NULL THEN left(trim(p_gaming_status), 160)
      ELSE "gamingStatus"
    END,
    "morningThought" = morning,
    "morningThoughtDayKey" = CASE WHEN morning IS NOT NULL THEN day_key ELSE "morningThoughtDayKey" END,
    "contextJson" = ctx,
    "lastContextAt" = p_now
  WHERE id = c.id
  RETURNING * INTO c;

  IF seeded_morning AND morning IS NOT NULL THEN
    PERFORM companion_seed_morning_thought_row(p_user_id, morning, day_key);
  END IF;

  -- Auto-thoughts when media / xbox status changes (indoor-focused)
  IF c."mediaHint" IS DISTINCT FROM prev_media
     AND c."mediaHint" IS NOT NULL
     AND length(c."mediaHint") > 0 THEN
    PERFORM companion_append_thought(
      p_user_id,
      format('Som na sala: %s', c."mediaHint"),
      'music',
      NULL
    );
  END IF;

  IF c."gamingStatus" IS DISTINCT FROM prev_gaming
     AND c."gamingStatus" IS NOT NULL
     AND length(c."gamingStatus") > 0
     AND c."lifeMode" = 'indoor'::"LifeMode" THEN
    PERFORM companion_append_thought(
      p_user_id,
      format('Xbox: %s', c."gamingStatus"),
      'gaming',
      NULL
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'companionId', c.id,
    'lifeMode', c."lifeMode",
    'lifeModeChanged', new_mode IS DISTINCT FROM old_mode,
    'decayFrozen', c."decayFrozen",
    'morningThought', c."morningThought",
    'mediaHint', c."mediaHint",
    'gamingStatus', c."gamingStatus",
    'energy', c.energy,
    'affection', c.affection,
    'mood', c.mood,
    'presenceStatus', c."presenceStatus",
    'onHomeWifi', on_home
  );
END;
$$;

-- Safe Xbox status write for Edge companion-state
CREATE OR REPLACE FUNCTION companion_set_gaming_status(
  p_user_id text,
  p_gaming_status text
) RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'no_companion'; END IF;
  UPDATE "Companion"
  SET "gamingStatus" = left(trim(p_gaming_status), 160)
  WHERE id = c.id
  RETURNING * INTO c;
  RETURN c;
END;
$$;

REVOKE ALL ON FUNCTION companion_set_gaming_status(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_set_gaming_status(text, text) TO service_role;
