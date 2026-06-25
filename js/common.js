const P112 = {
  get db() { return window.p112Supabase; },
  fmt(dt) {
    if (!dt) return "";
    return new Date(dt).toLocaleString("zh-TW", { hour12: false });
  },
  dateOnly(dt) {
    if (!dt) return "";
    return new Date(dt).toLocaleDateString("zh-TW", { timeZone: "Asia/Taipei" });
  },
  hour(n) { return Number(n || 0).toFixed(2); },
  async getUser() {
    const { data } = await this.db.auth.getUser();
    return data.user;
  },
  async getProfile() {
    const user = await this.getUser();
    if (!user) return null;
    const { data, error } = await this.db.from("p112_profiles").select("*").eq("id", user.id).single();
    if (error) throw error;
    return data;
  },
  async requireRole(roles) {
    if (window.P112_CONFIG_ERROR) throw new Error(window.P112_CONFIG_ERROR);
    const profile = await this.getProfile();
    if (!profile || !roles.includes(profile.role)) {
      location.href = "index.html";
      return null;
    }
    return profile;
  },
  async signOut() {
    await this.db.auth.signOut();
    location.href = "index.html";
  },
  msg(id, text, type = "") {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = `notice ${type}`;
    el.textContent = text;
    el.classList.remove("hidden");
  },
  hide(id) { const el = document.getElementById(id); if (el) el.classList.add("hidden"); },
  async sha256Hex(text) {
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("");
  },
  randomToken(bytes = 32) {
    const arr = new Uint8Array(bytes);
    crypto.getRandomValues(arr);
    return Array.from(arr).map(b => b.toString(16).padStart(2, "0")).join("");
  },
  downloadCSV(filename, rows) {
    if (!rows.length) return;
    const headers = Object.keys(rows[0]);
    const esc = v => `"${String(v ?? "").replaceAll('"', '""')}"`;
    const csv = [headers.join(","), ...rows.map(r => headers.map(h => esc(r[h])).join(","))].join("\n");
    const blob = new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
    URL.revokeObjectURL(a.href);
  }
};
