import { getSupabase } from "./supabase-config.js";

const supabase = getSupabase();

export async function signUp({ email, password, displayName, username = "", avatar = "🧒🏾" }) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        display_name: displayName,
        username: username || null,
        avatar
      }
    }
  });
  if (error) throw error;
  return data;
}

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function sendPasswordReset(email, redirectTo = window.location.origin) {
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  if (error) throw error;
}

export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

export function onAuthChange(callback) {
  return supabase.auth.onAuthStateChange(callback);
}

export async function getProfile(userId) {
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userId)
    .single();
  if (error) throw error;
  return data;
}

export async function updateProfile(userId, patch) {
  const safe = {
    display_name: String(patch.display_name || "").trim().slice(0, 40),
    username: patch.username ? String(patch.username).trim().slice(0, 24) : null,
    avatar: String(patch.avatar || "🧒🏾").slice(0, 12)
  };
  const { data, error } = await supabase.from("profiles").update(safe).eq("id", userId).select().single();
  if (error) throw error;
  return data;
}
