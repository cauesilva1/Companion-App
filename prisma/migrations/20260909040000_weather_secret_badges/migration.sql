-- Clima real (Open-Meteo) + badges secretas (easter eggs).

ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "weatherCondition" TEXT,
  ADD COLUMN IF NOT EXISTS "weatherTempC" INT,
  ADD COLUMN IF NOT EXISTS "weatherAt" TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lon DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "secretFlags" JSONB NOT NULL DEFAULT '{}'::jsonb;

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
  NEW."activeTitle" := OLD."activeTitle";
  NEW."titleKey" := OLD."titleKey";
  NEW."indoorMinutes" := OLD."indoorMinutes";
  NEW."workMinutes" := OLD."workMinutes";
  NEW."sleepMinutes" := OLD."sleepMinutes";
  NEW."unlockedTitles" := OLD."unlockedTitles";
  NEW."equippedTitleKey" := OLD."equippedTitleKey";
  NEW."timezone" := OLD."timezone";
  NEW."weatherCondition" := OLD."weatherCondition";
  NEW."weatherTempC" := OLD."weatherTempC";
  NEW."weatherAt" := OLD."weatherAt";
  NEW.lat := OLD.lat;
  NEW.lon := OLD.lon;
  NEW."secretFlags" := OLD."secretFlags";
  RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS companion_title_catalog();

CREATE OR REPLACE FUNCTION companion_title_catalog()
RETURNS TABLE (
  key text,
  label text,
  symbol text,
  description text,
  metric text,
  target numeric,
  "unit" text,
  rarity int,
  secret boolean
)
LANGUAGE sql
STABLE
AS $$
  SELECT * FROM (VALUES
    ('newcomer',       'Recém-chegado',           'sparkles',              'Começou a convivência.',                    'days',   0::numeric,   'dias', 0, false),
    ('loyal',          'Companheiro Fiel',        'heart.fill',            '7 dias de convivência.',                    'days',   7::numeric,   'dias', 1, false),
    ('veteran',        'Veterano',                'shield.fill',           '30 dias juntos.',                           'days',   30::numeric,  'dias', 2, false),
    ('warm_heart',     'Coração Quente',          'heart.circle.fill',     'Afeto alto e consistência.',                'affection_days', 90::numeric, 'afeto', 3, false),
    ('sofa_king',      'Rei do Sofá',             'sofa.fill',             '20h no sofá ao longo dos dias.',            'indoor_h', 20::numeric, 'h', 4, false),
    ('street_partner', 'Parceiro de Rua',         'figure.walk',           '15h em modo rua/trabalho.',                 'work_h', 15::numeric, 'h', 4, false),
    ('night_owl',      'Companheiro de Madrugada','moon.zzz.fill',         '20h de sono ou 40 sonhos.',                 'sleep_h', 20::numeric, 'h', 5, false),
    ('game_buddy',     'Colega de Game',          'gamecontroller.fill',  '25 sessões de Xbox no feed.',               'gaming', 25::numeric, 'x', 6, false),
    ('dj_sofa',        'DJ do Sofá',              'music.note',            '25 músicas + 10h de sofá.',                 'music',  25::numeric, 'x', 7, false),
    ('snow_whisper',   'Sussurro de Neve',        'snowflake',             'Abriu o app sob neve real.',                'secret', 1::numeric,  'x', 8, true),
    ('midnight_signal','Sinal da Madrugada',      'moon.stars.fill',       'Abriu o app entre 0h e 3h locais.',         'secret', 1::numeric,  'x', 8, true),
    ('storm_sofa',     'Sofá da Tempestade',      'cloud.bolt.rain.fill',  'Conversou no sofá sob chuva ou neve.',      'secret', 1::numeric,  'x', 9, true)
  ) AS t(key, label, symbol, description, metric, target, unit, rarity, secret);
$$;

CREATE OR REPLACE FUNCTION companion_title_label(p_key text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT label FROM companion_title_catalog() WHERE key = p_key LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION companion_sync_titles(p_companion_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  music_n int;
  gaming_n int;
  dream_n int;
  days_alive numeric;
  unlocked text[] := ARRAY[]::text[];
  best_key text;
  best_rarity int := -1;
  eq_key text;
  eq_label text;
  r record;
  flags jsonb;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT COUNT(*) INTO music_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'music';
  SELECT COUNT(*) INTO gaming_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'gaming';
  SELECT COUNT(*) INTO dream_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'dream';

  days_alive := EXTRACT(EPOCH FROM (now() - c."createdAt")) / 86400.0;
  flags := COALESCE(c."secretFlags", '{}'::jsonb);

  unlocked := array_append(unlocked, 'newcomer');

  IF days_alive >= 7 THEN
    unlocked := array_append(unlocked, 'loyal');
  END IF;
  IF days_alive >= 30 THEN
    unlocked := array_append(unlocked, 'veteran');
  END IF;
  IF c.affection >= 90 AND days_alive >= 7 THEN
    unlocked := array_append(unlocked, 'warm_heart');
  END IF;
  IF c."indoorMinutes" >= 1200 AND days_alive >= 5 THEN
    unlocked := array_append(unlocked, 'sofa_king');
  END IF;
  IF c."workMinutes" >= 900 AND days_alive >= 5 THEN
    unlocked := array_append(unlocked, 'street_partner');
  END IF;
  IF (c."sleepMinutes" >= 1200 OR dream_n >= 40) AND days_alive >= 5 THEN
    unlocked := array_append(unlocked, 'night_owl');
  END IF;
  IF gaming_n >= 25 AND days_alive >= 7 THEN
    unlocked := array_append(unlocked, 'game_buddy');
  END IF;
  IF music_n >= 25 AND c."indoorMinutes" >= 600 AND days_alive >= 7 THEN
    unlocked := array_append(unlocked, 'dj_sofa');
  END IF;

  IF COALESCE((flags->>'sawSnow')::boolean, false) THEN
    unlocked := array_append(unlocked, 'snow_whisper');
  END IF;
  IF COALESCE((flags->>'midnightOpen')::boolean, false) THEN
    unlocked := array_append(unlocked, 'midnight_signal');
  END IF;
  IF flags ? 'stormChatAt' AND length(trim(COALESCE(flags->>'stormChatAt', ''))) > 0 THEN
    unlocked := array_append(unlocked, 'storm_sofa');
  END IF;

  unlocked := (
    SELECT ARRAY(SELECT DISTINCT x FROM unnest(COALESCE(c."unlockedTitles", '{}') || unlocked) AS x)
  );

  FOR r IN SELECT * FROM companion_title_catalog() LOOP
    IF r.key = ANY(unlocked) AND r.rarity > best_rarity THEN
      best_rarity := r.rarity;
      best_key := r.key;
    END IF;
  END LOOP;

  eq_key := c."equippedTitleKey";
  IF eq_key IS NULL OR NOT (eq_key = ANY(unlocked)) THEN
    eq_key := COALESCE(best_key, 'newcomer');
  END IF;
  eq_label := COALESCE(companion_title_label(eq_key), 'Recém-chegado');

  PERFORM set_config('companion.allow_survival_write', 'on', true);
  UPDATE "Companion" SET
    "unlockedTitles" = unlocked,
    "equippedTitleKey" = eq_key,
    "titleKey" = eq_key,
    "activeTitle" = eq_label
  WHERE id = c.id;

  RETURN eq_label;
END;
$$;

CREATE OR REPLACE FUNCTION companion_profile_stats(p_user_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  music_n int;
  gaming_n int;
  dream_n int;
  days_alive numeric;
  badges jsonb := '[]'::jsonb;
  r record;
  progress numeric;
  target numeric;
  unlocked bool;
  equipped bool;
  hint text;
  remaining numeric;
  caller text;
  out_label text;
  out_symbol text;
  out_desc text;
  out_progress numeric;
  out_target numeric;
  out_hint text;
BEGIN
  caller := auth.uid()::text;
  IF caller IS NOT NULL AND caller IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_companion');
  END IF;

  PERFORM companion_sync_titles(c.id);
  SELECT * INTO c FROM "Companion" WHERE id = c.id;

  SELECT COUNT(*) INTO music_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'music';
  SELECT COUNT(*) INTO gaming_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'gaming';
  SELECT COUNT(*) INTO dream_n FROM "CompanionThought"
    WHERE "companionId" = c.id AND kind = 'dream';

  days_alive := GREATEST(0, EXTRACT(EPOCH FROM (now() - c."createdAt")) / 86400.0);

  FOR r IN SELECT * FROM companion_title_catalog() ORDER BY rarity ASC LOOP
    unlocked := r.key = ANY(COALESCE(c."unlockedTitles", '{}'));
    equipped := unlocked AND c."equippedTitleKey" IS NOT DISTINCT FROM r.key;
    target := r.target;
    progress := 0;
    hint := r.description;

    CASE r.metric
      WHEN 'days' THEN
        progress := days_alive;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN target <= 0 THEN 'Desbloqueado'
          ELSE format('Faltam %s dias', ceil(remaining)::int) END;
      WHEN 'affection_days' THEN
        progress := c.affection;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 7 THEN format('Faltam %s dias · afeto %s/%s', ceil(7 - days_alive)::int, c.affection, target::int)
          ELSE format('Afeto %s/%s', c.affection, target::int) END;
      WHEN 'indoor_h' THEN
        progress := c."indoorMinutes" / 60.0;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 5 THEN format('Faltam %s dias · sofá %sh/%sh', ceil(5 - days_alive)::int, round(progress,1), target)
          ELSE format('Sofá %sh/%sh', round(progress,1), target) END;
      WHEN 'work_h' THEN
        progress := c."workMinutes" / 60.0;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 5 THEN format('Faltam %s dias · rua %sh/%sh', ceil(5 - days_alive)::int, round(progress,1), target)
          ELSE format('Rua %sh/%sh', round(progress,1), target) END;
      WHEN 'sleep_h' THEN
        progress := c."sleepMinutes" / 60.0;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 5 THEN format('Faltam %s dias', ceil(5 - days_alive)::int)
          ELSE format('Sono %sh/%sh ou sonhos %s/40', round(c."sleepMinutes"/60.0,1), target, dream_n) END;
      WHEN 'gaming' THEN
        progress := gaming_n;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 7 THEN format('Faltam %s dias · %s/%s games', ceil(7 - days_alive)::int, gaming_n, target::int)
          ELSE format('Faltam %s sessões de game', ceil(remaining)::int) END;
      WHEN 'music' THEN
        progress := music_n;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 7 THEN format('Faltam %s dias · músicas %s/%s', ceil(7 - days_alive)::int, music_n, target::int)
          WHEN c."indoorMinutes" < 600 THEN format('Músicas %s/%s · sofá %sh/10h', music_n, target::int, round(c."indoorMinutes"/60.0,1))
          ELSE format('Faltam %s músicas', ceil(remaining)::int) END;
      WHEN 'secret' THEN
        progress := CASE WHEN unlocked THEN 1 ELSE 0 END;
        target := 1;
        hint := CASE WHEN unlocked THEN 'Segredo revelado' ELSE 'Condição misteriosa…' END;
      ELSE
        progress := 0;
        hint := r.description;
    END CASE;

    out_label := r.label;
    out_symbol := r.symbol;
    out_desc := r.description;
    out_progress := progress;
    out_target := target;
    out_hint := hint;

    IF r.secret AND NOT unlocked THEN
      out_label := '???';
      out_symbol := 'questionmark.circle';
      out_desc := 'Algo está escondido aqui.';
      out_progress := 0;
      out_target := 1;
      out_hint := 'Condição misteriosa…';
    END IF;

    badges := badges || jsonb_build_array(jsonb_build_object(
      'key', r.key,
      'label', out_label,
      'symbol', out_symbol,
      'description', out_desc,
      'unlocked', unlocked,
      'equipped', equipped,
      'progress', round(out_progress::numeric, 2),
      'target', out_target,
      'unit', r.unit,
      'hint', out_hint,
      'rarity', r.rarity,
      'secret', r.secret
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'name', c.name,
    'skin', c.skin,
    'archetype', c.archetype,
    'mood', c.mood,
    'energy', c.energy,
    'affection', c.affection,
    'lifeMode', c."lifeMode",
    'activeTitle', c."activeTitle",
    'titleKey', c."titleKey",
    'equippedTitleKey', c."equippedTitleKey",
    'unlockedTitles', to_jsonb(COALESCE(c."unlockedTitles", '{}')),
    'indoorMinutes', c."indoorMinutes",
    'workMinutes', c."workMinutes",
    'sleepMinutes', c."sleepMinutes",
    'indoorHours', round((c."indoorMinutes" / 60.0)::numeric, 1),
    'workHours', round((c."workMinutes" / 60.0)::numeric, 1),
    'sleepHours', round((c."sleepMinutes" / 60.0)::numeric, 1),
    'musicCount', music_n,
    'gamingCount', gaming_n,
    'dreamCount', dream_n,
    'daysAlive', round(days_alive::numeric, 1),
    'weatherCondition', c."weatherCondition",
    'weatherTempC', c."weatherTempC",
    'weatherAt', c."weatherAt",
    'badges', badges
  );
END;
$$;

-- Chat sob chuva/neve no sofá → flag stormChatAt
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
  flags jsonb;
  day_key text;
  tz text;
  wx text;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  c := companion_apply_decay(p_companion_id, now_ts);

  fx_aff := CASE p_type
    WHEN 'POKE' THEN 2
    WHEN 'FEED' THEN 0
    WHEN 'PLAY' THEN 6
    WHEN 'CHAT' THEN 4
    WHEN 'TEASE' THEN 5
    WHEN 'IGNORE_CHECK' THEN -4
    ELSE 0 END;

  fx_en := CASE p_type
    WHEN 'POKE' THEN -1
    WHEN 'FEED' THEN 8
    WHEN 'PLAY' THEN -4
    WHEN 'CHAT' THEN -1
    WHEN 'TEASE' THEN -1
    WHEN 'IGNORE_CHECK' THEN -2
    ELSE 0 END;

  new_aff := GREATEST(0, LEAST(100, c.affection + fx_aff));
  new_en := GREATEST(0, LEAST(100, c.energy + fx_en));
  new_mood := companion_compute_mood(new_aff, new_en, 0);

  flags := COALESCE(c."secretFlags", '{}'::jsonb);
  wx := lower(trim(COALESCE(c."weatherCondition", '')));
  IF p_type = 'CHAT'
     AND c."lifeMode" = 'indoor'::"LifeMode"
     AND wx IN ('rainy', 'snowy')
  THEN
    tz := NULLIF(trim(COALESCE(c."timezone", 'America/Toronto')), '');
    BEGIN
      PERFORM now_ts AT TIME ZONE tz;
    EXCEPTION WHEN OTHERS THEN
      tz := 'America/Toronto';
    END;
    day_key := to_char((now_ts AT TIME ZONE tz)::date, 'YYYY-MM-DD');
    flags := flags || jsonb_build_object('stormChatAt', day_key);
  END IF;

  UPDATE "Companion" SET
    energy = new_en,
    affection = new_aff,
    mood = new_mood,
    "lastDecayAt" = now_ts,
    "lastInteractionAt" = now_ts,
    "pendingAlert" = NULL,
    "secretFlags" = flags
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

DROP FUNCTION IF EXISTS companion_ingest_context(
  text, boolean, text, int, int, boolean, int, boolean, text, text, timestamptz, boolean, text
);

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
  p_timezone text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_weather_condition text DEFAULT NULL,
  p_weather_temp_c int DEFAULT NULL
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
  prev_gaming text;
  seeded_morning boolean := false;
  in_bed_window boolean;
  can_wake boolean;
  tz text;
  wx text;
  wx_temp int;
  flags jsonb;
  lat_v double precision;
  lon_v double precision;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  prev_gaming := c."gamingStatus";
  flags := COALESCE(c."secretFlags", '{}'::jsonb);

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

  wx := lower(trim(COALESCE(p_weather_condition, c."weatherCondition")));
  IF wx IS NOT NULL AND wx NOT IN ('sunny', 'rainy', 'snowy', 'cloudy', 'night') THEN
    wx := NULL;
  END IF;
  wx_temp := COALESCE(p_weather_temp_c, c."weatherTempC");
  lat_v := COALESCE(p_latitude, c.lat);
  lon_v := COALESCE(p_longitude, c.lon);

  IF COALESCE(p_app_foreground, false) AND wx = 'snowy' THEN
    flags := flags || jsonb_build_object('sawSnow', true);
  END IF;
  IF COALESCE(p_app_foreground, false) AND hour_local >= 0 AND hour_local < 4 THEN
    flags := flags || jsonb_build_object('midnightOpen', true);
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
    'weatherCondition', wx,
    'weatherTempC', wx_temp,
    'lat', lat_v,
    'lon', lon_v,
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
    "timezone" = tz,
    "weatherCondition" = COALESCE(wx, "weatherCondition"),
    "weatherTempC" = COALESCE(wx_temp, "weatherTempC"),
    "weatherAt" = CASE WHEN p_weather_condition IS NOT NULL OR p_weather_temp_c IS NOT NULL THEN p_now ELSE "weatherAt" END,
    lat = COALESCE(lat_v, lat),
    lon = COALESCE(lon_v, lon),
    "secretFlags" = flags
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
    'stillSleepy', (new_mode = 'sleep'::"LifeMode" AND hour_local < 6),
    'weatherCondition', c."weatherCondition",
    'weatherTempC', c."weatherTempC",
    'weatherAt', c."weatherAt"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION companion_title_catalog() TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_sync_titles(text) TO service_role;
GRANT EXECUTE ON FUNCTION companion_profile_stats(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_apply_interaction(text, "InteractionType", text, text) TO service_role;
GRANT EXECUTE ON FUNCTION companion_ingest_context(
  text, boolean, text, int, int, boolean, int, boolean, text, text, timestamptz, boolean, text,
  double precision, double precision, text, int
) TO service_role;
