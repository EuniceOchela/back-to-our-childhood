// ES module wrapper around the global Supabase client loaded by index.html.
export function getSupabase() {
  if (!window.BOC_SUPABASE_READY) {
    throw new Error("Supabase is not configured yet. Add your project URL and publishable key in js/supabase-config.js.");
  }
  if (!window.supabase?.createClient) {
    throw new Error("Supabase JavaScript client is not loaded.");
  }
  if (!window.__BOC_SUPABASE_CLIENT) {
    window.__BOC_SUPABASE_CLIENT = window.supabase.createClient(
      window.BOC_SUPABASE_CONFIG.url,
      window.BOC_SUPABASE_CONFIG.publishableKey
    );
  }
  return window.__BOC_SUPABASE_CLIENT;
}
