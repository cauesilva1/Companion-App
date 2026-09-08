import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, sha256Hex } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const deviceKey = req.headers.get("x-device-key")?.trim();
  if (!deviceKey) return json({ error: "missing_device_key" }, 401);

  let body: { kind?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const kind = (body.kind || "pet").toLowerCase();
  const interactionType = kind === "attention" ? "TEASE" : "POKE";

  const sb = serviceClient();
  const hash = await sha256Hex(deviceKey);
  const { data: device, error: dErr } = await sb
    .from("IotDevice")
    .select("id,userId,revokedAt")
    .eq("deviceKeyHash", hash)
    .maybeSingle();
  if (dErr) return json({ error: dErr.message }, 500);
  if (!device || device.revokedAt) return json({ error: "invalid_device" }, 401);

  await sb.from("IotInteractEvent").insert({
    id: `iev_${crypto.randomUUID().slice(0, 12)}`,
    deviceId: device.id,
    kind,
  });
  await sb
    .from("IotDevice")
    .update({ lastSeenAt: new Date().toISOString() })
    .eq("id", device.id);

  const { data: companions } = await sb
    .from("Companion")
    .select("id")
    .eq("userId", device.userId)
    .limit(1);
  const companionId = companions?.[0]?.id;
  if (!companionId) return json({ error: "no_companion" }, 404);

  const { data: companion, error: cErr } = await sb.rpc("companion_apply_interaction", {
    p_companion_id: companionId,
    p_type: interactionType,
    p_message: null,
    p_reaction: kind === "attention" ? "Você me deu atenção na mesa!" : "Carinho na mesa!",
  });
  if (cErr) return json({ error: cErr.message }, 500);

  return json({
    ok: true,
    kind,
    interactionType,
    energy: companion?.energy,
    affection: companion?.affection,
    mood: companion?.mood,
  });
});
