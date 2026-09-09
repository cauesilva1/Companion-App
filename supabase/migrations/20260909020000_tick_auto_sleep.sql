-- Sono automático no tick (23h–5h59 America/Sao_Paulo), sem depender do app aberto.
-- Antes, lifeMode só virava sleep se context-ingest rodasse na janela — phone fechado = nunca dormia.

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
  hour_sp int;
  in_bed boolean;
  day_key text;
  morning text;
  entered_sleep boolean;
BEGIN
  hour_sp := EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Sao_Paulo'))::int;
  in_bed := (hour_sp >= 23 OR hour_sp < 6);
  day_key := to_char((now() AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD');

  FOR r IN
    SELECT id, "userId", "lifeMode", name, energy, affection, "decayFrozen",
           "mediaHint", "gamingStatus", "morningThoughtDayKey"
    FROM "Companion"
  LOOP
    entered_sleep := false;

    -- Entra em sleep pelo relógio (mesmo sem telemetria do iPhone).
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
