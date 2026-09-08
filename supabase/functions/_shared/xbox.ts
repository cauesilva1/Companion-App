/** OpenXBL — status leve do Xbox (opcional via OPENXBL_API_KEY). */
export type XboxStatus = {
  online: boolean;
  line: string;
  title?: string;
};

export async function fetchXboxStatus(gamertag: string): Promise<XboxStatus | null> {
  const key = Deno.env.get("OPENXBL_API_KEY")?.trim();
  if (!key || !gamertag.trim()) return null;

  const tag = encodeURIComponent(gamertag.trim());
  const url = `https://xbl.io/api/v2/presence/${tag}`;
  try {
    const res = await fetch(url, {
      headers: {
        "X-Authorization": key,
        Accept: "application/json",
      },
    });
    if (!res.ok) return null;
    const data = await res.json();
    // OpenXBL shapes vary; tolerate array or object.
    const row = Array.isArray(data) ? data[0] : data;
    const state = String(row?.state ?? row?.Device?.state ?? "").toLowerCase();
    const online = state.includes("online") || state === "1" || row?.state === "Online";
    const title =
      row?.lastSeen?.titleName ||
      row?.Devices?.[0]?.titles?.[0]?.name ||
      row?.titleName ||
      undefined;
    const line = online
      ? title
        ? `online · ${title}`
        : "online no Xbox"
      : "offline no Xbox";
    return { online, line, title: title ? String(title) : undefined };
  } catch {
    return null;
  }
}
