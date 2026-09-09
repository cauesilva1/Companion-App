-- Fuso do usuário (ex.: America/Toronto), não mais hardcoded São Paulo.

ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "timezone" TEXT;

-- Backfill conservador: quem ainda não tem fuso fica America/Toronto
-- (produto atual do dono); o iPhone sobrescreve no próximo ingest.
UPDATE "Companion"
SET "timezone" = 'America/Toronto'
WHERE "timezone" IS NULL OR length(trim("timezone")) = 0;

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
  p_now timestamptz DEFAULT now(),
  p_app_foreground boolean DEFAULT false,
  p_timezone text DEFAULT NULL
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
  day_mode "LifeMode";
  new_presence "PresenceStatus";
  day_key text;
  morning text;
  frozen boolean;
  ctx jsonb;
  prev_media text;
  prev_gaming text;
  seeded_morning boolean := false;
  in_bed_window boolean;
  can_wake boolean;
  tz text;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  prev_media := c."mediaHint";
  prev_gaming := c."gamingStatus";

  tz := NULLIF(trim(COALESCE(p_timezone, c."timezone", 'America/Toronto')), '');
  BEGIN
    PERFORM p_now AT TIME ZONE tz;
  EXCEPTION WHEN OTHERS THEN
    tz := 'America/Toronto';
  END;

  hour_local := COALESCE(
    p_local_hour,
    EXTRACT(HOUR FROM (p_now AT TIME ZONE tz))::int
  );

  IF p_on_home_wifi IS NOT NULL THEN
    on_home := p_on_home_wifi;
  ELSIF c."homeWifiSsid" IS NOT NULL AND p_ssid IS NOT NULL AND length(trim(p_ssid)) > 0 THEN
    on_home := lower(trim(c."homeWifiSsid")) = lower(trim(p_ssid));
  ELSE
    on_home := NULL;
  END IF;

  old_mode := c."lifeMode";

  IF on_home IS FALSE
        AND hour_local >= 7 AND hour_local < 18
        AND COALESCE(p_steps_recent, 0) >= 120 THEN
    day_mode := 'work'::"LifeMode";
  ELSIF on_home IS FALSE AND hour_local >= 7 AND hour_local < 19 THEN
    day_mode := 'work'::"LifeMode";
  ELSE
    day_mode := 'indoor'::"LifeMode";
  END IF;

  in_bed_window := (hour_local >= 23 OR hour_local < 6);
  can_wake := COALESCE(p_app_foreground, false)
              AND hour_local >= 6
              AND hour_local < 23;

  IF old_mode = 'sleep'::"LifeMode" THEN
    IF can_wake THEN
      new_mode := day_mode;
    ELSE
      new_mode := 'sleep'::"LifeMode";
    END IF;
  ELSIF in_bed_window THEN
    new_mode := 'sleep'::"LifeMode";
  ELSE
    new_mode := day_mode;
  END IF;

  new_presence := CASE new_mode
    WHEN 'work'::"LifeMode" THEN 'away'::"PresenceStatus"
    WHEN 'sleep'::"LifeMode" THEN 'expedition'::"PresenceStatus"
    ELSE 'present'::"PresenceStatus"
  END;

  frozen := (new_mode = 'sleep'::"LifeMode");

  day_key := to_char((p_now AT TIME ZONE tz)::date, 'YYYY-MM-DD');
  morning := c."morningThought";

  IF new_mode = 'sleep'::"LifeMode" AND (
    c."morningThoughtDayKey" IS NULL OR c."morningThoughtDayKey" <> day_key
  ) THEN
    morning := format(
      'No sono: %s guarda um sonho de patch note sem changelog. Energia %s%%.',
      c.name,
      c.energy::text
    );
    seeded_morning := true;
  END IF;

  IF old_mode = 'sleep'::"LifeMode" AND new_mode <> 'sleep'::"LifeMode" THEN
    IF morning IS NULL OR c."morningThoughtDayKey" IS DISTINCT FROM day_key THEN
      morning := format(
        'Bom dia! %s acordou quando você abriu o app — a história do dia começa agora.',
        c.name
      );
      seeded_morning := true;
    END IF;
  END IF;

  IF COALESCE(p_app_foreground, false)
     AND new_mode <> 'sleep'::"LifeMode"
     AND hour_local >= 6
     AND hour_local < 23
     AND (c."morningThoughtDayKey" IS NULL OR c."morningThoughtDayKey" <> day_key)
     AND (morning IS NULL OR length(trim(morning)) = 0 OR NOT seeded_morning)
  THEN
    IF NOT seeded_morning THEN
      morning := format(
        'Bom dia. %s abriu o olho com você — micro-história do dia em andamento.',
        c.name
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
    'appForeground', COALESCE(p_app_foreground, false),
    'timezone', tz,
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
    "lastContextAt" = p_now,
    "timezone" = tz
  WHERE id = c.id
  RETURNING * INTO c;

  IF seeded_morning AND morning IS NOT NULL THEN
    PERFORM companion_seed_morning_thought_row(p_user_id, morning, day_key);
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
    'onHomeWifi', on_home,
    'localHour', hour_local,
    'timezone', tz,
    'stillSleepy', (new_mode = 'sleep'::"LifeMode" AND hour_local < 6)
  );
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
  line text;
  kind text;
  hour_local int;
  in_bed boolean;
  day_key text;
  morning text;
  entered_sleep boolean;
  tz text;
BEGIN
  FOR r IN
    SELECT id, "userId", "lifeMode", name, energy, affection, "decayFrozen",
           "mediaHint", "gamingStatus", "morningThoughtDayKey", "timezone"
    FROM "Companion"
  LOOP
    entered_sleep := false;
    tz := NULLIF(trim(COALESCE(r."timezone", 'America/Toronto')), '');
    BEGIN
      PERFORM now() AT TIME ZONE tz;
    EXCEPTION WHEN OTHERS THEN
      tz := 'America/Toronto';
    END;

    hour_local := EXTRACT(HOUR FROM (now() AT TIME ZONE tz))::int;
    in_bed := (hour_local >= 23 OR hour_local < 6);
    day_key := to_char((now() AT TIME ZONE tz)::date, 'YYYY-MM-DD');

    IF in_bed AND r."lifeMode" IS DISTINCT FROM 'sleep'::"LifeMode" THEN
      PERFORM set_config('companion.allow_survival_write', 'on', true);
      UPDATE "Companion" SET
        "lifeMode" = 'sleep'::"LifeMode",
        "lifeModeAt" = now(),
        "presenceStatus" = 'expedition'::"PresenceStatus",
        "decayFrozen" = true
      WHERE id = r.id;
      entered_sleep := true;
      r."lifeMode" := 'sleep'::"LifeMode";
      r."decayFrozen" := true;

      IF r."morningThoughtDayKey" IS NULL OR r."morningThoughtDayKey" <> day_key THEN
        morning := format(
          'No sono: %s guarda um sonho de patch note sem changelog. Energia %s%%.',
          r.name,
          r.energy::text
        );
        UPDATE "Companion" SET
          "morningThought" = morning,
          "morningThoughtDayKey" = day_key
        WHERE id = r.id;
        PERFORM companion_seed_morning_thought_row(r."userId", morning, day_key);
      END IF;
    END IF;

    PERFORM companion_apply_decay(r.id, now());
    PERFORM companion_accrue_mode_minutes(r.id, now());
    PERFORM companion_sync_titles(r.id);
    n := n + 1;

    IF r."lifeMode" = 'sleep'::"LifeMode" OR r."decayFrozen" THEN
      kind := 'dream';
      line := companion_pick_dream_line(r.name, r."mediaHint", r."gamingStatus");
    ELSIF r."lifeMode" = 'work'::"LifeMode" THEN
      kind := 'work';
      line := companion_pick_work_line(r.name, r.energy);
    ELSE
      kind := 'rest';
      line := companion_pick_rest_line(r.name, r.energy);
    END IF;

    IF entered_sleep OR random() < 0.34 THEN
      PERFORM companion_append_thought(r."userId", line, kind, NULL);
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION companion_tick_all() TO service_role;
