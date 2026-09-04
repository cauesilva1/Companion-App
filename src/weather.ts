export type WeatherSnapshot = {
  city: string;
  region: string;
  country: string;
  latitude: number;
  longitude: number;
  tempC: number;
  feelsLikeC?: number;
  humidity?: number;
  weatherCode: number;
  description: string;
  fetchedAt: number;
};

let cache: WeatherSnapshot | null = null;
const CACHE_MS = 10 * 60_000;

const WMO: Record<number, string> = {
  0: "céu limpo",
  1: "principalmente limpo",
  2: "parcialmente nublado",
  3: "nublado",
  45: "neblina",
  48: "neblina gelada",
  51: "garoa fraca",
  53: "garoa",
  55: "garoa forte",
  61: "chuva fraca",
  63: "chuva",
  65: "chuva forte",
  71: "neve fraca",
  73: "neve",
  75: "neve forte",
  80: "pancadas fracas",
  81: "pancadas",
  82: "pancadas fortes",
  95: "trovoada",
  96: "trovoada com granizo",
  99: "trovoada forte",
};

export function isWeatherQuestion(message: string): boolean {
  const m = message.toLowerCase();
  return /(temperatura|tempo|clima|graus|°\s*c|faz\s+calor|faz\s+frio|chove|chuva|umidade|como\s+est[aá]\s+o\s+tempo|weather)/i.test(
    m
  );
}

function describeCode(code: number): string {
  return WMO[code] ?? "tempo indefinido";
}

async function fetchJson<T>(url: string, timeoutMs = 6000): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return (await res.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}

async function resolveLocation(): Promise<{
  city: string;
  region: string;
  country: string;
  latitude: number;
  longitude: number;
}> {
  // 1) geojs (rápido, sem chave)
  try {
    const geo = await fetchJson<{
      city?: string;
      region?: string;
      country?: string;
      latitude?: string;
      longitude?: string;
    }>("https://get.geojs.io/v1/ip/geo.json");
    const latitude = Number(geo.latitude);
    const longitude = Number(geo.longitude);
    if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
      return {
        city: geo.city || "sua região",
        region: geo.region || "",
        country: geo.country || "",
        latitude,
        longitude,
      };
    }
  } catch {
    /* try next */
  }

  // 2) ipapi.co fallback
  const ipapi = await fetchJson<{
    city?: string;
    region?: string;
    country_name?: string;
    latitude?: number;
    longitude?: number;
  }>("https://ipapi.co/json/");
  const latitude = Number(ipapi.latitude);
  const longitude = Number(ipapi.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error("Não consegui obter localização");
  }
  return {
    city: ipapi.city || "sua região",
    region: ipapi.region || "",
    country: ipapi.country_name || "",
    latitude,
    longitude,
  };
}

export async function getWeatherSnapshot(force = false): Promise<WeatherSnapshot> {
  if (!force && cache && Date.now() - cache.fetchedAt < CACHE_MS) return cache;

  const loc = await resolveLocation();
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${loc.latitude}` +
    `&longitude=${loc.longitude}` +
    `&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code` +
    `&timezone=auto`;

  const data = await fetchJson<{
    current?: {
      temperature_2m?: number;
      apparent_temperature?: number;
      relative_humidity_2m?: number;
      weather_code?: number;
    };
  }>(url);

  const cur = data.current;
  if (!cur || typeof cur.temperature_2m !== "number") {
    throw new Error("Clima indisponível");
  }

  const weatherCode = Number(cur.weather_code ?? 0);
  cache = {
    city: loc.city,
    region: loc.region,
    country: loc.country,
    latitude: loc.latitude,
    longitude: loc.longitude,
    tempC: Math.round(cur.temperature_2m),
    feelsLikeC:
      typeof cur.apparent_temperature === "number"
        ? Math.round(cur.apparent_temperature)
        : undefined,
    humidity:
      typeof cur.relative_humidity_2m === "number"
        ? Math.round(cur.relative_humidity_2m)
        : undefined,
    weatherCode,
    description: describeCode(weatherCode),
    fetchedAt: Date.now(),
  };
  return cache;
}

export function weatherContextLine(w: WeatherSnapshot): string {
  const place = [w.city, w.region].filter(Boolean).join(", ");
  const feels =
    w.feelsLikeC != null && w.feelsLikeC !== w.tempC
      ? `, sensação ${w.feelsLikeC}°C`
      : "";
  const hum = w.humidity != null ? `, umidade ${w.humidity}%` : "";
  return `Clima REAL agora em ${place}: ${w.tempC}°C${feels}, ${w.description}${hum}. Cite a cidade (${w.city}) e a temperatura ${w.tempC}°C na fala. Nao invente graus.`;
}

export function weatherSpokenLine(w: WeatherSnapshot, archetype = "curioso"): string {
  const place = w.city || "aqui";
  const lines: Record<string, string[]> = {
    preguicoso: [
      `Aqui em ${place} tá ${w.tempC}°C… ${w.description}. Sem sair da cama.`,
      `${w.tempC}°C em ${place}. Quente demais pra eu me mexer.`,
    ],
    carinhoso: [
      `Em ${place} tá ${w.tempC}°C, ${w.description}. Cuida de você!`,
      `Olha: ${w.tempC}°C agora em ${place}.`,
    ],
    zoeiro: [
      `${w.tempC}°C em ${place}! ${w.description}. Não inventei, consultei!`,
      `Temperatura oficial: ${w.tempC}°C em ${place}.`,
    ],
    misterioso: [
      `Os sinais dizem ${w.tempC}°C em ${place}… ${w.description}.`,
      `Em ${place}, o ar marca ${w.tempC}°C.`,
    ],
    curioso: [
      `Pelo mapa: ${w.tempC}°C em ${place}, ${w.description}!`,
      `Agora em ${place}: ${w.tempC}°C e ${w.description}.`,
    ],
  };
  const pool = lines[archetype] ?? lines.curioso;
  return pool[Math.floor(Math.random() * pool.length)];
}
