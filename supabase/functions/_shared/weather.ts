/** Open-Meteo helpers for Edge (context-ingest / companion-state). */

export type WeatherCondition = "sunny" | "rainy" | "snowy" | "cloudy" | "night";

export type WeatherResult = {
  condition: WeatherCondition;
  tempC: number;
  weatherCode: number;
  latitude: number;
  longitude: number;
};

/** Toronto downtown — fallback when phone GPS unavailable. */
export const TORONTO = { latitude: 43.65, longitude: -79.38 };

export function mapWmoToCondition(code: number, localHour: number): WeatherCondition {
  // Precipitation overrides time-of-day sky.
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "snowy";
  if ([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99].includes(code)) {
    return "rainy";
  }
  const isNight = localHour < 6 || localHour >= 20;
  if (code === 0 || code === 1) return isNight ? "night" : "sunny";
  if (code === 2 || code === 3 || code === 45 || code === 48) {
    return isNight ? "night" : "cloudy";
  }
  return isNight ? "night" : "cloudy";
}

export function normalizeCondition(raw: unknown): WeatherCondition | null {
  if (typeof raw !== "string") return null;
  const v = raw.trim().toLowerCase();
  if (v === "sunny" || v === "rainy" || v === "snowy" || v === "cloudy" || v === "night") {
    return v;
  }
  return null;
}

type OpenMeteoCurrent = {
  current?: {
    temperature_2m?: number;
    weather_code?: number;
  };
};

export async function fetchOpenMeteo(
  latitude: number,
  longitude: number,
  localHour: number,
  timeoutMs = 5000,
): Promise<WeatherResult> {
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}` +
    `&current=temperature_2m,weather_code&timezone=auto`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`open_meteo_${res.status}`);
    const json = (await res.json()) as OpenMeteoCurrent;
    const temp = Number(json.current?.temperature_2m ?? 0);
    const code = Number(json.current?.weather_code ?? 0);
    return {
      condition: mapWmoToCondition(code, localHour),
      tempC: Math.round(temp),
      weatherCode: code,
      latitude,
      longitude,
    };
  } finally {
    clearTimeout(timer);
  }
}

/** Resolve weather: Open-Meteo is source of truth; device condition is fallback only. */
export async function resolveWeather(opts: {
  latitude?: number | null;
  longitude?: number | null;
  condition?: string | null;
  tempC?: number | null;
  localHour: number;
}): Promise<WeatherResult> {
  const lat =
    typeof opts.latitude === "number" && Number.isFinite(opts.latitude)
      ? opts.latitude
      : TORONTO.latitude;
  const lon =
    typeof opts.longitude === "number" && Number.isFinite(opts.longitude)
      ? opts.longitude
      : TORONTO.longitude;

  const fromDevice = normalizeCondition(opts.condition);

  try {
    // Sempre consulta Open-Meteo quando possível (chuva real em Toronto etc.).
    return await fetchOpenMeteo(lat, lon, opts.localHour);
  } catch {
    if (fromDevice) {
      return {
        condition: fromDevice,
        tempC: typeof opts.tempC === "number" && Number.isFinite(opts.tempC)
          ? Math.round(opts.tempC)
          : 10,
        weatherCode: -1,
        latitude: lat,
        longitude: lon,
      };
    }
    return {
      condition: "cloudy",
      tempC: typeof opts.tempC === "number" && Number.isFinite(opts.tempC)
        ? Math.round(opts.tempC)
        : 10,
      weatherCode: -1,
      latitude: lat,
      longitude: lon,
    };
  }
}
