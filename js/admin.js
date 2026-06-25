let adminProfile = null;
let latestHours = [];
let latestAttendance = [];

(async function initAdmin() {
  try {
    adminProfile = await P112.requireRole(['admin']);
    if (!adminProfile) return;
    document.getElementById('adminName').textContent = `${adminProfile.full_name} · ${adminProfile.email}`;
    initTabs();
    const today = new Date();
    document.getElementById('slotDate').valueAsDate = today;
    await loadAdminAll();
  } catch (err) {
    P112.msg('adminMsg', err.message);
  }
})();

function initTabs() {
  document.querySelectorAll('.tab').forEach(btn => btn.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.add('hidden'));
    btn.classList.add('active');
    document.getElementById(`tab-${btn.dataset.tab}`).classList.remove('hidden');
  }));
}

async function loadAdminAll() {
  await Promise.all([loadProfiles(), loadAdminSlots(), loadWorkAdmin(), loadAttendance(), loadDevices(), loadHours()]);
}

async function loadProfiles() {
  const { data, error } = await P112.db.from('p112_profiles').select('*').order('full_name');
  if (error) throw error;
  document.getElementById('kpiStudents').textContent = (data || []).filter(x => x.role === 'student').length;
  document.getElementById('profilesBody').innerHTML = (data || []).map(p => `<tr><td>${p.full_name}</td><td>${p.email}</td><td>${p.role}</td><td>${p.status}</td><td><code>${p.id}</code></td></tr>`).join('');
}

async function saveProfile() {
  const row = {
    id: document.getElementById('profileId').value.trim(),
    email: document.getElementById('profileEmail').value.trim(),
    full_name: document.getElementById('profileName').value.trim(),
    role: document.getElementById('profileRole').value,
    student_code: document.getElementById('profileCode').value.trim() || null,
    status: document.getElementById('profileStatus').value
  };
  if (!row.id || !row.email || !row.full_name) return P112.msg('adminMsg', 'User UUID、Email、姓名不可空白。');
  const { error } = await P112.db.from('p112_profiles').upsert(row);
  if (error) return P112.msg('adminMsg', error.message);
  P112.msg('adminMsg', 'Profile 已新增 / 更新。');
  await loadProfiles();
}

async function createSlots() {
  const p_date = document.getElementById('slotDate').value;
  const p_start_time = document.getElementById('slotStart').value;
  const p_end_time = document.getElementById('slotEnd').value;
  const p_interval_minutes = Number(document.getElementById('slotInterval').value || 30);
  const { data, error } = await P112.db.rpc('p112_create_slots', { p_date, p_start_time, p_end_time, p_interval_minutes });
  if (error) return P112.msg('adminMsg', error.message);
  P112.msg('adminMsg', `已建立 ${data} 個新時段。`);
  await loadAdminSlots();
}

async function loadAdminSlots() {
  const now = new Date();
  const end = new Date(Date.now() + 14 * 86400000);
  const { data, error } = await P112.db.from('p112_duty_slots').select('*').gte('start_at', now.toISOString()).lte('start_at', end.toISOString()).order('start_at');
  if (error) throw error;
  document.getElementById('kpiSlots').textContent = (data || []).filter(s => s.status === 'open').length;
  document.getElementById('adminSlotsBody').innerHTML = (data || []).map(s => `<tr><td>${P112.fmt(s.start_at)} – ${P112.fmt(s.end_at)}</td><td>${s.status}</td><td>${s.note || ''}</td></tr>`).join('') || '<tr><td colspan="3">尚無時段。</td></tr>';
}

async function loadWorkAdmin() {
  const { data: cats, error: cErr } = await P112.db.from('p112_work_categories').select('*').order('display_order');
  if (cErr) throw cErr;
  document.getElementById('itemCategory').innerHTML = (cats || []).map(c => `<option value="${c.id}">${c.category_name}</option>`).join('');
  const { data, error } = await P112.db.from('p112_work_items').select('*, p112_work_categories(category_name)').order('item_name');
  if (error) throw error;
  document.getElementById('workBody').innerHTML = (data || []).map(i => `<tr><td>${i.p112_work_categories?.category_name || ''}</td><td>${i.item_name}</td><td>${i.standard || ''}</td><td>${i.estimated_minutes || ''} 分</td></tr>`).join('');
}

async function saveCategory() {
  const category_name = document.getElementById('catName').value.trim();
  const description = document.getElementById('catDesc').value.trim();
  if (!category_name) return P112.msg('adminMsg', '分類名稱不可空白。');
  const { error } = await P112.db.from('p112_work_categories').insert({ category_name, description });
  if (error) return P112.msg('adminMsg', error.message);
  P112.msg('adminMsg', '已新增分類。');
  await loadWorkAdmin();
}

async function saveWorkItem() {
  const row = {
    category_id: document.getElementById('itemCategory').value,
    item_name: document.getElementById('itemName').value.trim(),
    standard: document.getElementById('itemStandard').value.trim(),
    estimated_minutes: Number(document.getElementById('itemMinutes').value || 30)
  };
  if (!row.category_id || !row.item_name) return P112.msg('adminMsg', '分類與項目名稱不可空白。');
  const { error } = await P112.db.from('p112_work_items').insert(row);
  if (error) return P112.msg('adminMsg', error.message);
  P112.msg('adminMsg', '已新增工作項目。');
  await loadWorkAdmin();
}

async function loadAttendance() {
  const { data, error } = await P112.db.from('p112_attendance_logs').select('*, p112_profiles(full_name), p112_duty_slots(start_at,end_at)').order('created_at', { ascending:false }).limit(200);
  if (error) throw error;
  latestAttendance = data || [];
  document.getElementById('kpiAbnormal').textContent = latestAttendance.filter(x => x.abnormal_flag).length;
  document.getElementById('attendanceBody').innerHTML = latestAttendance.map(l => `<tr><td>${l.p112_profiles?.full_name || ''}</td><td>${P112.fmt(l.p112_duty_slots?.start_at)}</td><td>${P112.fmt(l.checkin_time)}<br><span class="small">${l.checkin_code_status || ''}</span></td><td>${P112.fmt(l.checkout_time)}<br><span class="small">${l.checkout_code_status || ''}</span></td><td>${l.status}</td><td>${l.work_summary || ''}</td><td>${l.abnormal_reason || ''}</td></tr>`).join('') || '<tr><td colspan="7">尚無出勤紀錄。</td></tr>';
}

async function loadHours() {
  const { data, error } = await P112.db.from('p112_student_hour_summary').select('*').order('full_name');
  if (error) throw error;
  latestHours = data || [];
  document.getElementById('hoursBody').innerHTML = latestHours.map(h => `<tr><td>${h.full_name}</td><td>${h.email}</td><td>${h.student_code || ''}</td><td>${P112.hour(h.total_hours)}</td></tr>`).join('');
}

function exportHours() { P112.downloadCSV('p112_hours.csv', latestHours); }
function exportAttendance() { P112.downloadCSV('p112_attendance.csv', latestAttendance); }

async function registerDevice() {
  const device_name = document.getElementById('deviceNameInput').value.trim() || '實驗室看板機';
  const token = P112.randomToken(32);
  const hash = await P112.sha256Hex(token);
  const { data, error } = await P112.db.from('p112_lab_devices').insert({
    device_name,
    device_token_hash: hash,
    registered_by: adminProfile.id,
    user_agent: navigator.userAgent
  }).select().single();
  if (error) return P112.msg('adminMsg', error.message);
  localStorage.setItem('p112_display_device_id', data.id);
  localStorage.setItem('p112_display_device_token', token);
  P112.msg('adminMsg', `本機已註冊為看板裝置：${device_name}。請改用 display 帳號開啟 display.html。`);
  await loadDevices();
}

async function loadDevices() {
  const { data, error } = await P112.db.from('p112_lab_devices').select('*').order('created_at', { ascending:false });
  if (error) throw error;
  document.getElementById('devicesBody').innerHTML = (data || []).map(d => `<tr><td>${d.device_name}</td><td>${d.is_active ? 'active' : 'inactive'}</td><td>${P112.fmt(d.last_seen_at)}</td><td><code>${d.id}</code></td></tr>`).join('') || '<tr><td colspan="4">尚無看板裝置。</td></tr>';
}
