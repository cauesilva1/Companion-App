import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);

  const userSb = userClient(auth);
  const { data: userData, error: uErr } = await userSb.auth.getUser();
  if (uErr || !userData.user) return json({ error: "unauthorized" }, 401);

  const sb = serviceClient();
  const { data: rows } = await sb
    .from("Companion")
    .select("*")
    .eq("userId", userData.user.id)
    .order("createdAt", { ascending: true })
    .limit(1);
  const row = rows?.[0];
  if (!row) return json({ error: "no_companion" }, 404);

  if (!row.decayFrozen) {
    const { data: decayed } = await sb.rpc("companion_apply_decay", {
      p_companion_id: row.id,
    });
    return json({ ok: true, companion: decayed ?? row });
  }
  return json({ ok: true, companion: row });
});
