import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";
import { fetchXboxStatus } from "../_shared/xbox.ts";
import { resolveWeather } from "../_shared/weather.ts";

/**
 * POST /context-ingest
 * Telemetria do iPhone → companion_ingest_context (lifeMode work|indoor|sleep).
 * Em modo indoor, opcionalmente enriquece gamingStatus via OpenXBL.
 * Clima: GPS do device ou Toronto + Open-Meteo.
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
    timezone?: string;
    mediaActive?: boolean;
    mediaHint?: string;
    homeWifiSsid?: string;
    xboxGamertag?: string;
    ackMorning?: boolean;
    appForeground?: boolean;
    latitude?: number;
    longitude?: number;
    weatherCondition?: string;
    weatherTempC?: number;
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
    .select("xboxGamertag, lifeMode, lat, lon")
    .eq("userId", userId)
    .order("createdAt", { ascending: true })
    .limit(1);

  let gamingStatus: string | null = null;
  const gamertag =
    (rows?.[0]?.xboxGamertag as string | null) || body.xboxGamertag || null;

  if (gamertag && (body.onHomeWifi === true || body.mediaActive === true)) {
    const xbox = await fetchXboxStatus(gamertag);
    if (xbox) gamingStatus = xbox.line;
  }

  const localHour =
    typeof body.localHour === "number" && Number.isFinite(body.localHour)
      ? Math.floor(body.localHour)
      : new Date().getHours();

  const lat =
    typeof body.latitude === "number" && Number.isFinite(body.latitude)
      ? body.latitude
      : typeof rows?.[0]?.lat === "number"
      ? (rows[0].lat as number)
      : null;
  const lon =
    typeof body.longitude === "number" && Number.isFinite(body.longitude)
      ? body.longitude
      : typeof rows?.[0]?.lon === "number"
      ? (rows[0].lon as number)
      : null;

  const weather = await resolveWeather({
    latitude: lat,
    longitude: lon,
    condition: body.weatherCondition ?? null,
    tempC: body.weatherTempC ?? null,
    localHour,
  });

  const ingestPayload = {
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
    p_timezone: typeof body.timezone === "string" && body.timezone.trim().length > 0
      ? body.timezone.trim()
      : null,
    p_latitude: weather.latitude,
    p_longitude: weather.longitude,
    p_weather_condition: weather.condition,
    p_weather_temp_c: weather.tempC,
  };

  const { data, error } = await sb.rpc("companion_ingest_context", ingestPayload);

  if (error) return json({ error: error.message }, 500);

  let result = data as Record<string, unknown>;

  if (result?.lifeMode === "indoor" && gamertag) {
    const xbox = await fetchXboxStatus(gamertag);
    if (xbox && xbox.line !== result.gamingStatus) {
      await sb.rpc("companion_ingest_context", {
        ...ingestPayload,
        p_on_home_wifi: body.onHomeWifi ?? true,
        p_gaming_status: xbox.line,
      });
      result.gamingStatus = xbox.line;
    }
  }

  if (body.ackMorning === true) {
    await sb.rpc("companion_ack_morning_thought", { p_user_id: userId });
  }

  await sb.rpc("companion_refresh_titles_for_user", {
    p_user_id: userId,
  });
  const { data: titleRows } = await sb
    .from("Companion")
    .select("activeTitle, titleKey, equippedTitleKey, weatherCondition, weatherTempC, weatherAt")
    .eq("userId", userId)
    .order("createdAt", { ascending: true })
    .limit(1);
  const titleRow = titleRows?.[0];
  if (titleRow) {
    result.activeTitle = titleRow.activeTitle ?? result.activeTitle;
    result.titleKey = titleRow.titleKey ?? null;
    result.equippedTitleKey = titleRow.equippedTitleKey ?? null;
    result.weatherCondition = titleRow.weatherCondition ?? weather.condition;
    result.weatherTempC = titleRow.weatherTempC ?? weather.tempC;
    result.weatherAt = titleRow.weatherAt ?? null;
  } else {
    result.weatherCondition = weather.condition;
    result.weatherTempC = weather.tempC;
  }

  const { data: thoughts } = await sb.rpc("companion_list_thoughts", {
    p_user_id: userId,
    p_limit: 40,
  });

  return json({ ok: true, ...(result as object), thoughts: thoughts ?? [] });
});
