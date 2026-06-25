let displayTimer = null;

(async function initDisplay() {
  if (window.P112_CONFIG_ERROR) return showDisplayMessage(window.P112_CONFIG_ERROR);
  const { data } = await P112.db.auth.getSession();
  if (data.session) {
    try {
      const profile = await P112.getProfile();
      if (profile.role === 'display' || profile.role === 'admin') {
        document.getElementById('loginBox').classList.add('hidden');
        document.getElementById('codeBox').classList.remove('hidden');
        startDisplayLoop();
      }
    } catch (e) { showDisplayMessage(e.message); }
  }
})();

function showDisplayMessage(text) {
  P112.msg('displayMsg', text);
}

async function displayLogin() {
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  const { error } = await P112.db.auth.signInWithPassword({ email, password });
  if (error) return showDisplayMessage(error.message);
  const profile = await P112.getProfile();
  if (!['display','admin'].includes(profile.role)) return showDisplayMessage('此帳號不是 display 或 admin 角色。');
  document.getElementById('loginBox').classList.add('hidden');
  document.getElementById('codeBox').classList.remove('hidden');
  startDisplayLoop();
}

function startDisplayLoop() {
  refreshDisplayCode();
  if (displayTimer) clearInterval(displayTimer);
  displayTimer = setInterval(refreshDisplayCode, 10000);
  setInterval(() => {
    document.getElementById('clock').textContent = new Date().toLocaleString('zh-TW', { hour12:false });
  }, 1000);
}

async function refreshDisplayCode() {
  const deviceId = localStorage.getItem('p112_display_device_id');
  const token = localStorage.getItem('p112_display_device_token');
  if (!deviceId || !token) {
    document.getElementById('labCode').textContent = '未授權';
    document.getElementById('deviceName').textContent = '此瀏覽器尚未註冊為看板裝置';
    document.getElementById('validRange').textContent = '-';
    document.getElementById('countdown').textContent = '-';
    return;
  }
  const { data, error } = await P112.db.rpc('p112_get_display_code', { p_device_id: deviceId, p_device_token: token });
  if (error || !data?.ok) {
    document.getElementById('labCode').textContent = '錯誤';
    document.getElementById('deviceName').textContent = error?.message || data?.error || 'unknown error';
    return;
  }
  document.getElementById('labCode').textContent = data.code;
  document.getElementById('deviceName').textContent = data.device_name || deviceId;
  document.getElementById('validRange').textContent = `${P112.fmt(data.valid_from)} – ${P112.fmt(data.valid_until)}`;
  document.getElementById('countdown').textContent = `${data.seconds_remaining} 秒`;
}
