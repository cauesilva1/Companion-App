import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";
import { fetchXboxStatus } from "../_shared/xbox.ts";
import { resolveWeather } from "../_shared/weather.ts";

const WEATHER_STALE_MS = 25 * 60_000;

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

  // Refresh weather if stale (>25 min) using saved coords or Toronto
  const weatherAtMs = row.weatherAt ? Date.parse(String(row.weatherAt)) : 0;
  const weatherStale = !Number.isFinite(weatherAtMs) || Date.now() - weatherAtMs > WEATHER_STALE_MS;
  if (weatherStale) {
    const tz = String(row.timezone || "America/Toronto");
    let localHour = new Date().getHours();
    try {
      const fmt = new Intl.DateTimeFormat("en-CA", {
        timeZone: tz,
        hour: "numeric",
        hour12: false,
      });
      localHour = Number(fmt.format(new Date()));
    } catch {
      /* keep UTC hour */
    }
    try {
      const weather = await resolveWeather({
        latitude: typeof row.lat === "number" ? row.lat : null,
        longitude: typeof row.lon === "number" ? row.lon : null,
        condition: null,
        tempC: null,
        localHour,
      });
      const { data: wxRows } = await sb
        .from("Companion")
        .update({
          weatherCondition: weather.condition,
          weatherTempC: weather.tempC,
          weatherAt: new Date().toISOString(),
          lat: weather.latitude,
          lon: weather.longitude,
        })
        .eq("id", row.id)
        .select("*")
        .limit(1);
      if (wxRows?.[0]) row = wxRows[0];
      else {
        row = {
          ...row,
          weatherCondition: weather.condition,
          weatherTempC: weather.tempC,
          weatherAt: new Date().toISOString(),
          lat: weather.latitude,
          lon: weather.longitude,
        };
      }
    } catch {
      /* keep stale weather */
    }
  }

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
      weatherCondition: row.weatherCondition ?? null,
      weatherTempC: row.weatherTempC ?? null,
      weatherAt: row.weatherAt ?? null,
    },
  });
});
