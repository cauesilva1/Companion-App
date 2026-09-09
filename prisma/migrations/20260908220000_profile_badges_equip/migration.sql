-- Perfil + galeria de badges + títulos equipáveis + critérios endurecidos

ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "unlockedTitles" TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS "equippedTitleKey" TEXT;

-- Protege colunas de título/equip contra write direto do cliente
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
  RETURN NEW;
END;
$$;

-- Catálogo estável de badges/títulos
CREATE OR REPLACE FUNCTION companion_title_catalog()
RETURNS TABLE (
  key text,
  label text,
  symbol text,
  description text,
  metric text,
  target numeric,
  "unit" text,
  rarity int
)
LANGUAGE sql
STABLE
AS $$
  SELECT * FROM (VALUES
    ('newcomer',       'Recém-chegado',           'sparkles',              'Começou a convivência.',                    'days',   0::numeric,   'dias', 0),
    ('loyal',          'Companheiro Fiel',        'heart.fill',            '7 dias de convivência.',                    'days',   7::numeric,   'dias', 1),
    ('veteran',        'Veterano',                'shield.fill',           '30 dias juntos.',                           'days',   30::numeric,  'dias', 2),
    ('warm_heart',     'Coração Quente',          'heart.circle.fill',     'Afeto alto e consistência.',                'affection_days', 90::numeric, 'afeto', 3),
    ('sofa_king',      'Rei do Sofá',             'sofa.fill',             '20h no sofá ao longo dos dias.',            'indoor_h', 20::numeric, 'h', 4),
    ('street_partner', 'Parceiro de Rua',         'figure.walk',           '15h em modo rua/trabalho.',                 'work_h', 15::numeric, 'h', 4),
    ('night_owl',      'Companheiro de Madrugada','moon.zzz.fill',         '20h de sono ou 40 sonhos.',                 'sleep_h', 20::numeric, 'h', 5),
    ('game_buddy',     'Colega de Game',          'gamecontroller.fill',  '25 sessões de Xbox no feed.',               'gaming', 25::numeric, 'x', 6),
    ('dj_sofa',        'DJ do Sofá',              'music.note',            '25 músicas + 10h de sofá.',                 'music',  25::numeric, 'x', 7)
  ) AS t(key, label, symbol, description, metric, target, unit, rarity);
$$;

CREATE OR REPLACE FUNCTION companion_title_label(p_key text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT label FROM companion_title_catalog() WHERE key = p_key LIMIT 1;
$$;

-- Sync: desbloqueia (append-only); só auto-equipa se equipped inválido/null
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
  k text;
  best_key text;
  best_rarity int := -1;
  eq_key text;
  eq_label text;
  r record;
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

  -- Sempre
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

  -- Merge append-only com já desbloqueados
  unlocked := (
    SELECT ARRAY(SELECT DISTINCT x FROM unnest(COALESCE(c."unlockedTitles", '{}') || unlocked) AS x)
  );

  -- Melhor título por raridade (para auto-equip)
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

-- Compat: resolve_title agora só sync (não force-override de equipped válido)
CREATE OR REPLACE FUNCTION companion_resolve_title(p_companion_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN companion_sync_titles(p_companion_id);
END;
$$;

CREATE OR REPLACE FUNCTION companion_refresh_titles_for_user(p_user_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cid text;
  title text;
BEGIN
  SELECT id INTO cid FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF cid IS NULL THEN RETURN NULL; END IF;
  PERFORM companion_accrue_mode_minutes(cid, now());
  title := companion_sync_titles(cid);
  RETURN title;
END;
$$;

CREATE OR REPLACE FUNCTION companion_equip_title(p_user_id text, p_title_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  lbl text;
  caller text;
BEGIN
  caller := auth.uid()::text;
  IF caller IS NOT NULL AND caller IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_companion');
  END IF;

  -- Garante unlocks atualizados
  PERFORM companion_sync_titles(c.id);
  SELECT * INTO c FROM "Companion" WHERE id = c.id;

  IF p_title_key IS NULL OR length(trim(p_title_key)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_key');
  END IF;

  IF NOT (p_title_key = ANY(COALESCE(c."unlockedTitles", '{}'))) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'locked');
  END IF;

  lbl := COALESCE(companion_title_label(p_title_key), p_title_key);

  PERFORM set_config('companion.allow_survival_write', 'on', true);
  UPDATE "Companion" SET
    "equippedTitleKey" = p_title_key,
    "titleKey" = p_title_key,
    "activeTitle" = lbl
  WHERE id = c.id
  RETURNING * INTO c;

  RETURN jsonb_build_object(
    'ok', true,
    'equippedTitleKey', c."equippedTitleKey",
    'activeTitle', c."activeTitle",
    'titleKey', c."titleKey"
  );
END;
$$;

-- Bundle thin-client: stats + badges com progresso
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
    equipped := c."equippedTitleKey" IS NOT DISTINCT FROM r.key;
    target := r.target;

    CASE r.metric
      WHEN 'days' THEN
        progress := days_alive;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN target <= 0 THEN 'Desbloqueado'
          ELSE format('Faltam %s dias', ceil(remaining)::int) END;
      WHEN 'affection_days' THEN
        progress := LEAST(c.affection::numeric, 90);
        -- também precisa days>=7; progresso combinado em hint
        IF days_alive < 7 THEN
          hint := format('Afeto %s/90 · faltam %s dias', c.affection, ceil(7 - days_alive)::int);
        ELSIF unlocked THEN
          hint := 'Desbloqueado';
        ELSE
          hint := format('Afeto %s/90', c.affection);
        END IF;
        remaining := GREATEST(0, 90 - c.affection);
      WHEN 'indoor_h' THEN
        progress := c."indoorMinutes" / 60.0;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 5 THEN format('Faltam %s dias · %sh/%sh sofá', ceil(5 - days_alive)::int, round(progress,1), target)
          ELSE format('Faltam %sh de sofá', round(remaining, 1)) END;
      WHEN 'work_h' THEN
        progress := c."workMinutes" / 60.0;
        remaining := GREATEST(0, target - progress);
        hint := CASE WHEN unlocked THEN 'Desbloqueado'
          WHEN days_alive < 5 THEN format('Faltam %s dias · %sh/%sh rua', ceil(5 - days_alive)::int, round(progress,1), target)
          ELSE format('Faltam %sh de rua', round(remaining, 1)) END;
      WHEN 'sleep_h' THEN
        -- progresso = max(horas sono, dreams/2 equivalente visual)
        progress := GREATEST(c."sleepMinutes" / 60.0, dream_n * (20.0 / 40.0));
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
      ELSE
        progress := 0;
        hint := r.description;
    END CASE;

    badges := badges || jsonb_build_array(jsonb_build_object(
      'key', r.key,
      'label', r.label,
      'symbol', r.symbol,
      'description', r.description,
      'unlocked', unlocked,
      'equipped', equipped,
      'progress', round(progress::numeric, 2),
      'target', target,
      'unit', r.unit,
      'hint', hint,
      'rarity', r.rarity
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
    'badges', badges
  );
END;
$$;

-- tick continua usando companion_resolve_title (= sync)
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
BEGIN
  FOR r IN
    SELECT id, "userId", "lifeMode", name, energy, "decayFrozen", "mediaHint", "gamingStatus"
    FROM "Companion"
  LOOP
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

    IF random() < 0.34 THEN
      PERFORM companion_append_thought(r."userId", line, kind, NULL);
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION companion_title_catalog() TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_title_label(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_sync_titles(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_resolve_title(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_refresh_titles_for_user(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_equip_title(text, text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_profile_stats(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_tick_all() TO service_role, authenticated;

-- Backfill: sync todos os companions existentes
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT id FROM "Companion" LOOP
    PERFORM companion_sync_titles(r.id);
  END LOOP;
END $$;
