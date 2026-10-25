import { getSupabase } from "./supabase-config.js";

const supabase = getSupabase();

export function subscribeToRoom(roomId, handlers = {}) {
  const channel = supabase
    .channel(`room:${roomId}`)
    .on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "game_rooms",
      filter: `id=eq.${roomId}`
    }, payload => handlers.room?.(payload))
    .on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "room_players",
      filter: `room_id=eq.${roomId}`
    }, payload => handlers.players?.(payload))
    .on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "game_sessions",
      filter: `room_id=eq.${roomId}`
    }, payload => handlers.session?.(payload))
    .subscribe(status => handlers.status?.(status));

  return () => {
    supabase.removeChannel(channel);
  };
}
