/** OpenXBL — status leve do Xbox (opcional via OPENXBL_API_KEY). */
export type XboxStatus = {
  online: boolean;
  line: string;
  title?: string;
};

function pickTitle(row: Record<string, unknown>): string | undefined {
  const lastSeen = row.lastSeen as Record<string, unknown> | undefined;
  if (lastSeen?.titleName) return String(lastSeen.titleName);

  const devices = row.devices as Array<Record<string, unknown>> | undefined
    ?? row.Devices as Array<Record<string, unknown>> | undefined;
  const titles = devices?.[0]?.titles as Array<Record<string, unknown>> | undefined
    ?? devices?.[0]?.Titles as Array<Record<string, unknown>> | undefined;
  const active = titles?.find((t) => t.placement === "Full" || t.Placement === "Full") ?? titles?.[0];
  if (active?.name) return String(active.name);
  if (active?.Name) return String(active.Name);

  if (row.titleName) return String(row.titleName);
  return undefined;
}

function isOnline(row: Record<string, unknown>): boolean {
  const state = String(row.state ?? row.State ?? "").toLowerCase();
  if (state.includes("online")) return true;
  if (state === "1") return true;
  const devices = row.devices as unknown[] | undefined ?? row.Devices as unknown[] | undefined;
  return Array.isArray(devices) && devices.length > 0 && state !== "offline";
}

export async function fetchXboxStatus(gamertag: string): Promise<XboxStatus | null> {
  const key = Deno.env.get("OPENXBL_API_KEY")?.trim();
  if (!key || !gamertag.trim()) return null;

  const tag = encodeURIComponent(gamertag.trim());
  // Prefer presence; fallback account search not required for status line
  const urls = [
    `https://xbl.io/api/v2/presence/${tag}`,
    `https://xbl.io/api/v2/account/${tag}`,
  ];

  for (const url of urls) {
    try {
      const res = await fetch(url, {
        headers: {
          "X-Authorization": key,
          Accept: "application/json",
          "Accept-Language": "en-US",
        },
      });
      if (!res.ok) continue;
      const data = await res.json();
      const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown>;
      if (!row || typeof row !== "object") continue;

      const online = isOnline(row);
      const title = pickTitle(row);
      const line = online
        ? title
          ? `online · ${title}`
          : "online no Xbox"
        : title
          ? `offline · último: ${title}`
          : "offline no Xbox";
      return { online, line, title };
    } catch {
      // try next URL
    }
  }
  return null;
}
