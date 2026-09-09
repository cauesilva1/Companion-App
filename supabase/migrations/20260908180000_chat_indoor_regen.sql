-- Chat em casa não briga com regeneração; indoor recupera mais rápido (visível).

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
  mode text;
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  c := companion_apply_decay(p_companion_id, now_ts);
  mode := COALESCE(c."lifeMode"::text, 'indoor');

  fx_aff := CASE p_type
    WHEN 'POKE' THEN 2 WHEN 'FEED' THEN 0 WHEN 'PLAY' THEN 6
    WHEN 'CHAT' THEN 4 WHEN 'TEASE' THEN 5 WHEN 'IGNORE_CHECK' THEN -4
    ELSE 0 END;
  fx_en := CASE p_type
    WHEN 'POKE' THEN -1
    WHEN 'FEED' THEN 8
    WHEN 'PLAY' THEN -4
    WHEN 'CHAT' THEN
      CASE WHEN mode = 'indoor' THEN 0 ELSE -2 END
    WHEN 'TEASE' THEN -2
    WHEN 'IGNORE_CHECK' THEN -2
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

-- Indoor: ~6 energia/hora (antes 3) — ~1 ponto a cada 10 min após grace de 15 min
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
  en_delta_per_h double precision;
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

  IF c."decayFrozen" OR mode = 'sleep' THEN
    RETURN c;
  END IF;

  hours := EXTRACT(EPOCH FROM (p_now - c."lastDecayAt")) / 3600.0;

  IF mode = 'indoor' THEN
    grace := 0.15;
    aff_per_h := 1.0 / 24.0;
    en_delta_per_h := -6.0; -- recupera ~6/h
  ELSIF mode = 'work' THEN
    grace := 0.5;
    aff_per_h := 2.0 / 24.0;
    en_delta_per_h := 3.5;
    BEGIN
      steps_recent := COALESCE((c."contextJson"->>'stepsRecent')::int, 0);
    EXCEPTION WHEN others THEN
      steps_recent := 0;
    END;
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
