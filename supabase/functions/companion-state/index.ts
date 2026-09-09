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
  const userId = userData.user.id;
  const { data: rows } = await sb
    .from("Companion")
    .select("*")
    .eq("userId", userId)
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

  // Refresh Xbox when indoor (or gamertag set — status still useful)
  if (row.xboxGamertag) {
    const xbox = await fetchXboxStatus(String(row.xboxGamertag));
    if (xbox && xbox.line !== row.gamingStatus) {
      const { data: updated } = await sb.rpc("companion_set_gaming_status", {
        p_user_id: userId,
        p_gaming_status: xbox.line,
      });
      if (updated) row = updated;
      else row = { ...row, gamingStatus: xbox.line };
      // Feed row when indoor
      if (row.lifeMode === "indoor") {
        await sb.rpc("companion_append_thought", {
          p_user_id: userId,
          p_text: `Xbox: ${xbox.line}`,
          p_kind: "gaming",
          p_zone_name: null,
        });
      }
    }
  }

  // Sync títulos + bundle de perfil/badges
  await sb.rpc("companion_refresh_titles_for_user", { p_user_id: userId });
  const { data: refreshed } = await sb
    .from("Companion")
    .select("*")
    .eq("userId", userId)
    .order("createdAt", { ascending: true })
    .limit(1);
  if (refreshed?.[0]) row = refreshed[0];

  const { data: thoughts } = await sb.rpc("companion_list_thoughts", {
    p_user_id: userId,
    p_limit: 40,
  });

  const { data: profile } = await sb.rpc("companion_profile_stats", {
    p_user_id: userId,
  });

  return json({
    ok: true,
    companion: row,
    thoughts: thoughts ?? [],
    profile: profile ?? null,
    context: {
      lifeMode: row.lifeMode ?? "indoor",
      gamingStatus: row.gamingStatus ?? null,
      mediaHint: row.mediaHint ?? null,
      morningThought: row.morningThought ?? null,
      activeTitle: row.activeTitle ?? null,
      titleKey: row.titleKey ?? null,
      equippedTitleKey: row.equippedTitleKey ?? null,
      decayFrozen: row.decayFrozen ?? false,
      presenceStatus: row.presenceStatus ?? "present",
    },
  });
});
