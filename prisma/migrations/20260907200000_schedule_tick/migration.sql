-- Prisma mirror: schedule companion_tick_all every 15 minutes via pg_cron.
-- Fallback: .github/workflows/companion-tick.yml

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

DO $cronsetup$
DECLARE
  jid int;
BEGIN
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'companion-tick-decay' LIMIT 1;
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;
  PERFORM cron.schedule(
    'companion-tick-decay',
    '*/15 * * * *',
    'SELECT companion_tick_all()'
  );
EXCEPTION
  WHEN undefined_table THEN
    RAISE NOTICE 'cron.job missing — enable pg_cron in Dashboard (Database → Extensions)';
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron schedule failed — use GitHub Actions companion-tick.yml: %', SQLERRM;
END;
$cronsetup$;
