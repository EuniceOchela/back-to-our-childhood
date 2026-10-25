import { getSupabase } from "./supabase-config.js";

const supabase = getSupabase();

export const GAME_LABELS = {
  ten_ten: "Ten-Ten",
  name_animal_place_and_thing: "Name, Animal, Place and Thing",
  ayo: "Ayo"
};

export async function createRoom(gameType, maxPlayers = 2, isPrivate = false) {
  const { data, error } = await supabase.rpc("create_room", {
    p_game_type: gameType,
    p_max_players: Number(maxPlayers),
    p_is_private: Boolean(isPrivate)
  });
  if (error) throw error;
  return data;
}

export async function joinRoom(roomCode) {
  const { data, error } = await supabase.rpc("join_room", { p_room_code: roomCode });
  if (error) throw error;
  return data;
}

export async function setReady(roomId, ready) {
  const { data, error } = await supabase.rpc("set_ready", { p_room_id: roomId, p_ready: ready });
  if (error) throw error;
  return data;
}

export async function startRoom(roomId) {
  const { data, error } = await supabase.rpc("start_room", { p_room_id: roomId });
  if (error) throw error;
  return data;
}

export async function leaveRoom(roomId) {
  const { error } = await supabase.rpc("leave_room", { p_room_id: roomId });
  if (error) throw error;
}

export async function heartbeat(roomId) {
  const { error } = await supabase.rpc("heartbeat_room", { p_room_id: roomId });
  if (error) throw error;
}

export async function getRoom(roomId) {
  const { data, error } = await supabase.from("game_rooms").select("*").eq("id", roomId).single();
  if (error) throw error;
  return data;
}

export async function getRoomPlayers(roomId) {
  const { data, error } = await supabase
    .from("room_players")
    .select("id, room_id, user_id, is_host, is_ready, score, player_status, joined_at, last_seen_at, profiles(id,display_name,avatar,username)")
    .eq("room_id", roomId)
    .neq("player_status", "left")
    .order("joined_at");
  if (error) throw error;
  return data;
}

export function buildInviteUrl(roomCode) {
  return `${window.location.origin}${window.location.pathname.replace(/\/[^/]*$/, "/")}#join=${encodeURIComponent(roomCode)}`;
}

export async function shareRoom(roomCode, gameLabel) {
  const url = buildInviteUrl(roomCode);
  const text = `Come play Nigerian childhood games with me on Back to Our Childhood! Join my ${gameLabel} game here: ${url}`;
  if (navigator.share) {
    await navigator.share({ title: "Back to Our Childhood", text, url });
    return;
  }
  await navigator.clipboard.writeText(url);
  window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, "_blank", "noopener,noreferrer");
}
