/**
 * Re-export do módulo da API — fonte da verdade: src/speechFilters.ts
 * Testes rodam via: npx tsx --test …
 */
export {
  isMusicTopic,
  isDesignTopic,
  isMoodBurst,
  isOffTopic,
  isFalseEvolution,
  isStaleAssistantNoise,
  acceptReply,
} from "../../src/speechFilters.ts";
