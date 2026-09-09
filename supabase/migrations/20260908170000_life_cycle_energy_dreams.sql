-- Life-cycle energy: indoor recovers, work drains (+ steps fatigue), sleep freezes + dreams.
-- Also rate-limits auto thoughts to stop feed spam.

-- 1) Rate-limited append (mood/cloud/dream/rest/work spam)
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
  kind text;
  cooldown interval;
  recent "CompanionThought";
BEGIN
  body := left(trim(COALESCE(p_text, '')), 280);
  IF length(body) = 0 THEN
    RAISE EXCEPTION 'empty_thought';
  END IF;

  kind := COALESCE(NULLIF(trim(p_kind), ''), 'mood');

  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_companion';
  END IF;

  -- Auto kinds: 3 min; music/gaming events: 5 min; morning: 12 h
  cooldown := CASE
    WHEN kind IN ('mood', 'cloud', 'dream', 'rest', 'work') THEN interval '3 minutes'
    WHEN kind IN ('music', 'gaming') THEN interval '5 minutes'
    WHEN kind = 'morning' THEN interval '12 hours'
    ELSE interval '90 seconds'
  END;

  SELECT * INTO recent
  FROM "CompanionThought"
  WHERE "companionId" = c.id
    AND "kind" = kind
    AND "createdAt" > now() - cooldown
  ORDER BY "createdAt" DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN recent;
  END IF;

  -- Also block near-identical text across auto kinds within 2 minutes
  IF kind IN ('mood', 'cloud', 'dream', 'rest', 'work') THEN
    SELECT * INTO recent
    FROM "CompanionThought"
    WHERE "companionId" = c.id
      AND "text" = body
      AND "createdAt" > now() - interval '2 minutes'
    ORDER BY "createdAt" DESC
    LIMIT 1;
    IF FOUND THEN
      RETURN recent;
    END IF;
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
    kind,
    NULLIF(trim(COALESCE(p_zone_name, '')), ''),
    c."lifeMode"::text,
    c."mediaHint",
    c."gamingStatus",
    now()
  )
  RETURNING * INTO t;

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

-- 2) Dream / mode line pickers
CREATE OR REPLACE FUNCTION companion_pick_dream_line(p_name text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
BEGIN
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
  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

CREATE OR REPLACE FUNCTION companion_pick_rest_line(p_name text, p_energy int)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
BEGIN
  lines := ARRAY[
    format('%s descansa no sofá — energia subindo devagar (%s%%).', p_name, p_energy::text),
    format('Casa = recarga. %s boceja e recupera fôlego.', p_name),
    format('Modo sofá: %s regenera enquanto você está em casa.', p_name),
    'Lazer indoor: corpo leve, bateria voltando.'
  ];
  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

CREATE OR REPLACE FUNCTION companion_pick_work_line(p_name text, p_energy int)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
BEGIN
  IF p_energy < 35 THEN
    lines := ARRAY[
      format('%s quase no limite… ainda assim segue na rua.', p_name),
      format('Cansaço batendo: %s segura o ritmo fora de casa.', p_name),
      format('Dia pesado — %s acompanha cada passo (energia %s%%).', p_name, p_energy::text)
    ];
  ELSE
    lines := ARRAY[
      format('%s rala na rua com você — energia em %s%%.', p_name, p_energy::text),
      format('Dia de campo: %s sente o cansaço dos passos.', p_name),
      format('Fora de casa: esforço contínuo. %s segura o ritmo.', p_name),
      format('%s acompanha o dia presencial, sem sofá.', p_name)
    ];
  END IF;
  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

-- 3) Decay / recovery by lifeMode
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
  grace double precision;
  aff_per_h double precision;
  en_delta_per_h double precision; -- positivo = gasta; negativo = recupera
  steps_recent int := 0;
  days_since double precision;
  new_aff double precision;
  new_en double precision;
  new_mood "Mood";
  mode text;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'companion not found';
  END IF;

  mode := COALESCE(c."lifeMode"::text, 'indoor');

  -- Sleep: congela desgaste físico (sonhos vêm no tick separado)
  IF c."decayFrozen" OR mode = 'sleep' THEN
    -- Ainda avança lastDecayAt levemente? Não — congela o relógio de desgaste.
    RETURN c;
  END IF;

  hours := EXTRACT(EPOCH FROM (p_now - c."lastDecayAt")) / 3600.0;

  IF mode = 'indoor' THEN
    grace := 0.25; -- recupera logo em casa
    aff_per_h := 1.0 / 24.0; -- afeto cai bem devagar
    en_delta_per_h := -3.0; -- recupera ~3 energia/hora
  ELSIF mode = 'work' THEN
    grace := 0.5;
    aff_per_h := 2.0 / 24.0;
    en_delta_per_h := 3.5; -- cansaço base do dia
    BEGIN
      steps_recent := COALESCE((c."contextJson"->>'stepsRecent')::int, 0);
    EXCEPTION WHEN others THEN
      steps_recent := 0;
    END;
    -- Esforço extra pelos passos recentes (até +4/h)
    en_delta_per_h := en_delta_per_h + LEAST(4.0, GREATEST(0, steps_recent) / 500.0);
  ELSE
    grace := 1.0;
    aff_per_h := 2.0 / 24.0;
    en_delta_per_h := 0.5;
  END IF;

  IF hours <= grace THEN
    RETURN c;
  END IF;
  hours := hours - grace;

  new_aff := GREATEST(0, LEAST(100, c.affection - hours * aff_per_h));
  -- en_delta_per_h > 0 gasta; < 0 recupera
  new_en := GREATEST(0, LEAST(100, c.energy - hours * en_delta_per_h));
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

-- 4) Steps: work = fadiga; indoor = leve recarga; sleep = ignore
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
  should_units int;
  delta int;
  c "Companion"%ROWTYPE;
  mode text;
  new_energy int;
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

  SELECT * INTO c FROM "Companion" WHERE "userId" = p_user_id ORDER BY "createdAt" ASC LIMIT 1;
  IF NOT FOUND THEN
    RETURN json_build_object(
      'steps', ledger.steps,
      'energyGranted', ledger."energyGranted",
      'energyDelta', 0,
      'energy', 0
    );
  END IF;

  mode := COALESCE(c."lifeMode"::text, 'indoor');
  delta := 0;
  new_energy := c.energy;

  IF mode = 'sleep' OR c."decayFrozen" THEN
    -- Sono: passos não mexem na energia
    NULL;
  ELSIF mode = 'work' THEN
    -- Fadiga: cada 400 passos → -1 energia (cap diário 30)
    steps_per := 400;
    cap := 30;
    should_units := LEAST(cap, (ledger.steps / steps_per));
    -- Reusa energyGranted como "fatigueApplied" no dia
    delta := GREATEST(0, should_units - ledger."energyGranted");
    IF delta > 0 THEN
      UPDATE "StepsLedger" SET "energyGranted" = ledger."energyGranted" + delta WHERE id = ledger.id
      RETURNING * INTO ledger;
      new_energy := GREATEST(0, c.energy - delta);
      UPDATE "Companion" SET
        energy = new_energy,
        "lastInteractionAt" = now()
      WHERE id = c.id
      RETURNING * INTO c;
      delta := -delta; -- report negativo = gasto
    END IF;
  ELSE
    -- Indoor: passos leves ainda ajudam um pouco (metade do ritmo antigo)
    steps_per := 750;
    cap := 12;
    should_units := LEAST(cap, (ledger.steps / steps_per));
    delta := GREATEST(0, should_units - ledger."energyGranted");
    IF delta > 0 THEN
      UPDATE "StepsLedger" SET "energyGranted" = ledger."energyGranted" + delta WHERE id = ledger.id
      RETURNING * INTO ledger;
      new_energy := LEAST(100, c.energy + delta);
      UPDATE "Companion" SET
        energy = new_energy,
        "lastInteractionAt" = now()
      WHERE id = c.id
      RETURNING * INTO c;
    END IF;
  END IF;

  RETURN json_build_object(
    'steps', ledger.steps,
    'energyGranted', ledger."energyGranted",
    'energyDelta', delta,
    'energy', coalesce(c.energy, new_energy, 0),
    'lifeMode', mode
  );
END;
$$;

GRANT EXECUTE ON FUNCTION steps_ingest(text, text, int) TO authenticated, service_role;

-- 5) Tick: decay todos + pensamentos de modo com cooldown natural via append
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
    SELECT id, "userId", "lifeMode", name, energy, "decayFrozen"
    FROM "Companion"
  LOOP
    -- Decay/recovery (sleep no-op dentro de apply_decay)
    PERFORM companion_apply_decay(r.id, now());
    n := n + 1;

    -- Feed alinhado ao estado (rate-limit interno do append)
    IF r."lifeMode" = 'sleep'::"LifeMode" OR r."decayFrozen" THEN
      kind := 'dream';
      line := companion_pick_dream_line(r.name);
    ELSIF r."lifeMode" = 'work'::"LifeMode" THEN
      kind := 'work';
      line := companion_pick_work_line(r.name, r.energy);
    ELSE
      kind := 'rest';
      line := companion_pick_rest_line(r.name, r.energy);
    END IF;

    -- Só tenta append ~1/3 das vezes no tick (cron ~15min → menos spam)
    IF random() < 0.34 THEN
      PERFORM companion_append_thought(r."userId", line, kind, NULL);
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION companion_tick_all() TO service_role;
