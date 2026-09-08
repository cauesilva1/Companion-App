-- Drop ESP32 / RSSI IoT path. Presence is driven by LifeMode via context-ingest.

-- 1) Decay: only decayFrozen freezes (not presenceStatus away/expedition alone)
CREATE OR REPLACE FUNCTION companion_apply_decay(
  p_companion_id text,
  p_now timestamptz DEFAULT now()
) RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  hours double precision;
  grace double precision := 1.0;
  aff_per_h double precision := 2.0 / 24.0;
  en_per_h double precision := 0.5;
  days_since double precision;
  new_aff double precision;
  new_en double precision;
  new_mood "Mood";
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'companion not found';
  END IF;

  -- LifeMode sleep (e qualquer freeze explícito). PresenceStatus é só espelho semântico.
  IF c."decayFrozen" THEN
    RETURN c;
  END IF;

  hours := EXTRACT(EPOCH FROM (p_now - c."lastDecayAt")) / 3600.0;
  IF hours <= grace THEN
    RETURN c;
  END IF;
  hours := hours - grace;

  new_aff := GREATEST(0, LEAST(100, c.affection - hours * aff_per_h));
  new_en := GREATEST(0, LEAST(100, c.energy - hours * en_per_h));
  days_since := EXTRACT(EPOCH FROM (p_now - c."lastInteractionAt")) / 86400.0;
  new_mood := companion_compute_mood(new_aff, new_en, days_since);

  UPDATE "Companion" SET
    affection = ROUND(new_aff)::int,
    energy = ROUND(new_en)::int,
    mood = new_mood,
    "lastDecayAt" = p_now
  WHERE id = c.id
  RETURNING * INTO c;

  RETURN c;
END;
$$;

-- 2) Tick: sem auto-expedition por IotDevice / lastPresenceAt
CREATE OR REPLACE FUNCTION companion_tick_all()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT id FROM "Companion" WHERE NOT "decayFrozen"
  LOOP
    PERFORM companion_apply_decay(r.id, now());
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- 3) context-ingest: presenceStatus espelha lifeMode; freeze só no sleep
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
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  hour_local := COALESCE(
    p_local_hour,
    EXTRACT(HOUR FROM (p_now AT TIME ZONE 'America/Sao_Paulo'))::int
  );

  on_home := COALESCE(
    p_on_home_wifi,
    CASE
      WHEN c."homeWifiSsid" IS NOT NULL AND p_ssid IS NOT NULL
        AND lower(trim(c."homeWifiSsid")) = lower(trim(p_ssid)) THEN true
      ELSE false
    END
  );

  old_mode := c."lifeMode";

  IF hour_local >= 0 AND hour_local < 6
     AND COALESCE(p_steps_recent, 0) < 80
     AND (COALESCE(p_is_charging, false) OR COALESCE(p_steps_recent, 0) < 20) THEN
    new_mode := 'sleep'::"LifeMode";
  ELSIF NOT on_home
        AND hour_local >= 7 AND hour_local < 18
        AND COALESCE(p_steps_recent, 0) >= 120 THEN
    new_mode := 'work'::"LifeMode";
  ELSIF NOT on_home AND hour_local >= 7 AND hour_local < 19 THEN
    new_mode := 'work'::"LifeMode";
  ELSE
    new_mode := 'indoor'::"LifeMode";
  END IF;

  -- Presence espelha life mode (sem RSSI / ESP32)
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
  END IF;

  IF old_mode = 'sleep'::"LifeMode" AND new_mode <> 'sleep'::"LifeMode" THEN
    IF morning IS NULL OR c."morningThoughtDayKey" IS DISTINCT FROM day_key THEN
      morning := format(
        'Bom dia! %s acordou pensando em você (modo %s).',
        c.name,
        new_mode::text
      );
    END IF;
  END IF;

  ctx := jsonb_build_object(
    'onHomeWifi', on_home,
    'ssid', p_ssid,
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
    "presenceRssi" = NULL,
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
    'presenceStatus', c."presenceStatus"
  );
END;
$$;

-- 4) Drop legacy IoT presence RPC (ESP32)
DROP FUNCTION IF EXISTS companion_set_presence(text, "PresenceStatus", int);

-- 5) Drop IoT tables
DROP TABLE IF EXISTS "IotInteractEvent" CASCADE;
DROP TABLE IF EXISTS "IotPresenceEvent" CASCADE;
DROP TABLE IF EXISTS "IotDevice" CASCADE;

-- 6) Drop unused RSSI column
ALTER TABLE "Companion" DROP COLUMN IF EXISTS "presenceRssi";

-- 7) Protect trigger without presenceRssi
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
  NEW."decayFrozen" := OLD."decayFrozen";
  NEW."lifeMode" := OLD."lifeMode";
  NEW."lifeModeAt" := OLD."lifeModeAt";
  NEW."gamingStatus" := OLD."gamingStatus";
  NEW."mediaHint" := OLD."mediaHint";
  NEW."morningThought" := OLD."morningThought";
  NEW."morningThoughtDayKey" := OLD."morningThoughtDayKey";
  NEW."contextJson" := OLD."contextJson";
  NEW."lastContextAt" := OLD."lastContextAt";
  RETURN NEW;
END;
$$;
