import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

/** Schedule via Supabase Dashboard Cron → this function every 10 minutes.
 *  Header: Authorization: Bearer <SERVICE_ROLE> or x-cron-secret.
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
  return json({ ok: true, ticked: data });
});
