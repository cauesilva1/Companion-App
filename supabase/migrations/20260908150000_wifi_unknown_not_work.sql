-- Unknown Wi‑Fi (SSID nil) must not force lifeMode=work.
-- on_home: true | false | NULL (unknown)

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

  -- Prefer explicit iOS flag; else compare SSIDs; else NULL (unknown — não forçar work)
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
  -- work só com certeza de estar fora de casa
  ELSIF on_home IS FALSE
        AND hour_local >= 7 AND hour_local < 18
        AND COALESCE(p_steps_recent, 0) >= 120 THEN
    new_mode := 'work'::"LifeMode";
  ELSIF on_home IS FALSE AND hour_local >= 7 AND hour_local < 19 THEN
    new_mode := 'work'::"LifeMode";
  ELSE
    -- indoor: em casa, OU SSID desconhecido, OU fora do horário de work
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
