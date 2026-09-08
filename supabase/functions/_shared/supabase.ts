import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export function serviceClient(): SupabaseClient {
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

export function userClient(authHeader: string): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const anon = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  if (!url || !url.startsWith("http")) {
    throw new Error("missing_or_invalid_SUPABASE_URL");
  }
  if (!anon || anon.length < 20) {
    throw new Error("missing_or_invalid_SUPABASE_ANON_KEY");
  }
  return createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** RSSI present threshold (survivalSpec IOT_RSSI_PRESENT_THRESHOLD). */
export const RSSI_PRESENT = -75;
