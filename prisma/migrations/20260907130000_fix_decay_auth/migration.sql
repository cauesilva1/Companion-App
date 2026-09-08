-- Allow cron / SECURITY DEFINER callers without JWT to run decay.
CREATE OR REPLACE FUNCTION companion_apply_decay(p_companion_id text, p_now timestamptz DEFAULT now())
RETURNS "Companion"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c "Companion"%ROWTYPE;
  hours_since double precision;
  hours_idle double precision;
  new_aff double precision;
  new_en double precision;
  new_mood "Mood";
BEGIN
  PERFORM set_config('companion.allow_survival_write', 'on', true);
  SELECT * INTO c FROM "Companion" WHERE id = p_companion_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'companion not found';
  END IF;
  -- Enforce ownership only when a user JWT is present.
  IF auth.uid() IS NOT NULL AND c."userId" IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF c."decayFrozen" OR c."presenceStatus" IN ('away'::"PresenceStatus", 'expedition'::"PresenceStatus") THEN
    RETURN c;
  END IF;

  hours_since := EXTRACT(EPOCH FROM (p_now - c."lastInteractionAt")) / 3600.0;
  hours_idle := GREATEST(0, hours_since - 1.0);
  new_aff := GREATEST(0, LEAST(100, c.affection - hours_idle * (2.0 / 24.0)));
  new_en := GREATEST(0, LEAST(100, c.energy - hours_idle * 0.5));
  new_mood := companion_compute_mood(new_aff, new_en, hours_since / 24.0);

  UPDATE "Companion" SET
    energy = ROUND(new_en)::int,
    affection = ROUND(new_aff)::int,
    mood = new_mood,
    "lastDecayAt" = p_now
  WHERE id = c.id
  RETURNING * INTO c;
  RETURN c;
END;
$$;
