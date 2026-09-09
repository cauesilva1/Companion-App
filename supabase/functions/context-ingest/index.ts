import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";
import { fetchXboxStatus } from "../_shared/xbox.ts";

/**
 * POST /context-ingest
 * Telemetria do iPhone → companion_ingest_context (lifeMode work|indoor|sleep).
 * Em modo indoor, opcionalmente enriquece gamingStatus via OpenXBL.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);

  let body: {
    onHomeWifi?: boolean;
    ssid?: string;
    stepsToday?: number;
    stepsRecent?: number;
    isCharging?: boolean;
    localHour?: number;
    mediaActive?: boolean;
    mediaHint?: string;
    homeWifiSsid?: string;
    xboxGamertag?: string;
    ackMorning?: boolean;
    appForeground?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const userSb = userClient(auth);
  const { data: userData, error: uErr } = await userSb.auth.getUser();
  if (uErr || !userData.user) return json({ error: "unauthorized" }, 401);

  const sb = serviceClient();
  const userId = userData.user.id;

  if (body.homeWifiSsid || body.xboxGamertag) {
    await sb.rpc("companion_set_home_context", {
      p_user_id: userId,
      p_home_wifi_ssid: body.homeWifiSsid ?? null,
      p_xbox_gamertag: body.xboxGamertag ?? null,
    });
  }

  const { data: rows } = await sb
    .from("Companion")
    .select("xboxGamertag, lifeMode")
    .eq("userId", userId)
    .order("createdAt", { ascending: true })
    .limit(1);

  let gamingStatus: string | null = null;
  const gamertag =
    (rows?.[0]?.xboxGamertag as string | null) || body.xboxGamertag || null;

  // Prefetch Xbox when likely indoor OR always light-check if gamertag set
  // (RPC decides final lifeMode; we refresh gaming after)
  if (gamertag && (body.onHomeWifi === true || body.mediaActive === true)) {
    const xbox = await fetchXboxStatus(gamertag);
    if (xbox) gamingStatus = xbox.line;
  }

  const { data, error } = await sb.rpc("companion_ingest_context", {
    p_user_id: userId,
    p_on_home_wifi: body.onHomeWifi ?? null,
    p_ssid: body.ssid ?? null,
    p_steps_today: Math.max(0, Math.floor(Number(body.stepsToday) || 0)),
    p_steps_recent: Math.max(0, Math.floor(Number(body.stepsRecent) || 0)),
    p_is_charging: Boolean(body.isCharging),
    p_local_hour: typeof body.localHour === "number" ? body.localHour : null,
    p_media_active: Boolean(body.mediaActive),
    p_media_hint: body.mediaHint ?? null,
    p_gaming_status: gamingStatus,
    p_app_foreground: Boolean(body.appForeground),
  });

  if (error) return json({ error: error.message }, 500);

  let result = data as Record<string, unknown>;

  // Se indoor e ainda sem gamingStatus fresco, busca OpenXBL
  if (result?.lifeMode === "indoor" && gamertag) {
    const xbox = await fetchXboxStatus(gamertag);
    if (xbox && xbox.line !== result.gamingStatus) {
      await sb.rpc("companion_ingest_context", {
        p_user_id: userId,
        p_on_home_wifi: body.onHomeWifi ?? true,
        p_ssid: body.ssid ?? null,
        p_steps_today: Math.max(0, Math.floor(Number(body.stepsToday) || 0)),
        p_steps_recent: Math.max(0, Math.floor(Number(body.stepsRecent) || 0)),
        p_is_charging: Boolean(body.isCharging),
        p_local_hour: typeof body.localHour === "number" ? body.localHour : null,
        p_media_active: Boolean(body.mediaActive),
        p_media_hint: body.mediaHint ?? null,
        p_gaming_status: xbox.line,
        p_app_foreground: Boolean(body.appForeground),
      });
      result.gamingStatus = xbox.line;
    }
  }

  if (body.ackMorning === true) {
    await sb.rpc("companion_ack_morning_thought", { p_user_id: userId });
  }

  // Pensamento de mídia (feed + título DJ do Sofá)
  const mediaHint =
    typeof result.mediaHint === "string" ? result.mediaHint.trim() : "";
  if (body.mediaActive === true && mediaHint.length > 0) {
    await sb.rpc("companion_append_thought", {
      p_user_id: userId,
      p_text: `Ouvindo: ${mediaHint}`,
      p_kind: "music",
      p_zone_name: null,
    });
  }

  // Sync títulos (unlock append-only; não força re-equip)
  const { data: title } = await sb.rpc("companion_refresh_titles_for_user", {
    p_user_id: userId,
  });
  if (typeof title === "string" && title.length > 0) {
    result.activeTitle = title;
  }

  // Return latest thoughts so iOS can sync feed
  const { data: thoughts } = await sb.rpc("companion_list_thoughts", {
    p_user_id: userId,
    p_limit: 40,
  });

  return json({ ok: true, ...(result as object), thoughts: thoughts ?? [] });
});
