import { getSupabase } from "./supabase-config.js";

const supabase = getSupabase();

export async function getMyStats() {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return null;

  const { data, error } = await supabase
    .from("leaderboard")
    .select("*")
    .eq("user_id", user.id)
    .maybeSingle();

  if (error) throw error;
  return data || { games_played: 0, wins: 0, total_score: 0 };
}

export async function getLeaderboard(limit = 25) {
  const { data, error } = await supabase
    .from("leaderboard")
    .select("*")
    .order("wins", { ascending: false })
    .order("total_score", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}

export async function createMemory(content) {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) throw new Error("Please sign in to save a memory.");
  const clean = String(content).trim();
  if (!clean || clean.length > 500) throw new Error("Memory must be 1–500 characters.");
  const { data, error } = await supabase.from("memories").insert({
    user_id: user.id,
    content: clean,
    is_published: false
  }).select().single();
  if (error) throw error;
  return data;
}

export async function getPublishedMemories(limit = 20) {
  const { data, error } = await supabase
    .from("memories")
    .select("id,content,created_at,profiles(display_name,avatar)")
    .eq("is_published", true)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}
