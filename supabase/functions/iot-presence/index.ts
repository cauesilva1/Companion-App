/**
 * POST /functions/v1/iot-presence
 * Headers: X-Device-Key
 * Body: { "rssi": -45 } | { "action": "pet", "rssi": -45 }
 *
 * Toda falha devolve Response JSON — nunca EarlyDrop silencioso.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-device-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Spec: IOT_RSSI_PRESENT_THRESHOLD */
const RSSI_PRESENT = -75;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function fail(status: number, error: string, detail?: unknown): Response {
  console.error("[iot-presence]", status, error, detail ?? "");
  return json(
    {
      ok: false,
      error,
      ...(detail !== undefined
        ? { detail: typeof detail === "string" ? detail : String(detail) }
        : {}),
    },
    status,
  );
}

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function makeServiceClient() {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!url || !url.startsWith("http")) {
    throw new Error("missing_or_invalid_SUPABASE_URL");
  }
  if (!key || key.length < 20) {
    throw new Error("missing_or_invalid_SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  const raw = await req.text();
  if (!raw || !raw.trim()) return {};
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    throw new Error("body_not_object");
  } catch (e) {
    throw new Error(`invalid_json: ${e instanceof Error ? e.message : String(e)}`);
  }
}

Deno.serve(async (req) => {
  // Isola TODO o handler — EarlyDrop só acontece se o runtime cair antes disto.
  try {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }
    if (req.method !== "POST") {
      return fail(405, "method_not_allowed");
    }

    const deviceKey =
      req.headers.get("x-device-key")?.trim() ||
      req.headers.get("X-Device-Key")?.trim() ||
      "";
    if (!deviceKey) {
      return fail(401, "missing_device_key");
    }

    let body: Record<string, unknown>;
    try {
      body = await readBody(req);
    } catch (e) {
      return fail(400, "invalid_json", e instanceof Error ? e.message : e);
    }

    // Aceita {"rssi":-45} ou {"action":"pet","rssi":-45}
    const rssiRaw = body.rssi;
    const rssi = typeof rssiRaw === "number" ? rssiRaw : Number(rssiRaw);
    if (!Number.isFinite(rssi)) {
      return fail(400, "rssi_required", { received: rssiRaw, body });
    }
    const rssiInt = Math.round(rssi);

    let sb;
    try {
      sb = makeServiceClient();
    } catch (e) {
      return fail(500, "supabase_client_init_failed", e instanceof Error ? e.message : e);
    }

    let hash: string;
    try {
      hash = await sha256Hex(deviceKey);
    } catch (e) {
      return fail(500, "hash_failed", e instanceof Error ? e.message : e);
    }

    const { data: device, error: dErr } = await sb
      .from("IotDevice")
      .select("id,userId,revokedAt")
      .eq("deviceKeyHash", hash)
      .maybeSingle();

    if (dErr) {
      return fail(500, "device_lookup_failed", dErr.message);
    }
    if (!device?.id || !device.userId) {
      return fail(401, "invalid_device");
    }
    if (device.revokedAt) {
      return fail(401, "device_revoked");
    }

    const eventId = `pev_${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
    const { error: insErr } = await sb.from("IotPresenceEvent").insert({
      id: eventId,
      deviceId: device.id,
      rssi: rssiInt,
    });
    if (insErr) {
      return fail(500, "presence_event_insert_failed", insErr.message);
    }

    const { error: updErr } = await sb
      .from("IotDevice")
      .update({ lastSeenAt: new Date().toISOString() })
      .eq("id", device.id);
    if (updErr) {
      // Não é fatal para o status do companion — loga e segue.
      console.error("[iot-presence] device lastSeen update:", updErr.message);
    }

    const status = rssiInt >= RSSI_PRESENT ? "present" : "expedition";
    const { data: companion, error: cErr } = await sb.rpc("companion_set_presence", {
      p_user_id: device.userId,
      p_status: status,
      p_rssi: rssiInt,
    });

    if (cErr) {
      return fail(500, "companion_set_presence_failed", cErr.message);
    }

    // RPC pode devolver row ou array conforme PostgREST
    const row = Array.isArray(companion) ? companion[0] : companion;

    return json({
      ok: true,
      status,
      rssi: rssiInt,
      action: typeof body.action === "string" ? body.action : undefined,
      companionId: row?.id ?? null,
      energy: row?.energy ?? null,
      affection: row?.affection ?? null,
      decayFrozen: row?.decayFrozen ?? null,
      presenceStatus: row?.presenceStatus ?? status,
    });
  } catch (e) {
    // Última linha de defesa — nunca deixar o isolate morrer sem Response.
    const msg = e instanceof Error ? e.message : String(e);
    const stack = e instanceof Error ? e.stack : undefined;
    console.error("[iot-presence] unhandled", msg, stack);
    return fail(500, "unhandled_exception", msg);
  }
});
