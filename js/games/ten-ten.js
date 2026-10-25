import { getSupabase } from "../supabase-config.js";
const supabase = getSupabase();

export async function submitTenTenAction(sessionId, action) {
  const allowed = ["success", "failure", "challenge_complete"];
  if (!allowed.includes(action)) throw new Error("Invalid Ten-Ten action.");
  const { data, error } = await supabase.rpc("submit_game_move", {
    p_session_id: sessionId,
    p_move_type: "ten_ten_action",
    p_move_data: { action }
  });
  if (error) throw error;
  return data;
}
