-- P112 LabDuty Multi-Unit V1 Schema - fixed clean install
-- GitHub Pages + Supabase
-- Run this file in Supabase Dashboard > SQL Editor.
-- All tables/functions use p112_ prefix.
-- IMPORTANT for early testing: this script drops existing P112 tables/functions first.
-- If you already have real P112 data, back it up before running this file.

create extension if not exists pgcrypto;

-- ---------- clean reset for P112 objects ----------
drop function if exists public.p112_is_system_admin(uuid) cascade;
drop function if exists public.p112_is_unit_manager(uuid,uuid) cascade;
drop function if exists public.p112_is_unit_member(uuid,uuid) cascade;
drop function if exists public.p112_get_my_units() cascade;
drop function if exists public.p112_create_unit(text,text,text) cascade;
drop function if exists public.p112_add_unit_member_by_email(uuid,text,text) cascade;
drop function if exists public.p112_generate_slots(uuid,date,time,time,int) cascade;
drop function if exists public.p112_make_reservation(uuid,uuid,text) cascade;
drop function if exists public.p112_get_my_reservations(uuid) cascade;
drop function if exists public.p112_checkin(uuid,text,text) cascade;
drop function if exists public.p112_checkout(uuid,text,text,uuid[],text,text) cascade;
drop function if exists public.p112_get_my_hours(uuid) cascade;
drop function if exists public.p112_admin_attendance_report(uuid) cascade;
drop function if exists public.p112_admin_hours_report(uuid) cascade;
drop function if exists public.p112_get_display_code(uuid) cascade;

drop table if exists public.p112_lab_code_audit cascade;
drop table if exists public.p112_lab_devices cascade;
drop table if exists public.p112_hour_transactions cascade;
drop table if exists public.p112_attendance_work_items cascade;
drop table if exists public.p112_work_items cascade;
drop table if exists public.p112_work_categories cascade;
drop table if exists public.p112_attendance_logs cascade;
drop table if exists public.p112_reservations cascade;
drop table if exists public.p112_duty_slots cascade;
drop table if exists public.p112_unit_settings cascade;
drop table if exists public.p112_unit_members cascade;
drop table if exists public.p112_units cascade;
drop table if exists public.p112_profiles cascade;

-- ---------- tables ----------
create table public.p112_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  display_name text not null,
  system_role text not null default 'user' check (system_role in ('system_admin','user')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.p112_units (
  unit_id uuid primary key default gen_random_uuid(),
  unit_name text not null,
  unit_type text not null default 'lab' check (unit_type in ('lab','office','center','company','project','other')),
  description text,
  contact_email text,
  photo_email text,
  timezone text not null default 'Asia/Taipei',
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.p112_unit_members (
  unit_member_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_in_unit text not null default 'worker' check (role_in_unit in ('unit_admin','supervisor','worker')),
  member_status text not null default 'active' check (member_status in ('active','inactive')),
  joined_at timestamptz not null default now(),
  unique(unit_id,user_id)
);

create table public.p112_unit_settings (
  unit_id uuid primary key references public.p112_units(unit_id) on delete cascade,
  slot_minutes integer not null default 30 check (slot_minutes between 15 and 240),
  allow_standby boolean not null default true,
  standby_credit_rate numeric(5,2) not null default 0.10 check (standby_credit_rate >= 0 and standby_credit_rate <= 1),
  require_work_items boolean not null default true,
  require_work_summary boolean not null default true,
  require_photo_email boolean not null default true,
  photo_email text,
  photo_email_instruction text default '請於簽到後拍攝現場工作照片，並以 email 寄給單位管理者。建議主旨：P112簽到照片｜單位名稱｜姓名｜日期時間',
  checkin_grace_minutes integer not null default 10,
  checkout_grace_minutes integer not null default 10,
  enable_lab_code boolean not null default false,
  enable_device_token boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.p112_duty_slots (
  slot_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  slot_date date not null,
  start_time time not null,
  end_time time not null,
  status text not null default 'open' check (status in ('open','closed','cancelled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(unit_id,slot_date,start_time,end_time),
  check (end_time > start_time)
);

create table public.p112_reservations (
  reservation_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  slot_id uuid not null references public.p112_duty_slots(slot_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reservation_type text not null check (reservation_type in ('regular','standby')),
  status text not null default 'reserved' check (status in ('reserved','checked_in','completed','absent','cancelled','replaced')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);

create unique index p112_reservations_one_active_type_per_slot
  on public.p112_reservations(slot_id, reservation_type)
  where status in ('reserved','checked_in','completed');

create table public.p112_attendance_logs (
  attendance_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  reservation_id uuid not null references public.p112_reservations(reservation_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  checkin_at timestamptz,
  checkout_at timestamptz,
  checkin_ip_note text,
  checkout_ip_note text,
  checkin_user_agent text,
  checkout_user_agent text,
  lab_code_status text default 'not_required',
  photo_email_required boolean default true,
  photo_email_recipient text,
  work_summary text,
  issue_report text,
  abnormal_flag boolean not null default false,
  abnormal_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(reservation_id)
);

create table public.p112_work_categories (
  category_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  category_name text not null,
  description text,
  display_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.p112_work_items (
  item_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  category_id uuid references public.p112_work_categories(category_id) on delete set null,
  item_name text not null,
  standard text,
  estimated_minutes integer,
  is_required boolean not null default false,
  requires_approval boolean not null default false,
  display_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.p112_attendance_work_items (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.p112_attendance_logs(attendance_id) on delete cascade,
  item_id uuid not null references public.p112_work_items(item_id) on delete cascade,
  note text,
  completed boolean not null default true,
  created_at timestamptz not null default now(),
  unique(attendance_id,item_id)
);

create table public.p112_hour_transactions (
  transaction_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reservation_id uuid references public.p112_reservations(reservation_id) on delete set null,
  attendance_id uuid references public.p112_attendance_logs(attendance_id) on delete set null,
  hours_delta numeric(8,2) not null,
  reason text not null,
  transaction_type text not null default 'attendance' check (transaction_type in ('attendance','standby_credit','manual_adjustment','absence_penalty')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- V2 reserved: display account + authorized device token + lab code
create table public.p112_lab_devices (
  device_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.p112_units(unit_id) on delete cascade,
  device_name text not null,
  device_token_hash text,
  is_active boolean not null default true,
  registered_by uuid references auth.users(id),
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz,
  last_ip_note text,
  note text
);

create table public.p112_lab_code_audit (
  audit_id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.p112_units(unit_id) on delete cascade,
  device_id uuid references public.p112_lab_devices(device_id) on delete set null,
  event_type text not null,
  event_note text,
  created_at timestamptz not null default now()
);

-- ---------- helper functions ----------
create or replace function public.p112_is_system_admin(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.p112_profiles where user_id=p_user and system_role='system_admin' and is_active=true);
$$;

create or replace function public.p112_is_unit_manager(p_unit_id uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select public.p112_is_system_admin(p_user) or exists(
    select 1 from public.p112_unit_members
    where unit_id=p_unit_id and user_id=p_user and role_in_unit in ('unit_admin','supervisor') and member_status='active'
  );
$$;

create or replace function public.p112_is_unit_member(p_unit_id uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select public.p112_is_unit_manager(p_unit_id,p_user) or exists(
    select 1 from public.p112_unit_members
    where unit_id=p_unit_id and user_id=p_user and member_status='active'
  );
$$;

-- ---------- RLS ----------
alter table public.p112_profiles enable row level security;
alter table public.p112_units enable row level security;
alter table public.p112_unit_members enable row level security;
alter table public.p112_unit_settings enable row level security;
alter table public.p112_duty_slots enable row level security;
alter table public.p112_reservations enable row level security;
alter table public.p112_attendance_logs enable row level security;
alter table public.p112_work_categories enable row level security;
alter table public.p112_work_items enable row level security;
alter table public.p112_attendance_work_items enable row level security;
alter table public.p112_hour_transactions enable row level security;
alter table public.p112_lab_devices enable row level security;
alter table public.p112_lab_code_audit enable row level security;

create policy p112_profiles_self_or_admin on public.p112_profiles for select using (user_id=auth.uid() or public.p112_is_system_admin());
create policy p112_profiles_admin_all on public.p112_profiles for all using (public.p112_is_system_admin()) with check (public.p112_is_system_admin());

create policy p112_units_member_select on public.p112_units for select using (public.p112_is_unit_member(unit_id) or public.p112_is_system_admin());
create policy p112_units_system_admin_all on public.p112_units for all using (public.p112_is_system_admin()) with check (public.p112_is_system_admin());

create policy p112_unit_members_select on public.p112_unit_members for select using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));
create policy p112_unit_members_manager_all on public.p112_unit_members for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));

create policy p112_unit_settings_member_select on public.p112_unit_settings for select using (public.p112_is_unit_member(unit_id));
create policy p112_unit_settings_manager_all on public.p112_unit_settings for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));

create policy p112_slots_member_select on public.p112_duty_slots for select using (public.p112_is_unit_member(unit_id));
create policy p112_slots_manager_all on public.p112_duty_slots for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));

create policy p112_reservations_member_select on public.p112_reservations for select using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));
create policy p112_reservations_member_insert on public.p112_reservations for insert with check (user_id=auth.uid() and public.p112_is_unit_member(unit_id));
create policy p112_reservations_self_update on public.p112_reservations for update using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id)) with check (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));

create policy p112_attendance_member_select on public.p112_attendance_logs for select using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));
create policy p112_attendance_self_insert on public.p112_attendance_logs for insert with check (user_id=auth.uid() and public.p112_is_unit_member(unit_id));
create policy p112_attendance_self_update on public.p112_attendance_logs for update using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id)) with check (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));

create policy p112_categories_member_select on public.p112_work_categories for select using (public.p112_is_unit_member(unit_id));
create policy p112_categories_manager_all on public.p112_work_categories for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));
create policy p112_items_member_select on public.p112_work_items for select using (public.p112_is_unit_member(unit_id));
create policy p112_items_manager_all on public.p112_work_items for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));

create policy p112_attendance_items_select on public.p112_attendance_work_items for select using (
  exists(select 1 from public.p112_attendance_logs a where a.attendance_id=public.p112_attendance_work_items.attendance_id and (a.user_id=auth.uid() or public.p112_is_unit_manager(a.unit_id)))
);
create policy p112_attendance_items_insert on public.p112_attendance_work_items for insert with check (
  exists(select 1 from public.p112_attendance_logs a where a.attendance_id=public.p112_attendance_work_items.attendance_id and (a.user_id=auth.uid() or public.p112_is_unit_manager(a.unit_id)))
);

create policy p112_hours_select on public.p112_hour_transactions for select using (user_id=auth.uid() or public.p112_is_unit_manager(unit_id));
create policy p112_hours_manager_all on public.p112_hour_transactions for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));

create policy p112_devices_manager_all on public.p112_lab_devices for all using (public.p112_is_unit_manager(unit_id)) with check (public.p112_is_unit_manager(unit_id));
create policy p112_code_audit_manager_select on public.p112_lab_code_audit for select using (public.p112_is_unit_manager(unit_id));

-- ---------- application functions ----------
create or replace function public.p112_get_my_units()
returns table(unit_id uuid, unit_name text, role_in_unit text, system_role text)
language sql stable security definer set search_path=public as $$
  select u.unit_id,u.unit_name,m.role_in_unit,p.system_role
  from public.p112_unit_members m
  join public.p112_units u on u.unit_id=m.unit_id
  join public.p112_profiles p on p.user_id=m.user_id
  where m.user_id=auth.uid() and m.member_status='active' and u.is_active=true
  union
  select u.unit_id,u.unit_name,'system_admin'::text,p.system_role
  from public.p112_units u, public.p112_profiles p
  where p.user_id=auth.uid() and p.system_role='system_admin' and p.is_active=true and u.is_active=true
  order by unit_name;
$$;
grant execute on function public.p112_get_my_units() to authenticated;

create or replace function public.p112_create_unit(p_unit_name text, p_unit_type text default 'lab', p_photo_email text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_unit uuid;
begin
  if not public.p112_is_system_admin() then raise exception 'Only system_admin can create units.'; end if;
  insert into public.p112_units(unit_name,unit_type,photo_email,created_by) values(p_unit_name,coalesce(p_unit_type,'lab'),p_photo_email,auth.uid()) returning unit_id into v_unit;
  insert into public.p112_unit_settings(unit_id,photo_email,require_photo_email) values(v_unit,p_photo_email,true);
  insert into public.p112_unit_members(unit_id,user_id,role_in_unit) values(v_unit,auth.uid(),'unit_admin');
  return v_unit;
end $$;
grant execute on function public.p112_create_unit(text,text,text) to authenticated;

create or replace function public.p112_add_unit_member_by_email(p_unit_id uuid, p_email text, p_role_in_unit text default 'worker')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_id uuid;
begin
  if not public.p112_is_unit_manager(p_unit_id) then raise exception 'No permission for this unit.'; end if;
  select user_id into v_user from public.p112_profiles where lower(email)=lower(p_email) and is_active=true;
  if v_user is null then raise exception 'Profile not found. Create Supabase Auth user and p112_profiles row first.'; end if;
  insert into public.p112_unit_members(unit_id,user_id,role_in_unit) values(p_unit_id,v_user,p_role_in_unit)
  on conflict(unit_id,user_id) do update set role_in_unit=excluded.role_in_unit, member_status='active'
  returning unit_member_id into v_id;
  return v_id;
end $$;
grant execute on function public.p112_add_unit_member_by_email(uuid,text,text) to authenticated;

create or replace function public.p112_generate_slots(p_unit_id uuid, p_slot_date date, p_start_time time, p_end_time time, p_slot_minutes int default 30)
returns int language plpgsql security definer set search_path=public as $$
declare t time := p_start_time; n int := 0; next_t time;
begin
  if not public.p112_is_unit_manager(p_unit_id) then raise exception 'No permission.'; end if;
  while t < p_end_time loop
    next_t := (t + make_interval(mins => p_slot_minutes))::time;
    exit when next_t > p_end_time;
    insert into public.p112_duty_slots(unit_id,slot_date,start_time,end_time,created_by)
    values(p_unit_id,p_slot_date,t,next_t,auth.uid()) on conflict do nothing;
    n := n + 1; t := next_t;
  end loop;
  return n;
end $$;
grant execute on function public.p112_generate_slots(uuid,date,time,time,int) to authenticated;

create or replace function public.p112_make_reservation(p_unit_id uuid, p_slot_id uuid, p_reservation_type text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_allow boolean; v_slot_unit uuid;
begin
  if not public.p112_is_unit_member(p_unit_id) then raise exception 'Not a member of this unit.'; end if;
  if p_reservation_type not in ('regular','standby') then raise exception 'Invalid reservation type.'; end if;
  select unit_id into v_slot_unit from public.p112_duty_slots where slot_id=p_slot_id and status='open';
  if v_slot_unit is null or v_slot_unit <> p_unit_id then raise exception 'Slot not found in this unit.'; end if;
  select allow_standby into v_allow from public.p112_unit_settings where unit_id=p_unit_id;
  if p_reservation_type='standby' and coalesce(v_allow,true)=false then raise exception 'Standby is disabled for this unit.'; end if;
  insert into public.p112_reservations(unit_id,slot_id,user_id,reservation_type)
  values(p_unit_id,p_slot_id,auth.uid(),p_reservation_type) returning reservation_id into v_id;
  return v_id;
end $$;
grant execute on function public.p112_make_reservation(uuid,uuid,text) to authenticated;

create or replace function public.p112_get_my_reservations(p_unit_id uuid)
returns table(reservation_id uuid, slot_date date, start_time time, end_time time, reservation_type text, status text)
language sql stable security definer set search_path=public as $$
  select r.reservation_id,s.slot_date,s.start_time,s.end_time,r.reservation_type,r.status
  from public.p112_reservations r join public.p112_duty_slots s on s.slot_id=r.slot_id
  where r.unit_id=p_unit_id and r.user_id=auth.uid() and r.status <> 'cancelled'
  order by s.slot_date desc, s.start_time desc;
$$;
grant execute on function public.p112_get_my_reservations(uuid) to authenticated;

create or replace function public.p112_checkin(p_reservation_id uuid, p_ip_note text default null, p_user_agent text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; st record; v_att uuid;
begin
  select * into r from public.p112_reservations where reservation_id=p_reservation_id and user_id=auth.uid();
  if r.reservation_id is null then raise exception 'Reservation not found.'; end if;
  select * into st from public.p112_unit_settings where unit_id=r.unit_id;
  insert into public.p112_attendance_logs(unit_id,reservation_id,user_id,checkin_at,checkin_ip_note,checkin_user_agent,photo_email_required,photo_email_recipient)
  values(r.unit_id,r.reservation_id,auth.uid(),now(),p_ip_note,p_user_agent,coalesce(st.require_photo_email,true),coalesce(st.photo_email,(select photo_email from public.p112_units where unit_id=r.unit_id)))
  on conflict(reservation_id) do update set checkin_at=coalesce(public.p112_attendance_logs.checkin_at,now()), checkin_ip_note=p_ip_note, checkin_user_agent=p_user_agent
  returning attendance_id into v_att;
  update public.p112_reservations set status='checked_in' where reservation_id=p_reservation_id;
  return jsonb_build_object('attendance_id',v_att,'message','簽到完成。若本單位要求照片佐證，請依頁面提示以 email 傳送照片給管理者。','photo_email',coalesce(st.photo_email,(select photo_email from public.p112_units where unit_id=r.unit_id)));
end $$;
grant execute on function public.p112_checkin(uuid,text,text) to authenticated;

create or replace function public.p112_checkout(p_reservation_id uuid, p_work_summary text default null, p_issue_report text default null, p_work_item_ids uuid[] default '{}', p_ip_note text default null, p_user_agent text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; a record; st record; v_hours numeric; v_item uuid;
begin
  select * into r from public.p112_reservations where reservation_id=p_reservation_id and user_id=auth.uid();
  if r.reservation_id is null then raise exception 'Reservation not found.'; end if;
  select * into st from public.p112_unit_settings where unit_id=r.unit_id;
  select * into a from public.p112_attendance_logs where reservation_id=p_reservation_id;
  if a.attendance_id is null then raise exception 'Please check in first.'; end if;
  if st.require_work_summary and coalesce(length(trim(p_work_summary)),0)=0 then raise exception 'Work summary is required.'; end if;
  if st.require_work_items and (p_work_item_ids is null or array_length(p_work_item_ids,1) is null) then raise exception 'At least one work item is required.'; end if;
  update public.p112_attendance_logs set checkout_at=now(), checkout_ip_note=p_ip_note, checkout_user_agent=p_user_agent, work_summary=p_work_summary, issue_report=p_issue_report, updated_at=now() where attendance_id=a.attendance_id;
  if p_work_item_ids is not null then
    foreach v_item in array p_work_item_ids loop
      insert into public.p112_attendance_work_items(attendance_id,item_id) values(a.attendance_id,v_item) on conflict do nothing;
    end loop;
  end if;
  select round((extract(epoch from ((s.slot_date + s.end_time) - (s.slot_date + s.start_time)))/3600.0)::numeric,2) into v_hours from public.p112_duty_slots s where s.slot_id=r.slot_id;
  update public.p112_reservations set status='completed' where reservation_id=p_reservation_id;
  delete from public.p112_hour_transactions where reservation_id=p_reservation_id and transaction_type in ('attendance','standby_credit');
  insert into public.p112_hour_transactions(unit_id,user_id,reservation_id,attendance_id,hours_delta,reason,transaction_type,created_by)
  values(r.unit_id,auth.uid(),r.reservation_id,a.attendance_id,v_hours,'completed duty attendance','attendance',auth.uid());
  return jsonb_build_object('message','簽退完成，已產生時數紀錄。','hours',v_hours);
end $$;
grant execute on function public.p112_checkout(uuid,text,text,uuid[],text,text) to authenticated;

create or replace function public.p112_get_my_hours(p_unit_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(hours_delta),0) from public.p112_hour_transactions where unit_id=p_unit_id and user_id=auth.uid();
$$;
grant execute on function public.p112_get_my_hours(uuid) to authenticated;

create or replace function public.p112_admin_attendance_report(p_unit_id uuid)
returns table(display_name text,email text,reservation_id uuid,slot_date date,start_time time,end_time time,reservation_type text,status text,checkin_at timestamptz,checkout_at timestamptz,work_summary text,issue_report text)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.p112_is_unit_manager(p_unit_id) then raise exception 'No permission.'; end if;
 return query
 select p.display_name,p.email,r.reservation_id,s.slot_date,s.start_time,s.end_time,r.reservation_type,r.status,a.checkin_at,a.checkout_at,a.work_summary,a.issue_report
 from public.p112_reservations r
 join public.p112_profiles p on p.user_id=r.user_id
 join public.p112_duty_slots s on s.slot_id=r.slot_id
 left join public.p112_attendance_logs a on a.reservation_id=r.reservation_id
 where r.unit_id=p_unit_id
 order by s.slot_date desc,s.start_time desc,p.display_name;
end $$;
grant execute on function public.p112_admin_attendance_report(uuid) to authenticated;

create or replace function public.p112_admin_hours_report(p_unit_id uuid)
returns table(display_name text,email text,total_hours numeric)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.p112_is_unit_manager(p_unit_id) then raise exception 'No permission.'; end if;
 return query
 select p.display_name,p.email,coalesce(sum(h.hours_delta),0) as total_hours
 from public.p112_unit_members m
 join public.p112_profiles p on p.user_id=m.user_id
 left join public.p112_hour_transactions h on h.unit_id=m.unit_id and h.user_id=m.user_id
 where m.unit_id=p_unit_id and m.member_status='active'
 group by p.display_name,p.email
 order by total_hours desc,p.display_name;
end $$;
grant execute on function public.p112_admin_hours_report(uuid) to authenticated;

-- V2 placeholder function. Do not enable in V1 unless you intentionally turn on lab code.
create or replace function public.p112_get_display_code(p_unit_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_hex text; v_num numeric;
begin
  if not public.p112_is_unit_manager(p_unit_id) then raise exception 'V2 display code requires authorized display setup.'; end if;
  v_hex := substr(encode(digest(p_unit_id::text || date_trunc('minute',now())::text,'sha256'),'hex'),1,8);
  v_num := mod(('x' || v_hex)::bit(32)::bigint, 1000000);
  return lpad(v_num::int::text,6,'0');
end $$;
grant execute on function public.p112_get_display_code(uuid) to authenticated;

-- ---------- seed note ----------
-- After creating an Auth user for yourself, insert or update your profile as system_admin:
-- insert into public.p112_profiles(user_id,email,display_name,system_role)
-- values('YOUR-AUTH-USER-UUID','your@email','老師','system_admin')
-- on conflict(user_id) do update set system_role='system_admin', display_name=excluded.display_name, email=excluded.email;
