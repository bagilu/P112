/* P112 LabDuty Multi-Unit V1 shared front-end helpers */
let p112Client = null;
function p112RequireConfig(){
  if(!window.P112_CONFIG || !window.P112_CONFIG.SUPABASE_URL || !window.P112_CONFIG.SUPABASE_ANON_KEY){
    throw new Error("Missing config.js. Please copy config.sample.js to config.js and fill Supabase URL/key.");
  }
}
function p112Init(){
  p112RequireConfig();
  p112Client = supabase.createClient(window.P112_CONFIG.SUPABASE_URL, window.P112_CONFIG.SUPABASE_ANON_KEY);
  return p112Client;
}
function $(id){return document.getElementById(id)}
function p112Msg(el, text, type="notice"){
  if(!el) return; el.className = `notice ${type}`; el.textContent = text; el.classList.remove('hidden');
}
function p112FmtDate(d){ return new Date(d).toLocaleString('zh-TW',{hour12:false}); }
function p112Today(){ return new Date().toISOString().slice(0,10); }
async function p112Session(){ const {data}=await p112Client.auth.getSession(); return data.session; }
async function p112User(){ const s=await p112Session(); return s?.user || null; }
async function p112SignOut(){ await p112Client.auth.signOut(); location.href='index.html'; }
async function p112GetProfile(){
  const u=await p112User(); if(!u) return null;
  let {data,error}=await p112Client.from('p112_profiles').select('*').eq('user_id',u.id).single();
  if(error) console.warn(error); return data;
}
async function p112ListMyUnits(){
  const {data,error}=await p112Client.rpc('p112_get_my_units');
  if(error) throw error; return data || [];
}
function p112SetUnit(unitId, unitName){ localStorage.setItem('p112_unit_id',unitId); localStorage.setItem('p112_unit_name',unitName||''); }
function p112GetUnit(){ return {unit_id:localStorage.getItem('p112_unit_id'), unit_name:localStorage.getItem('p112_unit_name')}; }
function p112StatusLabel(s){
  const map={reserved:'已預約',checked_in:'已簽到',completed:'已完成',absent:'缺席',cancelled:'已取消',standby:'待命'}; return map[s]||s||'';
}
function p112CsvDownload(filename, rows){
  if(!rows?.length){ alert('沒有資料可匯出'); return; }
  const headers=Object.keys(rows[0]);
  const csv=[headers.join(',')].concat(rows.map(r=>headers.map(h=>`"${String(r[h]??'').replace(/"/g,'""')}"`).join(','))).join('\n');
  const blob=new Blob(["\ufeff"+csv],{type:'text/csv;charset=utf-8'});
  const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download=filename; a.click(); URL.revokeObjectURL(a.href);
}
