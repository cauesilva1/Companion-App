import { corsHeaders, json } from "../_shared/cors.ts";
import { serviceClient, sha256Hex, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);

  let body: { label?: string };
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const userSb = userClient(auth);
  const { data: userData, error: uErr } = await userSb.auth.getUser();
  if (uErr || !userData.user) return json({ error: "unauthorized" }, 401);

  const rawKey = `dev_${crypto.randomUUID().replace(/-/g, "")}`;
  const hash = await sha256Hex(rawKey);
  const id = `iot_${crypto.randomUUID().slice(0, 12)}`;
  const sb = serviceClient();
  const { error } = await sb.from("IotDevice").insert({
    id,
    userId: userData.user.id,
    deviceKeyHash: hash,
    label: body.label?.trim() || "mesa",
  });
  if (error) return json({ error: error.message }, 500);

  return json({
    ok: true,
    deviceId: id,
    deviceKey: rawKey,
    note: "Guarde deviceKey no ESP32 (X-Device-Key). Não é mostrado de novo.",
  });
});
