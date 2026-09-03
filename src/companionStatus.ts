import { Mood } from "@prisma/client";

const MOOD_PHRASE: Record<Mood, string> = {
  EXCITED: "empolgado",
  HAPPY: "feliz",
  CONTENT: "tranquilo",
  BORED: "entediado",
  SLEEPY: "com sono",
  SAD: "triste",
  LONELY: "sentindo sua falta",
};

export function moodText(name: string, mood: Mood, _energy?: number): string {
  return `${name} está ${MOOD_PHRASE[mood] ?? "por aqui"}`;
}

export function computeAlert(name: string, mood: Mood, _energy?: number): string | undefined {
  if (mood === Mood.LONELY) return `${name} sente sua falta.`;
  return undefined;
}
