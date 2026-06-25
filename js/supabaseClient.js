(function () {
  if (!window.P112_CONFIG || !window.P112_CONFIG.SUPABASE_URL || !window.P112_CONFIG.SUPABASE_ANON_KEY) {
    const msg = "找不到 config.js。請將 js/config.sample.js 複製為 js/config.js，並填入 Supabase URL 與 anon key。";
    console.error(msg);
    window.P112_CONFIG_ERROR = msg;
    return;
  }
  window.p112Supabase = supabase.createClient(
    window.P112_CONFIG.SUPABASE_URL,
    window.P112_CONFIG.SUPABASE_ANON_KEY,
    { auth: { persistSession: true, autoRefreshToken: true } }
  );
})();
