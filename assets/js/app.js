(function(){
  const cfg = window.P112_CONFIG || {};
  if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
    console.error('Missing config.js. Copy config.sample.js to config.js and fill in Supabase URL/key.');
  }
  const db = window.supabase?.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  const $ = (id)=>document.getElementById(id);
  const page = document.body.dataset.page;
  const TOKEN_KEY = 'P112_SESSION_TOKEN';
  const token = ()=>localStorage.getItem(TOKEN_KEY);
  const setToken = (t)=>localStorage.setItem(TOKEN_KEY,t);
  const clearToken = ()=>localStorage.removeItem(TOKEN_KEY);
  const msg = (id, text, danger=false)=>{ const el=$(id); if(el){el.textContent=text; el.classList.remove('hidden'); if(danger) el.classList.add('danger');}};
  async function rpc(name, args={}){
    const {data,error} = await db.rpc(name,args);
    if(error){ throw new Error(error.message || JSON.stringify(error)); }
    return data;
  }
  function todayPlus(days=0){ const d=new Date(); d.setDate(d.getDate()+days); return d.toISOString().slice(0,10); }
  async function currentUser(){ return await rpc('p112_get_current_user',{p_token:token()}); }
  async function logout(){ try{ if(token()) await rpc('p112_logout',{p_token:token()}); }catch(e){} clearToken(); location.href='index.html'; }
  function setupLogout(){ const b=$('logoutBtn'); if(b) b.onclick=logout; }

  async function loadUnits(selectId){
    const units = await rpc('p112_get_units',{p_token:token()});
    const sel=$(selectId); sel.innerHTML='';
    for(const u of units){ const opt=document.createElement('option'); opt.value=u.unit_id; opt.textContent=`${u.unit_name} (${u.role_in_unit})`; opt.dataset.photoEmail=u.photo_email||''; sel.appendChild(opt); }
    return units;
  }

  async function initLogin(){
    $('loginBtn').onclick = async()=>{
      try{
        const data = await rpc('p112_login',{p_email:$('loginEmail').value,p_password:$('loginPassword').value,p_user_agent:navigator.userAgent,p_ip:null});
        setToken(data.session_token);
        $('loginMsg').textContent='登入成功。';
        location.href = data.system_role === 'sysadmin' ? 'admin.html' : 'student.html';
      }catch(e){ $('loginMsg').textContent='登入失敗：'+e.message; }
    };
  }

  async function initStudent(){
    setupLogout();
    if(!token()){ $('authBox')?.classList.remove('hidden'); return; }
    try{
      const me=await currentUser(); $('meBox').textContent=`${me.display_name}｜${me.email}｜${me.system_role}`;
      $('slotFrom').value=todayPlus(0); $('slotTo').value=todayPlus(14);
      await loadUnits('unitSelect'); updatePhotoNotice();
      $('unitSelect').onchange=async()=>{updatePhotoNotice(); await loadWorkItems(); await loadHours(); await loadSlots(); await loadMyReservations();};
      $('loadSlotsBtn').onclick=loadSlots; $('adHocCheckinBtn').onclick=adHocCheckin; $('loadMyReservationsBtn').onclick=loadMyReservations; $('checkoutSubmitBtn').onclick=submitCheckout;
      await loadWorkItems(); await loadHours(); await loadSlots(); await loadMyReservations();
    }catch(e){ $('authBox').textContent='登入狀態無效：'+e.message; $('authBox').classList.remove('hidden'); }
  }
  function updatePhotoNotice(){
    const sel=$('unitSelect'); const email=sel?.selectedOptions?.[0]?.dataset.photoEmail;
    const el=$('unitPhotoNotice'); if(!el) return;
    if(email){ el.innerHTML=`本單位採 email 照片人工佐證。請依規定將簽到／工作照片寄至：<strong>${email}</strong><br>建議主旨：P112簽到照片｜${sel.selectedOptions[0].textContent}｜姓名｜日期時間`; el.classList.remove('hidden'); }
    else { el.textContent='本單位尚未設定照片寄送信箱。'; el.classList.remove('hidden'); }
  }
  async function loadSlots(){
    const unit=$('unitSelect').value; const rows=$('slotRows'); rows.innerHTML='';
    try{
      const data=await rpc('p112_get_slots',{p_token:token(),p_unit_id:unit,p_from:$('slotFrom').value,p_to:$('slotTo').value});
      for(const s of data){
        const tr=document.createElement('tr');
        tr.innerHTML=`<td>${s.unit_name||''}</td><td>${s.slot_date}</td><td>${s.start_time.slice(0,5)}-${s.end_time.slice(0,5)}</td><td>${s.regular_user||'<span class="muted">空</span>'}<br><span class="muted">${s.regular_count||0}/${s.regular_capacity||0}</span></td><td>${s.standby_user||'<span class="muted">空</span>'}<br><span class="muted">${s.standby_count||0}/${s.standby_capacity||0}</span></td><td></td>`;
        const td=tr.lastChild;
        const b1=document.createElement('button'); b1.textContent='預約正式'; b1.disabled=(Number(s.regular_count||0) >= Number(s.regular_capacity||0)); b1.onclick=()=>reserve(s.slot_id,'regular');
        const b2=document.createElement('button'); b2.textContent='預約待命'; b2.className='secondary'; b2.disabled=(Number(s.standby_count||0) >= Number(s.standby_capacity||0)); b2.onclick=()=>reserve(s.slot_id,'standby');
        td.append(b1,' ',b2); rows.appendChild(tr);
      }
    }catch(e){ alert(e.message); }
  }
  async function reserve(slotId,type){ try{ await rpc('p112_create_reservation',{p_token:token(),p_slot_id:slotId,p_reservation_type:type}); await loadSlots(); await loadMyReservations(); }catch(e){ alert(e.message); } }
  async function loadMyReservations(){
    const rows=$('reservationRows'); rows.innerHTML='';
    try{
      const unit=$('unitSelect')?.value || null;
      const data=await rpc('p112_get_my_reservations',{p_token:token(),p_unit_id:unit});
      for(const r of data){
        const tr=document.createElement('tr');
        tr.innerHTML=`<td>${r.unit_name}</td><td>${r.slot_date}</td><td>${r.start_time.slice(0,5)}-${r.end_time.slice(0,5)}</td><td>${r.reservation_type}</td><td>${r.status}</td><td></td>`;
        const td=tr.lastChild;
        if(r.status==='reserved'){ const b=document.createElement('button'); b.textContent='簽到'; b.onclick=()=>checkin(r.reservation_id); td.appendChild(b); }
        if(r.status==='checked_in'){ const b=document.createElement('button'); b.textContent='準備簽退'; b.className='ok'; b.onclick=()=>{$('checkoutReservationId').value=r.reservation_id; window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'});}; td.appendChild(b); }
        rows.appendChild(tr);
      }
    }catch(e){ alert(e.message); }
  }
  async function checkin(resId){
    try{ await rpc('p112_checkin',{p_token:token(),p_reservation_id:resId,p_user_agent:navigator.userAgent,p_ip:null}); alert('簽到完成。請依單位規定另寄照片 email 作為人工佐證。'); await loadMyReservations(); await loadSlots(); }
    catch(e){ alert(e.message); }
  }
  async function adHocCheckin(){
    const unit=$('unitSelect')?.value;
    if(!unit){ alert('請先選擇單位。'); return; }
    if(!confirm('確定要使用「未預約臨時簽到」？系統會建立目前半小時時段的臨時出勤紀錄，並標記給管理者確認。')) return;
    try{ await rpc('p112_ad_hoc_checkin',{p_token:token(),p_unit_id:unit,p_user_agent:navigator.userAgent,p_ip:null}); alert('臨時簽到完成。請依單位規定另寄照片 email 作為人工佐證。'); await loadSlots(); await loadMyReservations(); }
    catch(e){ alert(e.message); }
  }
  async function loadWorkItems(){
    const box=$('workItemsBox'); if(!box) return; box.innerHTML='';
    try{ const data=await rpc('p112_get_work_items',{p_token:token(),p_unit_id:$('unitSelect').value});
      for(const item of data){ const label=document.createElement('label'); label.className='card small'; label.innerHTML=`<input type="checkbox" class="workItemChk" value="${item.item_id}" style="width:auto;margin-right:8px"> <strong>${item.category_name}｜${item.item_name}</strong><br><span class="muted">${item.standard||''}</span>`; box.appendChild(label); }
    }catch(e){ box.innerHTML='<p class="muted">尚無工作項目，或無法讀取。</p>'; }
  }
  async function submitCheckout(){
    const ids=[...document.querySelectorAll('.workItemChk:checked')].map(x=>x.value);
    try{ const data=await rpc('p112_checkout',{p_token:token(),p_reservation_id:$('checkoutReservationId').value,p_work_summary:$('workSummary').value,p_abnormal_note:$('abnormalNote').value,p_work_item_ids:ids,p_user_agent:navigator.userAgent,p_ip:null}); $('studentMsg').textContent=`簽退完成，計入 ${data.hours_delta} 小時。`; await loadMyReservations(); await loadHours(); await loadSlots(); }
    catch(e){ $('studentMsg').textContent='簽退失敗：'+e.message; }
  }
  async function loadHours(){
    try{ const data=await rpc('p112_get_hour_summary',{p_token:token(),p_unit_id:$('unitSelect')?.value || null}); const total=data.reduce((a,b)=>a+Number(b.total_hours||0),0); if($('hourBox')) $('hourBox').textContent=total.toFixed(2)+' 小時'; }
    catch(e){ if($('hourBox')) $('hourBox').textContent='--'; }
  }

  async function initAdmin(){
    setupLogout(); if(!token()){ location.href='index.html'; return; }
    try{
      const me=await currentUser(); $('meBox').textContent=`${me.display_name}｜${me.email}｜${me.system_role}`;
      await loadUnits('adminUnitSelect'); await loadUsers();
      $('createUnitBtn').onclick=createUnit; $('createUserBtn').onclick=createUser; $('loadUsersBtn').onclick=loadUsers; $('addMemberBtn').onclick=addMember; $('createSlotBtn').onclick=createSlot; $('addCategoryBtn').onclick=addCategory; $('addWorkItemBtn').onclick=addWorkItem; $('loadHoursBtn').onclick=loadAdminHours;
    }catch(e){ msg('adminMsg','管理端初始化失敗：'+e.message,true); }
  }
  async function createUnit(){ try{ await rpc('p112_create_unit',{p_token:token(),p_unit_name:$('newUnitName').value,p_unit_type:$('newUnitType').value,p_description:null,p_contact_email:null,p_photo_email:$('newUnitPhotoEmail').value}); msg('adminMsg','單位建立完成。'); await loadUnits('adminUnitSelect'); }catch(e){ msg('adminMsg',e.message,true); } }
  async function createUser(){ try{ await rpc('p112_admin_create_user',{p_token:token(),p_email:$('newUserEmail').value,p_display_name:$('newUserName').value,p_password:$('newUserPassword').value,p_system_role:$('newUserRole').value,p_must_change_password:true}); msg('adminMsg','使用者建立完成。'); await loadUsers(); }catch(e){ msg('adminMsg',e.message,true); } }
  async function loadUsers(){
    try{ const data=await rpc('p112_list_users',{p_token:token()}); const rows=$('userRows'); const sel=$('memberUserSelect'); rows.innerHTML=''; sel.innerHTML='';
      for(const u of data){ rows.insertAdjacentHTML('beforeend',`<tr><td>${u.display_name}</td><td>${u.email}</td><td>${u.system_role}</td><td>${u.is_active}</td><td class="small">${u.user_id}</td></tr>`); const opt=document.createElement('option'); opt.value=u.user_id; opt.textContent=`${u.display_name}｜${u.email}`; sel.appendChild(opt); }
    }catch(e){ msg('adminMsg','讀取使用者失敗：'+e.message,true); }
  }
  async function addMember(){ try{ await rpc('p112_add_unit_member',{p_token:token(),p_unit_id:$('adminUnitSelect').value,p_user_id:$('memberUserSelect').value,p_unit_role:$('memberRole').value}); msg('adminMsg','已加入單位成員。'); }catch(e){ msg('adminMsg',e.message,true); } }
  async function createSlot(){ try{ await rpc('p112_create_duty_slot',{p_token:token(),p_unit_id:$('adminUnitSelect').value,p_slot_date:$('slotDate').value,p_start_time:$('slotStart').value,p_end_time:$('slotEnd').value,p_note:$('slotNote').value,p_regular_capacity:Number($('regularCapacity').value||1),p_standby_capacity:Number($('standbyCapacity').value||0)}); msg('adminMsg','時段建立完成。'); }catch(e){ msg('adminMsg',e.message,true); } }
  async function addCategory(){ try{ const r=await rpc('p112_admin_add_work_category',{p_token:token(),p_unit_id:$('adminUnitSelect').value,p_category_name:$('categoryName').value,p_description:null}); $('categoryId').value=r.category_id; msg('adminMsg','分類建立完成，已填入 category_id。'); }catch(e){ msg('adminMsg',e.message,true); } }
  async function addWorkItem(){ try{ await rpc('p112_admin_add_work_item',{p_token:token(),p_unit_id:$('adminUnitSelect').value,p_category_id:$('categoryId').value||null,p_item_name:$('workItemName').value,p_standard:$('workItemStandard').value}); msg('adminMsg','工作項目建立完成。'); }catch(e){ msg('adminMsg',e.message,true); } }
  async function loadAdminHours(){ try{ const data=await rpc('p112_get_hour_summary',{p_token:token(),p_unit_id:$('adminUnitSelect').value}); const rows=$('hourRows'); rows.innerHTML=''; for(const h of data){ rows.insertAdjacentHTML('beforeend',`<tr><td>${h.unit_name}</td><td>${h.display_name}</td><td>${h.total_hours}</td></tr>`); }}catch(e){ msg('adminMsg',e.message,true); } }

  if(page==='login') initLogin();
  if(page==='student') initStudent();
  if(page==='admin') initAdmin();
})();
