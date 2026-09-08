import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";
import { fetchXboxStatus } from "../_shared/xbox.ts";

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
  let row = rows?.[0];
  if (!row) return json({ error: "no_companion" }, 404);

  if (!row.decayFrozen) {
    const { data: decayed } = await sb.rpc("companion_apply_decay", {
      p_companion_id: row.id,
    });
    row = decayed ?? row;
  }

  // Refresh Xbox presence when indoor (enriquece system prompt / widgets)
  if (row.lifeMode === "indoor" && row.xboxGamertag) {
    const xbox = await fetchXboxStatus(String(row.xboxGamertag));
    if (xbox && xbox.line !== row.gamingStatus) {
      await sb
        .from("Companion")
        .update({ gamingStatus: xbox.line })
        .eq("id", row.id);
      row = { ...row, gamingStatus: xbox.line };
    }
  }

  return json({
    ok: true,
    companion: row,
    context: {
      lifeMode: row.lifeMode ?? "indoor",
      gamingStatus: row.gamingStatus ?? null,
      mediaHint: row.mediaHint ?? null,
      morningThought: row.morningThought ?? null,
      decayFrozen: row.decayFrozen ?? false,
      presenceStatus: row.presenceStatus ?? "present",
    },
  });
});
