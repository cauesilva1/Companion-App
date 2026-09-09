-- Emotes contextuais + títulos por convivência + sonhos com mídia/jogo

-- 1) Colunas de título / acumuladores de convivência
ALTER TABLE "Companion"
  ADD COLUMN IF NOT EXISTS "activeTitle" TEXT,
  ADD COLUMN IF NOT EXISTS "titleKey" TEXT,
  ADD COLUMN IF NOT EXISTS "indoorMinutes" INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "workMinutes" INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "sleepMinutes" INT NOT NULL DEFAULT 0;

-- Protect: cliente não sobrescreve título/minutos
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
  RETURN NEW;
END;
$$;

-- 2) Acumula minutos no modo atual (cap por chamada)
CREATE OR REPLACE FUNCTION companion_accrue_mode_minutes(
  p_companion_id text,
  p_now timestamptz DEFAULT now()
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  delta int;
BEGIN
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id;
  IF NOT FOUND THEN RETURN; END IF;

  delta := GREATEST(
    0,
    LEAST(
      45,
      FLOOR(EXTRACT(EPOCH FROM (p_now - COALESCE(c."lastContextAt", c."lifeModeAt", p_now))) / 60.0)::int
    )
  );
  IF delta <= 0 THEN
    delta := 1; -- tick mínimo
  END IF;

  PERFORM set_config('companion.allow_survival_write', 'on', true);

  IF c."lifeMode" = 'work'::"LifeMode" THEN
    UPDATE "Companion" SET "workMinutes" = "workMinutes" + delta WHERE id = c.id;
  ELSIF c."lifeMode" = 'sleep'::"LifeMode" THEN
    UPDATE "Companion" SET "sleepMinutes" = "sleepMinutes" + delta WHERE id = c.id;
  ELSE
    UPDATE "Companion" SET "indoorMinutes" = "indoorMinutes" + delta WHERE id = c.id;
  END IF;
END;
$$;

-- 3) Resolve título ativo por convivência
CREATE OR REPLACE FUNCTION companion_resolve_title(p_companion_id text)
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
  t_key text;
  t_label text;
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

  -- Prioridade (mais específico / raro primeiro)
  IF music_n >= 3 OR (c."mediaHint" IS NOT NULL AND length(trim(c."mediaHint")) > 0 AND c."indoorMinutes" >= 60) THEN
    t_key := 'dj_sofa'; t_label := 'DJ do Sofá';
  ELSIF gaming_n >= 3 THEN
    t_key := 'game_buddy'; t_label := 'Colega de Game';
  ELSIF c."sleepMinutes" >= 90 OR dream_n >= 5 THEN
    t_key := 'night_owl'; t_label := 'Companheiro de Madrugada';
  ELSIF c."workMinutes" >= 120 THEN
    t_key := 'street_partner'; t_label := 'Parceiro de Rua';
  ELSIF c."indoorMinutes" >= 180 THEN
    t_key := 'sofa_king'; t_label := 'Rei do Sofá';
  ELSIF c.affection >= 85 THEN
    t_key := 'warm_heart'; t_label := 'Coração Quente';
  ELSIF days_alive >= 7 THEN
    t_key := 'veteran'; t_label := 'Veterano';
  ELSIF days_alive >= 2 THEN
    t_key := 'loyal'; t_label := 'Companheiro Fiel';
  ELSE
    t_key := 'newcomer'; t_label := 'Recém-chegado';
  END IF;

  PERFORM set_config('companion.allow_survival_write', 'on', true);
  UPDATE "Companion" SET
    "titleKey" = t_key,
    "activeTitle" = t_label
  WHERE id = c.id;

  RETURN t_label;
END;
$$;

GRANT EXECUTE ON FUNCTION companion_accrue_mode_minutes(text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION companion_resolve_title(text) TO service_role;

-- 4) Sonhos personalizados com último mediaHint / gamingStatus
CREATE OR REPLACE FUNCTION companion_pick_dream_line(
  p_name text,
  p_media_hint text DEFAULT NULL,
  p_gaming_status text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
  media text;
  game text;
BEGIN
  media := NULLIF(trim(COALESCE(p_media_hint, '')), '');
  game := NULLIF(trim(COALESCE(p_gaming_status, '')), '');

  IF media IS NOT NULL THEN
    lines := ARRAY[
      format('%s sonha que a faixa "%s" vira um rio de luz no sofá.', p_name, left(media, 48)),
      format('No sono, %s dança sem som ao ritmo de %s.', p_name, left(media, 40)),
      format('Sonho: a TV sussurra "%s" e as paredes respiram no beat.', left(media, 36)),
      format('%s guarda a melodia de %s no bolso do pijama.', p_name, left(media, 40)),
      format('História onírica: %s flutua numa nuvem feita da última música do dia.', p_name)
    ];
  ELSIF game IS NOT NULL THEN
    lines := ARRAY[
      format('%s sonha que o Xbox ainda está ligado: %s — mas o controle é de nuvem.', p_name, left(game, 40)),
      format('No sono, %s joga %s em câmera lenta, rindo sem som.', p_name, left(game, 36)),
      format('Sonho gamer: pixels de %s chovem no tapete da sala.', left(game, 40)),
      format('%s guarda um save onírico de %s sob o travesseiro.', p_name, left(game, 36))
    ];
  ELSE
    lines := ARRAY[
      format('%s sonha que o sofá vira um barco em mar de estrelas.', p_name),
      format('No sono, %s persegue um snack que voa pela sala…', p_name),
      format('%s sonha com você chegando em casa — mas o relógio derrete.', p_name),
      'Sonho: a TV fala baixo e as paredes respiram em rosa.',
      format('%s flutua pelo teto, leve como nuvem de sofá.', p_name),
      'História onírica: passos na rua viram batidas de coração no escuro.',
      format('%s guarda um segredo no bolso do pijama. Acorda? Ainda não.', p_name),
      'Sonho leve: chuva de pixels caindo no tapete da sala.'
    ];
  END IF;

  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

-- 5) Tick: accrue + título + dreams com contexto
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
    PERFORM companion_resolve_title(r.id);
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

GRANT EXECUTE ON FUNCTION companion_tick_all() TO service_role;

-- 6) Hook leve no ingest: accrue + resolve title ao final
-- (redefine wrapper: chama resolve após update já feito em companion_ingest_context
--  via função auxiliar usada pelo edge — adicionamos RPC dedicada)

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
  title := companion_resolve_title(cid);
  RETURN title;
END;
$$;

GRANT EXECUTE ON FUNCTION companion_refresh_titles_for_user(text) TO service_role;
