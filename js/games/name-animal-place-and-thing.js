import { getSupabase } from "../supabase-config.js";
const supabase = getSupabase();

export async function submitNAPTRound(sessionId, letter, answers) {
  const clean = {
    name: String(answers?.name || "").trim().slice(0, 60),
    animal: String(answers?.animal || "").trim().slice(0, 60),
    place: String(answers?.place || "").trim().slice(0, 60),
    thing: String(answers?.thing || "").trim().slice(0, 60)
  };
  const { data, error } = await supabase.rpc("submit_game_move", {
    p_session_id: sessionId,
    p_move_type: "napt_submission",
    p_move_data: { letter: String(letter || "").slice(0, 1).toUpperCase(), answers: clean }
  });
  if (error) throw error;
  return data;
}

export async function finalizeNAPTRound(sessionId) {
  const { data, error } = await supabase.rpc("finalize_napt_round", { p_session_id: sessionId });
  if (error) throw error;
  return data;
}
