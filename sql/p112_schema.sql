-- P112 我來值班 / LabDuty MVP
-- Supabase SQL Editor 一次貼上執行。
-- 注意：請先在 Supabase Dashboard 建立 Auth 使用者，再於 p112_profiles 建立對應角色。

create extension if not exists pgcrypto;

-- ---------- helper ----------
create or replace function public.p112_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- core tables ----------
create table if not exists public.p112_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null,
  role text not null check (role in ('student','admin','display')) default 'student',
  status text not null check (status in ('active','inactive')) default 'active',
  student_code text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_p112_profiles_updated_at on public.p112_profiles;
create trigger trg_p112_profiles_updated_at before update on public.p112_profiles
for each row execute function public.p112_touch_updated_at();

create table if not exists public.p112_settings (
  setting_key text primary key,
  setting_value text not null,
  note text,
  updated_at timestamptz not null default now()
);

insert into public.p112_settings(setting_key, setting_value, note)
values ('lab_code_secret', encode(gen_random_bytes(32), 'hex'), 'P112 現場動態碼秘密值，請勿提供給學生。')
on conflict (setting_key) do nothing;

create table if not exists public.p112_duty_slots (
  id uuid primary key default gen_random_uuid(),
  slot_date date not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  max_regular int not null default 1,
  max_standby int not null default 1,
  status text not null check (status in ('open','closed','cancelled')) default 'open',
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint p112_slot_time_check check (end_at > start_at),
  constraint p112_slot_unique unique (start_at, end_at)
);

drop trigger if exists trg_p112_duty_slots_updated_at on public.p112_duty_slots;
create trigger trg_p112_duty_slots_updated_at before update on public.p112_duty_slots
for each row execute function public.p112_touch_updated_at();

create table if not exists public.p112_reservations (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.p112_duty_slots(id) on delete cascade,
  student_id uuid not null references public.p112_profiles(id) on delete cascade,
  reservation_type text not null check (reservation_type in ('regular','standby')),
  status text not null check (status in ('reserved','cancelled','completed','absent','replaced')) default 'reserved',
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  note text
);

create unique index if not exists p112_one_regular_per_slot
on public.p112_reservations(slot_id)
where reservation_type = 'regular' and status = 'reserved';

create unique index if not exists p112_one_standby_per_slot
on public.p112_reservations(slot_id)
where reservation_type = 'standby' and status = 'reserved';

create unique index if not exists p112_one_reservation_per_student_slot_type
on public.p112_reservations(slot_id, student_id, reservation_type)
where status = 'reserved';

create table if not exists public.p112_attendance_logs (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid references public.p112_reservations(id) on delete set null,
  slot_id uuid references public.p112_duty_slots(id) on delete set null,
  student_id uuid not null references public.p112_profiles(id) on delete cascade,
  checkin_time timestamptz,
  checkout_time timestamptz,
  checkin_code_input text,
  checkin_code_status text check (checkin_code_status in ('valid_current','valid_previous','valid_next','invalid','manual','not_checked')),
  checkout_code_input text,
  checkout_code_status text check (checkout_code_status in ('valid_current','valid_previous','valid_next','invalid','manual','not_checked')),
  checkin_ip text,
  checkout_ip text,
  checkin_user_agent text,
  checkout_user_agent text,
  work_summary text,
  issue_report text,
  status text not null check (status in ('checked_in','checked_out','abnormal','void')) default 'checked_in',
  abnormal_flag boolean not null default false,
  abnormal_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_p112_attendance_logs_updated_at on public.p112_attendance_logs;
create trigger trg_p112_attendance_logs_updated_at before update on public.p112_attendance_logs
for each row execute function public.p112_touch_updated_at();

create table if not exists public.p112_work_categories (
  id uuid primary key default gen_random_uuid(),
  category_name text not null,
  description text,
  display_order int not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_p112_work_categories_updated_at on public.p112_work_categories;
create trigger trg_p112_work_categories_updated_at before update on public.p112_work_categories
for each row execute function public.p112_touch_updated_at();

create table if not exists public.p112_work_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.p112_work_categories(id) on delete cascade,
  item_name text not null,
  standard text,
  estimated_minutes int default 30,
  is_required boolean not null default false,
  requires_approval boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_p112_work_items_updated_at on public.p112_work_items;
create trigger trg_p112_work_items_updated_at before update on public.p112_work_items
for each row execute function public.p112_touch_updated_at();

create table if not exists public.p112_attendance_work_items (
  id uuid primary key default gen_random_uuid(),
  attendance_log_id uuid not null references public.p112_attendance_logs(id) on delete cascade,
  work_item_id uuid not null references public.p112_work_items(id) on delete restrict,
  note text,
  completed boolean not null default true,
  created_at timestamptz not null default now(),
  unique(attendance_log_id, work_item_id)
);

create table if not exists public.p112_hour_transactions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.p112_profiles(id) on delete cascade,
  attendance_log_id uuid references public.p112_attendance_logs(id) on delete set null,
  reservation_id uuid references public.p112_reservations(id) on delete set null,
  slot_id uuid references public.p112_duty_slots(id) on delete set null,
  hours_delta numeric(8,2) not null,
  transaction_type text not null check (transaction_type in ('regular_attendance','standby_credit','standby_replacement','manual_adjustment','absence_penalty','correction')),
  reason text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.p112_lab_devices (
  id uuid primary key default gen_random_uuid(),
  device_name text not null,
  device_token_hash text not null,
  role text not null default 'display' check (role = 'display'),
  is_active boolean not null default true,
  registered_by uuid references auth.users(id),
  last_seen_at timestamptz,
  last_ip text,
  user_agent text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_p112_lab_devices_updated_at on public.p112_lab_devices;
create trigger trg_p112_lab_devices_updated_at before update on public.p112_lab_devices
for each row execute function public.p112_touch_updated_at();

-- ---------- seed work items ----------
insert into public.p112_work_categories(category_name, description, display_order) values
('環境整理', '打掃、桌面、白板、垃圾、物品歸位。', 10),
('設備檢查', '公共電腦、螢幕、網路、展示設備、麥克風與線材。', 20),
('展示維護', '專案展示頁面、QR Code、海報與實驗室展示資訊。', 30),
('專案協助', 'P101–P112 等專案測試、資料整理與記錄。', 40),
('老師指定任務', '老師或管理者臨時交辦之工作。', 50)
on conflict do nothing;

insert into public.p112_work_items(category_id, item_name, standard, estimated_minutes)
select c.id, x.item_name, x.standard, x.estimated_minutes
from public.p112_work_categories c
join (values
('環境整理','桌面整理','桌面無垃圾、紙杯、食物包裝；公共物品歸位。',30),
('環境整理','白板整理','保留指定內容，其餘擦除；白板筆與板擦歸位。',15),
('環境整理','垃圾與回收檢查','垃圾桶滿 80% 以上需打包；回收物分類放置。',15),
('設備檢查','公共電腦與螢幕檢查','確認展示電腦與螢幕可正常顯示，無錯誤畫面。',30),
('設備檢查','網路連線檢查','確認實驗室主要展示頁面可開啟。',15),
('展示維護','專案展示頁面確認','確認指定專案頁面可正常顯示，QR Code 可掃描。',30),
('專案協助','專案資料整理','依指定專案整理測試紀錄、表格或文字資料。',30),
('老師指定任務','老師指定任務','依老師或管理者指定內容執行，需於摘要中說明。',30)
) as x(category_name, item_name, standard, estimated_minutes)
on c.category_name = x.category_name
where not exists (select 1 from public.p112_work_items wi where wi.category_id = c.id and wi.item_name = x.item_name);

-- ---------- functions ----------
create or replace function public.p112_current_role()
returns text
language sql
security definer
set search_path = public
as $$
  select role from public.p112_profiles where id = auth.uid() and status = 'active';
$$;

create or replace function public.p112_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(public.p112_current_role() = 'admin', false);
$$;

create or replace function public.p112_lab_code_bucket(p_time timestamptz default now())
returns timestamptz
language sql
stable
as $$
  select to_timestamp(floor(extract(epoch from p_time) / 300) * 300)::timestamptz;
$$;

create or replace function public.p112_generate_lab_code(p_bucket timestamptz default public.p112_lab_code_bucket(now()))
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  secret text;
  hx text;
  n bigint;
begin
  select setting_value into secret from public.p112_settings where setting_key = 'lab_code_secret';
  if secret is null then
    raise exception 'P112 lab_code_secret not found';
  end if;
  hx := encode(digest(secret || '|' || to_char(p_bucket at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'sha256'), 'hex');
  n := ('x' || substr(hx, 1, 8))::bit(32)::bigint;
  return lpad((n % 1000000)::text, 6, '0');
end;
$$;

create or replace function public.p112_verify_lab_code(p_input text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cleaned text := regexp_replace(coalesce(p_input,''), '\\D', '', 'g');
  b timestamptz := public.p112_lab_code_bucket(now());
  c_prev text := public.p112_generate_lab_code(b - interval '5 minutes');
  c_now text := public.p112_generate_lab_code(b);
  c_next text := public.p112_generate_lab_code(b + interval '5 minutes');
  status text := 'invalid';
begin
  if cleaned = c_now then status := 'valid_current';
  elsif cleaned = c_prev then status := 'valid_previous';
  elsif cleaned = c_next then status := 'valid_next';
  end if;
  return jsonb_build_object(
    'valid', status <> 'invalid',
    'status', status,
    'bucket_start', b,
    'bucket_end', b + interval '5 minutes'
  );
end;
$$;

create or replace function public.p112_get_display_code(p_device_id uuid, p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  token_hash text := encode(digest(coalesce(p_device_token,''), 'sha256'), 'hex');
  dev public.p112_lab_devices%rowtype;
  b timestamptz := public.p112_lab_code_bucket(now());
  code text;
  sec_remaining int;
begin
  select * into dev
  from public.p112_lab_devices
  where id = p_device_id
    and device_token_hash = token_hash
    and is_active = true;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'device_not_authorized');
  end if;

  update public.p112_lab_devices
  set last_seen_at = now(), updated_at = now()
  where id = p_device_id;

  code := public.p112_generate_lab_code(b);
  sec_remaining := greatest(0, extract(epoch from ((b + interval '5 minutes') - now()))::int);

  return jsonb_build_object(
    'ok', true,
    'code', code,
    'valid_from', b,
    'valid_until', b + interval '5 minutes',
    'seconds_remaining', sec_remaining,
    'device_name', dev.device_name
  );
end;
$$;

create or replace view public.p112_student_hour_summary as
select
  p.id as student_id,
  p.full_name,
  p.email,
  p.student_code,
  coalesce(sum(h.hours_delta), 0)::numeric(8,2) as total_hours
from public.p112_profiles p
left join public.p112_hour_transactions h on h.student_id = p.id
where p.role = 'student'
group by p.id, p.full_name, p.email, p.student_code;

create or replace function public.p112_create_slots(
  p_date date,
  p_start_time time,
  p_end_time time,
  p_interval_minutes int default 30
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  current_start timestamptz;
  current_end timestamptz;
  final_end timestamptz;
  created_count int := 0;
begin
  if not public.p112_is_admin() then
    raise exception 'Only admin can create slots';
  end if;
  current_start := (p_date::text || ' ' || p_start_time::text || '+08')::timestamptz;
  final_end := (p_date::text || ' ' || p_end_time::text || '+08')::timestamptz;
  while current_start < final_end loop
    current_end := current_start + make_interval(mins => p_interval_minutes);
    insert into public.p112_duty_slots(slot_date, start_at, end_at, created_by)
    values (p_date, current_start, current_end, auth.uid())
    on conflict (start_at, end_at) do nothing;
    if found then created_count := created_count + 1; end if;
    current_start := current_end;
  end loop;
  return created_count;
end;
$$;

-- ---------- RLS ----------
alter table public.p112_profiles enable row level security;
alter table public.p112_settings enable row level security;
alter table public.p112_duty_slots enable row level security;
alter table public.p112_reservations enable row level security;
alter table public.p112_attendance_logs enable row level security;
alter table public.p112_work_categories enable row level security;
alter table public.p112_work_items enable row level security;
alter table public.p112_attendance_work_items enable row level security;
alter table public.p112_hour_transactions enable row level security;
alter table public.p112_lab_devices enable row level security;

-- Drop policies for re-runnable script.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname='public' and tablename like 'p112_%' loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

create policy p112_profiles_select_self_or_admin on public.p112_profiles
for select using (id = auth.uid() or public.p112_is_admin());
create policy p112_profiles_admin_all on public.p112_profiles
for all using (public.p112_is_admin()) with check (public.p112_is_admin());
create policy p112_profiles_update_self_basic on public.p112_profiles
for update using (id = auth.uid()) with check (id = auth.uid());

create policy p112_slots_select_active on public.p112_duty_slots
for select using (auth.uid() is not null);
create policy p112_slots_admin_all on public.p112_duty_slots
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_reservations_select_self_or_admin on public.p112_reservations
for select using (student_id = auth.uid() or public.p112_is_admin());
create policy p112_reservations_student_insert_self on public.p112_reservations
for insert with check (student_id = auth.uid());
create policy p112_reservations_student_update_self on public.p112_reservations
for update using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy p112_reservations_admin_all on public.p112_reservations
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_attendance_select_self_or_admin on public.p112_attendance_logs
for select using (student_id = auth.uid() or public.p112_is_admin());
create policy p112_attendance_insert_self on public.p112_attendance_logs
for insert with check (student_id = auth.uid());
create policy p112_attendance_update_self on public.p112_attendance_logs
for update using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy p112_attendance_admin_all on public.p112_attendance_logs
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_work_categories_select_auth on public.p112_work_categories
for select using (auth.uid() is not null);
create policy p112_work_categories_admin_all on public.p112_work_categories
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_work_items_select_auth on public.p112_work_items
for select using (auth.uid() is not null);
create policy p112_work_items_admin_all on public.p112_work_items
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_att_work_select_self_or_admin on public.p112_attendance_work_items
for select using (
  public.p112_is_admin() or exists (
    select 1 from public.p112_attendance_logs l where l.id = attendance_log_id and l.student_id = auth.uid()
  )
);
create policy p112_att_work_insert_self on public.p112_attendance_work_items
for insert with check (
  exists (select 1 from public.p112_attendance_logs l where l.id = attendance_log_id and l.student_id = auth.uid())
);
create policy p112_att_work_admin_all on public.p112_attendance_work_items
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

create policy p112_hours_select_self_or_admin on public.p112_hour_transactions
for select using (student_id = auth.uid() or public.p112_is_admin());
create policy p112_hours_admin_all on public.p112_hour_transactions
for all using (public.p112_is_admin()) with check (public.p112_is_admin());
create policy p112_hours_insert_self_checked_out on public.p112_hour_transactions
for insert with check (student_id = auth.uid());

create policy p112_lab_devices_admin_all on public.p112_lab_devices
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

-- Settings remain admin-readable only.
create policy p112_settings_admin_select on public.p112_settings
for select using (public.p112_is_admin());
create policy p112_settings_admin_all on public.p112_settings
for all using (public.p112_is_admin()) with check (public.p112_is_admin());

-- Grants for RPC and tables.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.p112_verify_lab_code(text) to authenticated;
grant execute on function public.p112_get_display_code(uuid, text) to authenticated;
grant execute on function public.p112_create_slots(date, time, time, int) to authenticated;
grant execute on function public.p112_generate_lab_code(timestamptz) to authenticated;
