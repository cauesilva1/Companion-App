import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";

/**
 * GET  /thoughts — lista feed autoritativo (asc)
 * POST /thoughts — { text, kind?, zoneName? } append
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);

  const userSb = userClient(auth);
  const { data: userData, error: uErr } = await userSb.auth.getUser();
  if (uErr || !userData.user) return json({ error: "unauthorized" }, 401);

  const sb = serviceClient();
  const userId = userData.user.id;

  if (req.method === "GET") {
    const url = new URL(req.url);
    const limit = Math.min(120, Math.max(1, Number(url.searchParams.get("limit") || 40)));
    const { data, error } = await sb.rpc("companion_list_thoughts", {
      p_user_id: userId,
      p_limit: limit,
    });
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, thoughts: data ?? [] });
  }

  if (req.method === "POST") {
    let body: { text?: string; kind?: string; zoneName?: string };
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const text = String(body.text || "").trim();
    if (!text) return json({ error: "empty_thought" }, 400);

    const { data, error } = await sb.rpc("companion_append_thought", {
      p_user_id: userId,
      p_text: text,
      p_kind: body.kind ?? "mood",
      p_zone_name: body.zoneName ?? null,
    });
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, thought: data });
  }

  return json({ error: "method_not_allowed" }, 405);
});
