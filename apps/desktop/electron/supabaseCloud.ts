import { createClient, type SupabaseClient, type Session } from "@supabase/supabase-js";

export type CloudCompanion = {
  id: string;
  userId: string;
  name: string;
  personality: string;
  skin: string;
  archetype: string;
  mood: string;
  energy: number;
  affection: number;
};

let client: SupabaseClient | null = null;
let session: Session | null = null;

export function configureSupabase(url: string, anonKey: string) {
  if (!url || !anonKey) {
    client = null;
    return;
  }
  client = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: true },
  });
}

export function getSupabase() {
  return client;
}

export function getSession() {
  return session;
}

export async function signIn(email: string, password: string) {
  if (!client) throw new Error("Configure SUPABASE_URL e anon key");
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  session = data.session;
  if (session?.user) {
    await client.from("Profile").upsert({
      id: session.user.id,
      email: session.user.email ?? email,
    });
  }
  return session;
}

export async function signUp(email: string, password: string) {
  if (!client) throw new Error("Configure SUPABASE_URL e anon key");
  const { data, error } = await client.auth.signUp({ email, password });
  if (error) throw error;
  session = data.session;
  if (!session) {
    // email confirm may be on — try sign-in
    return signIn(email, password);
  }
  if (session.user) {
    await client.from("Profile").upsert({
      id: session.user.id,
      email: session.user.email ?? email,
    });
  }
  return session;
}

export async function signOut() {
  if (client) await client.auth.signOut();
  session = null;
}

export async function fetchMyCompanion(): Promise<CloudCompanion | null> {
  if (!client || !session?.user) return null;
  const { data, error } = await client
    .from("Companion")
    .select("*")
    .eq("userId", session.user.id)
    .order("createdAt", { ascending: true })
    .limit(1);
  if (error) throw error;
  return (data?.[0] as CloudCompanion) ?? null;
}

export async function upsertCompanion(body: {
  id?: string;
  name: string;
  personality: string;
  skin: string;
  archetype: string;
  mood?: string;
  energy?: number;
  affection?: number;
}): Promise<CloudCompanion> {
  if (!client || !session?.user) throw new Error("Faça login");
  const existing = await fetchMyCompanion();
  if (existing) {
    const { data, error } = await client
      .from("Companion")
      .update({
        name: body.name,
        personality: body.personality,
        skin: body.skin,
        archetype: body.archetype,
        mood: body.mood ?? existing.mood,
        energy: body.energy ?? existing.energy,
        affection: body.affection ?? existing.affection,
      })
      .eq("id", existing.id)
      .select()
      .single();
    if (error) throw error;
    return data as CloudCompanion;
  }
  const id = body.id ?? `cmp_${Date.now().toString(36)}`;
  const { data, error } = await client
    .from("Companion")
    .insert({
      id,
      userId: session.user.id,
      name: body.name,
      personality: body.personality,
      skin: body.skin,
      artStyle: "pixel",
      backdrop: "sky",
      archetype: body.archetype,
      mood: body.mood ?? "HAPPY",
      energy: body.energy ?? 80,
      affection: body.affection ?? 55,
      memoryNotes: [],
    })
    .select()
    .single();
  if (error) throw error;
  return data as CloudCompanion;
}

export async function pushCompanionState(patch: {
  id: string;
  name?: string;
  skin?: string;
  archetype?: string;
  mood?: string;
  energy?: number;
  affection?: number;
}) {
  if (!client || !session?.user) return;
  const { error } = await client
    .from("Companion")
    .update({
      name: patch.name,
      skin: patch.skin,
      archetype: patch.archetype,
      mood: patch.mood,
      energy: patch.energy,
      affection: patch.affection,
      personality: patch.archetype,
    })
    .eq("id", patch.id);
  if (error) throw error;
}

export type CloudMission = {
  id: string;
  userId: string;
  dayKey: string;
  kind: string;
  title: string;
  description: string;
  target: number;
  progress: number;
  rewardEnergy: number;
  rewardAffection: number;
  claimed: boolean;
};

export async function syncMissions(
  missions: Array<{
    id: string;
    kind: string;
    title: string;
    description: string;
    target: number;
    progress: number;
    rewardEnergy: number;
    rewardAffection: number;
    claimed: boolean;
  }>,
  day: string
): Promise<CloudMission[]> {
  if (!client || !session?.user) return [];
  const userId = session.user.id;
  const { data: remoteRows, error: fetchErr } = await client
    .from("UserMissionProgress")
    .select("*")
    .eq("userId", userId)
    .eq("dayKey", day);
  if (fetchErr) throw fetchErr;
  let remote = (remoteRows ?? []) as CloudMission[];

  if (remote.length === 0) {
    for (const m of missions) {
      const id = `msn_${day}_${m.kind}_${userId.slice(0, 8)}`;
      const { error } = await client.from("UserMissionProgress").insert({
        id,
        userId,
        dayKey: day,
        kind: m.kind,
        title: m.title,
        description: m.description,
        target: m.target,
        progress: m.progress,
        rewardEnergy: m.rewardEnergy,
        rewardAffection: m.rewardAffection,
        claimed: m.claimed,
      });
      if (error) throw error;
    }
    const { data } = await client
      .from("UserMissionProgress")
      .select("*")
      .eq("userId", userId)
      .eq("dayKey", day);
    return (data ?? []) as CloudMission[];
  }

  for (const m of missions) {
    const hit = remote.find((r) => r.kind === m.kind);
    if (!hit) continue;
    const progress = Math.max(hit.progress, m.progress);
    const claimed = hit.claimed || m.claimed;
    if (progress !== hit.progress || claimed !== hit.claimed) {
      const { error } = await client
        .from("UserMissionProgress")
        .update({ progress, claimed })
        .eq("id", hit.id);
      if (error) throw error;
    }
  }

  const { data } = await client
    .from("UserMissionProgress")
    .select("*")
    .eq("userId", userId)
    .eq("dayKey", day);
  return (data ?? []) as CloudMission[];
}
