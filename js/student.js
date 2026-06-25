let currentProfile = null;
let activeLog = null;
let allWorkItems = [];

(async function init() {
  try {
    currentProfile = await P112.requireRole(['student','admin']);
    if (!currentProfile) return;
    document.getElementById('whoami').textContent = `${currentProfile.full_name} · ${currentProfile.email}`;
    const today = new Date();
    const to = new Date(Date.now() + 7 * 86400000);
    document.getElementById('fromDate').valueAsDate = today;
    document.getElementById('toDate').valueAsDate = to;
    await loadAll();
  } catch (err) {
    P112.msg('msg', err.message);
  }
})();

async function loadAll() {
  await Promise.all([loadHours(), loadWorkItems(), loadSlots(), loadMyLogs()]);
}

async function loadHours() {
  const { data, error } = await P112.db.from('p112_hour_transactions').select('hours_delta').eq('student_id', currentProfile.id);
  if (error) throw error;
  const total = (data || []).reduce((s, r) => s + Number(r.hours_delta || 0), 0);
  document.getElementById('totalHours').textContent = P112.hour(total);
}

async function loadWorkItems() {
  const { data, error } = await P112.db.from('p112_work_items').select('*, p112_work_categories(category_name)').eq('is_active', true).order('item_name');
  if (error) throw error;
  allWorkItems = data || [];
  const box = document.getElementById('workItemsBox');
  box.innerHTML = allWorkItems.map(i => `<label style="font-weight:600;color:var(--ink);"><input type="checkbox" class="work-check" value="${i.id}" style="width:auto;margin-right:8px;">${i.p112_work_categories?.category_name || ''}｜${i.item_name}<br><span class="small" style="margin-left:24px;">${i.standard || ''}</span></label>`).join('');
}

async function loadSlots() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const fromISO = new Date(`${from}T00:00:00+08:00`).toISOString();
  const toISO = new Date(`${to}T23:59:59+08:00`).toISOString();
  const { data: slots, error } = await P112.db
    .from('p112_duty_slots')
    .select('*, p112_reservations(id, student_id, reservation_type, status, p112_profiles(full_name))')
    .gte('start_at', fromISO).lte('start_at', toISO).eq('status', 'open').order('start_at');
  if (error) throw error;
  const tbody = document.getElementById('slotsBody');
  tbody.innerHTML = (slots || []).map(slot => {
    const res = (slot.p112_reservations || []).filter(r => r.status === 'reserved');
    const reg = res.find(r => r.reservation_type === 'regular');
    const st = res.find(r => r.reservation_type === 'standby');
    const mineReg = reg?.student_id === currentProfile.id;
    const mineSt = st?.student_id === currentProfile.id;
    return `<tr>
      <td>${P112.fmt(slot.start_at)}<br><span class="small">至 ${P112.fmt(slot.end_at)}</span></td>
      <td><span class="badge ok">open</span></td>
      <td>${reg ? reg.p112_profiles?.full_name || '已預約' : '<span class="small">可預約</span>'}</td>
      <td>${st ? st.p112_profiles?.full_name || '已待命' : '<span class="small">可待命</span>'}</td>
      <td>
        ${!reg ? `<button onclick="reserveSlot('${slot.id}','regular')">預約正式</button>` : mineReg ? '<span class="badge ok">我的正式</span>' : ''}
        ${!st ? `<button onclick="reserveSlot('${slot.id}','standby')">預約待命</button>` : mineSt ? '<span class="badge warn">我的待命</span>' : ''}
      </td>
    </tr>`;
  }).join('') || '<tr><td colspan="5">沒有可預約時段。</td></tr>';
}

async function reserveSlot(slotId, type) {
  const { error } = await P112.db.from('p112_reservations').insert({ slot_id: slotId, student_id: currentProfile.id, reservation_type: type });
  if (error) return P112.msg('msg', error.message);
  P112.msg('msg', type === 'regular' ? '已預約正式值班。' : '已預約待命。');
  await loadAll();
}

async function loadMyLogs() {
  const { data: reservations, error } = await P112.db
    .from('p112_reservations')
    .select('*, p112_duty_slots(start_at,end_at), p112_attendance_logs(*)')
    .eq('student_id', currentProfile.id)
    .order('created_at', { ascending: false });
  if (error) throw error;
  const openRes = (reservations || []).filter(r => r.status === 'reserved');
  document.getElementById('checkinReservation').innerHTML = openRes.map(r => `<option value="${r.id}">${P112.fmt(r.p112_duty_slots?.start_at)}｜${r.reservation_type}</option>`).join('');
  const logs = (reservations || []).flatMap(r => (r.p112_attendance_logs || []).map(l => ({...l, reservation:r})));
  activeLog = logs.find(l => l.status === 'checked_in') || null;
  document.getElementById('activeStatus').textContent = activeLog ? '已簽到' : '未簽到';
  document.getElementById('reminder').textContent = activeLog ? '您有一筆尚未簽退紀錄，離開前請完成簽退。' : '請依預約時段到場簽到。';
  document.getElementById('myLogsBody').innerHTML = (reservations || []).map(r => {
    const l = (r.p112_attendance_logs || [])[0] || {};
    return `<tr><td>${P112.fmt(r.p112_duty_slots?.start_at)}<br>${P112.fmt(r.p112_duty_slots?.end_at)}</td><td>${r.reservation_type}</td><td>${r.status}</td><td>${P112.fmt(l.checkin_time)}</td><td>${P112.fmt(l.checkout_time)}</td><td>${l.work_summary || ''}</td></tr>`;
  }).join('') || '<tr><td colspan="6">尚無紀錄。</td></tr>';
}

async function checkIn() {
  const reservationId = document.getElementById('checkinReservation').value;
  const code = document.getElementById('checkinCode').value.trim();
  if (!reservationId || !code) return P112.msg('msg', '請選擇預約紀錄並輸入現場碼。');
  const { data: verify, error: vErr } = await P112.db.rpc('p112_verify_lab_code', { p_input: code });
  if (vErr) return P112.msg('msg', vErr.message);
  const { data: res, error: rErr } = await P112.db.from('p112_reservations').select('slot_id').eq('id', reservationId).single();
  if (rErr) return P112.msg('msg', rErr.message);
  const status = verify.status || 'invalid';
  const { error } = await P112.db.from('p112_attendance_logs').insert({
    reservation_id: reservationId,
    slot_id: res.slot_id,
    student_id: currentProfile.id,
    checkin_time: new Date().toISOString(),
    checkin_code_input: code,
    checkin_code_status: status,
    checkin_user_agent: navigator.userAgent,
    abnormal_flag: !verify.valid,
    abnormal_reason: verify.valid ? null : '簽到現場碼錯誤'
  });
  if (error) return P112.msg('msg', error.message);
  P112.msg('msg', verify.valid ? '簽到完成。' : '簽到已送出，但現場碼錯誤，已標記異常。');
  document.getElementById('checkinCode').value = '';
  await loadAll();
}

async function checkOut() {
  if (!activeLog) return P112.msg('msg', '目前沒有已簽到未簽退的紀錄。');
  const code = document.getElementById('checkoutCode').value.trim();
  const workSummary = document.getElementById('workSummary').value.trim();
  const issueReport = document.getElementById('issueReport').value.trim() || '無';
  const selected = Array.from(document.querySelectorAll('.work-check:checked')).map(x => x.value);
  if (!code) return P112.msg('msg', '請輸入現場碼。');
  if (!selected.length && !workSummary) return P112.msg('msg', '請至少勾選一項工作項目或填寫摘要。');
  const { data: verify, error: vErr } = await P112.db.rpc('p112_verify_lab_code', { p_input: code });
  if (vErr) return P112.msg('msg', vErr.message);
  const checkoutTime = new Date();
  const checkinTime = new Date(activeLog.checkin_time);
  const hours = Math.max(0, (checkoutTime - checkinTime) / 3600000);
  const abnormal = activeLog.abnormal_flag || !verify.valid || hours < 0.05;
  const { error: updErr } = await P112.db.from('p112_attendance_logs').update({
    checkout_time: checkoutTime.toISOString(),
    checkout_code_input: code,
    checkout_code_status: verify.status || 'invalid',
    checkout_user_agent: navigator.userAgent,
    work_summary: workSummary,
    issue_report: issueReport,
    status: abnormal ? 'abnormal' : 'checked_out',
    abnormal_flag: abnormal,
    abnormal_reason: abnormal ? [activeLog.abnormal_reason, !verify.valid ? '簽退現場碼錯誤' : null, hours < 0.05 ? '出勤時間過短' : null].filter(Boolean).join('；') : null
  }).eq('id', activeLog.id);
  if (updErr) return P112.msg('msg', updErr.message);
  if (selected.length) {
    const rows = selected.map(work_item_id => ({ attendance_log_id: activeLog.id, work_item_id }));
    const { error: wiErr } = await P112.db.from('p112_attendance_work_items').insert(rows);
    if (wiErr) P112.msg('msg', wiErr.message);
  }
  const { error: hErr } = await P112.db.from('p112_hour_transactions').insert({
    student_id: currentProfile.id,
    attendance_log_id: activeLog.id,
    reservation_id: activeLog.reservation_id,
    slot_id: activeLog.slot_id,
    hours_delta: Number(hours.toFixed(2)),
    transaction_type: 'regular_attendance',
    reason: '學生簽退自動產生出勤時數'
  });
  if (hErr) return P112.msg('msg', hErr.message);
  await P112.db.from('p112_reservations').update({ status: 'completed' }).eq('id', activeLog.reservation_id);
  P112.msg('msg', verify.valid ? '簽退完成，已計入時數。' : '簽退完成，但現場碼錯誤，已標記異常。');
  document.getElementById('checkoutCode').value = '';
  document.getElementById('workSummary').value = '';
  document.getElementById('issueReport').value = '';
  document.querySelectorAll('.work-check').forEach(x => x.checked = false);
  await loadAll();
}
