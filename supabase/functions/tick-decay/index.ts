import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

/**
 * Cron a cada ~10 min.
 * companion_tick_all: decay + minutos de convivência + títulos +
 * sonhos oníricos com último mediaHint / gamingStatus do dia.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const secret = Deno.env.get("CRON_SECRET");
  const auth = req.headers.get("Authorization") ?? "";
  const cronHeader = req.headers.get("x-cron-secret") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const ok =
    (secret && cronHeader === secret) ||
    auth === `Bearer ${serviceKey}` ||
    !secret;
  if (!ok) return json({ error: "unauthorized" }, 401);

  const sb = serviceClient();
  const { data, error } = await sb.rpc("companion_tick_all");
  if (error) return json({ error: error.message }, 500);

  // Contagem leve de companions em sono (observabilidade)
  const { count } = await sb
    .from("Companion")
    .select("id", { count: "exact", head: true })
    .eq("lifeMode", "sleep");

  return json({
    ok: true,
    ticked: data,
    sleeping: count ?? 0,
    dreams: "mediaHint/gamingStatus injected via companion_pick_dream_line",
  });
});
