-- Chat é a interação principal (sem FEED na UI): não drena energia; leve recarga social.

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
    WHEN 'POKE' THEN 2
    WHEN 'FEED' THEN 0
    WHEN 'PLAY' THEN 6
    WHEN 'CHAT' THEN 4
    WHEN 'TEASE' THEN 5
    WHEN 'IGNORE_CHECK' THEN -4
    ELSE 0 END;

  -- CHAT: conversa não cansa (é a forma principal de cuidar). +1 energia social.
  -- Outros tipos legados mantêm custo; FEED ainda cura se existir.
  fx_en := CASE p_type
    WHEN 'POKE' THEN -1
    WHEN 'FEED' THEN 8
    WHEN 'PLAY' THEN -4
    WHEN 'CHAT' THEN 1
    WHEN 'TEASE' THEN -1
    WHEN 'IGNORE_CHECK' THEN -2
    ELSE 0 END;

  -- Na rua, conversa não recupera energia (só não gasta).
  IF p_type = 'CHAT' AND mode = 'work' THEN
    fx_en := 0;
  END IF;

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
