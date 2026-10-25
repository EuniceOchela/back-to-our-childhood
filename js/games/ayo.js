import { getSupabase } from "../supabase-config.js";
const supabase = getSupabase();

export async function makeAyoMove(sessionId, pitIndex) {
  const pit = Number(pitIndex);
  if (!Number.isInteger(pit) || pit < 0 || pit > 11) throw new Error("Invalid pit.");
  const { data, error } = await supabase.rpc("make_ayo_move", {
    p_session_id: sessionId,
    p_pit: pit
  });
  if (error) throw error;
  return data;
}
