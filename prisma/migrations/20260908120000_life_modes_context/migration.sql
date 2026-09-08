-- Life modes (work / indoor / sleep) + external context for LLM
-- Orthogonal to IoT PresenceStatus (desk), but sleep freezes decay like expedition.

DO $$ BEGIN
  CREATE TYPE "LifeMode" AS ENUM ('work', 'indoor', 'sleep');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "lifeMode" "LifeMode" NOT NULL DEFAULT 'indoor',
  ADD COLUMN IF NOT EXISTS "lifeModeAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS "homeWifiSsid" TEXT,
  ADD COLUMN IF NOT EXISTS "xboxGamertag" TEXT,
  ADD COLUMN IF NOT EXISTS "gamingStatus" TEXT,
  ADD COLUMN IF NOT EXISTS "mediaHint" TEXT,
  ADD COLUMN IF NOT EXISTS "morningThought" TEXT,
  ADD COLUMN IF NOT EXISTS "morningThoughtDayKey" TEXT,
  ADD COLUMN IF NOT EXISTS "contextJson" JSONB,
  ADD COLUMN IF NOT EXISTS "lastContextAt" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "Companion_lifeMode_idx" ON "Companion"("lifeMode");

-- Extend survival protect: lifeMode / gaming / morning are server-written
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

-- Settings the user may write (home SSID / Xbox tag)
CREATE OR REPLACE FUNCTION companion_set_home_context(
  p_user_id text,
  p_home_wifi_ssid text DEFAULT NULL,
  p_xbox_gamertag text DEFAULT NULL
) RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  UPDATE "Companion" SET
    "homeWifiSsid" = COALESCE(NULLIF(trim(p_home_wifi_ssid), ''), "homeWifiSsid"),
    "xboxGamertag" = COALESCE(NULLIF(trim(p_xbox_gamertag), ''), "xboxGamertag")
  WHERE id = c.id
  RETURNING * INTO c;

  RETURN c;
END;
$$;

REVOKE ALL ON FUNCTION companion_set_home_context(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_set_home_context(text, text, text) TO service_role;

-- Core: ingest phone telemetry → recompute lifeMode + optionally freeze decay
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

  -- 1) Sleep / expedition night: madrugada + pouca movimentação + (carregando ou parado)
  IF hour_local >= 0 AND hour_local < 6
     AND COALESCE(p_steps_recent, 0) < 80
     AND (COALESCE(p_is_charging, false) OR COALESCE(p_steps_recent, 0) < 20) THEN
    new_mode := 'sleep'::"LifeMode";
  -- 2) Work / field: fora do Wi‑Fi casa em horário comercial + passos
  ELSIF NOT on_home
        AND hour_local >= 7 AND hour_local < 18
        AND COALESCE(p_steps_recent, 0) >= 120 THEN
    new_mode := 'work'::"LifeMode";
  ELSIF NOT on_home AND hour_local >= 7 AND hour_local < 19 THEN
    new_mode := 'work'::"LifeMode";
  -- 3) Indoor / lazer: em casa (ou noite cedo no sofá)
  ELSE
    new_mode := 'indoor'::"LifeMode";
  END IF;

  day_key := to_char((p_now AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  morning := c."morningThought";

  -- Entering sleep: seed morning thought for next open (keep existing same-day seed)
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

  -- Leaving sleep on first active context of the day: keep morningThought for client feed
  IF old_mode = 'sleep'::"LifeMode" AND new_mode <> 'sleep'::"LifeMode" THEN
    IF morning IS NULL OR c."morningThoughtDayKey" IS DISTINCT FROM day_key THEN
      morning := format(
        'Bom dia! %s acordou pensando em você (modo %s).',
        c.name,
        new_mode::text
      );
    END IF;
  END IF;

  -- Freeze decay in sleep; otherwise respect IoT presence freeze
  IF new_mode = 'sleep'::"LifeMode" THEN
    frozen := true;
  ELSE
    frozen := c."presenceStatus" IN ('away'::"PresenceStatus", 'expedition'::"PresenceStatus");
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

REVOKE ALL ON FUNCTION companion_ingest_context(
  text, boolean, text, int, int, boolean, int, boolean, text, text, timestamptz
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_ingest_context(
  text, boolean, text, int, int, boolean, int, boolean, text, text, timestamptz
) TO service_role;

-- Clear morning thought after client consumed it (optional)
CREATE OR REPLACE FUNCTION companion_ack_morning_thought(p_user_id text)
RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion";
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  UPDATE "Companion" SET "morningThought" = NULL WHERE id = c.id RETURNING * INTO c;
  RETURN c;
END;
$$;

REVOKE ALL ON FUNCTION companion_ack_morning_thought(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION companion_ack_morning_thought(text) TO service_role;
