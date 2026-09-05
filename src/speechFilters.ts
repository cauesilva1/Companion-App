/**
 * Filtros de fala — espelho de apps/ios/Shared/SpeechFilters.swift
 * e tests/companion-logic (mantidos alinhados via npm test).
 */

export function isMusicTopic(text: string | null | undefined): boolean {
  return /m[uú]sica|spotify|playlist|faixa|ouvindo|ouvir|tocando|rap\b|racionais|album|álbum|\bsom\b|track|banda|artista/i.test(
    text ?? ""
  );
}

export function isDesignTopic(text: string | null | undefined): boolean {
  return /design|arte|evoluc|evolução|evolucao|sprite|visual|desenho|forma\s*base/i.test(text ?? "");
}

export function isMoodBurst(text: string | null | undefined): boolean {
  const trimmed = (text ?? "").trim();
  if (!trimmed) return true;
  if (/^(uh+u+l*!*\s*)+$/i.test(trimmed)) return true;
  if (/modo\s*foguete|melhor\s*momento|que\s*alegria\s*!*$/i.test(trimmed)) return true;
  if (/modo foguete/i.test(trimmed)) return true;
  const words = trimmed.split(/\s+/);
  if (words.length <= 4) {
    const joined = words.map((w) => w.toLowerCase()).join(" ");
    if (/uhu+l|uhul|eba+|bo+a+|yay|woo+|foguete|alegria|empolg/i.test(joined)) return true;
  }
  return false;
}

export function isOffTopic(reply: string, user: string): boolean {
  const u = (user ?? "").trim();
  if (!u) return false;
  if (isMusicTopic(u)) return false;
  const r = (reply ?? "").toLowerCase();
  if (isMusicTopic(reply)) return true;
  if (/pra ouvir|para ouvir|sugest[aã]o do rap|curtiu.*rap|mais pra ouvir|racionais/i.test(r)) {
    return true;
  }
  if (isDesignTopic(u) && isMusicTopic(reply)) return true;
  if (
    !/uhu|foguete|por ?que.*(falou|disse)/i.test(u) &&
    /express[aã]o espont[aâ]nea|falei uhu|disse uhu|modo foguete/i.test(r)
  ) {
    return true;
  }
  return false;
}

/** Growth OFF: não inventar que já evoluiu. */
export function isFalseEvolution(reply: string, growthEnabled: boolean): boolean {
  if (growthEnabled) return false;
  const r = (reply ?? "").toLowerCase();
  return /j[aá]\s+evolu|voc[eê]\s+j[aá]\s+evolu|cresce\s+sozinho|eu\s+evolu[ií]|evolui,?\s*s[oó]|forma\s+nova|vire[i]?\s+teen|vire[i]?\s+adulto/i.test(
    r
  );
}

export function isStaleAssistantNoise(text: string): boolean {
  const t = (text ?? "").toLowerCase();
  return /express[aã]o espont[aâ]nea|sugest[aã]o do rap|modo foguete|mais pra ouvir|j[aá]\s+evolu|cresce\s+sozinho/i.test(
    t
  );
}

export function acceptReply(
  reply: string,
  user: string,
  opts: { growthEnabled?: boolean } = {}
): boolean {
  const growthEnabled = opts.growthEnabled ?? false;
  if (!reply || isMoodBurst(reply)) return false;
  if (isOffTopic(reply, user)) return false;
  if (isFalseEvolution(reply, growthEnabled)) return false;
  return true;
}
