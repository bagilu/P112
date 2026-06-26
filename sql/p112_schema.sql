-- P112 我來值班｜Multi-Unit V1, Table-based Login, No Supabase Auth
-- Naming rule: all tables use quoted names beginning with "TblP112".
-- Function names use p112_ prefix.
-- Development install: this script first drops old p112_ / TblP112 objects, then rebuilds.

-- P112 reset script
-- Drops previous p112_ lowercase tables/functions and current TblP112 quoted tables/functions.
-- Use only during development or when you want a clean reinstall.

begin;

-- Drop p112 functions first.
do $$
declare r record;
begin
  for r in
    select n.nspname as schema_name, p.proname as function_name, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'p112\_%' escape '\'
  loop
    execute format('drop function if exists %I.%I(%s) cascade', r.schema_name, r.function_name, r.args);
  end loop;
end $$;

-- Drop prior lowercase p112_ tables.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public' and tablename like 'p112\_%' escape '\'
  loop
    execute format('drop table if exists %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end $$;

-- Drop current quoted TblP112 tables.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public' and tablename like 'TblP112%'
  loop
    execute format('drop table if exists %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end $$;

commit;


create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- =========================
-- Tables
-- =========================

create table public."TblP112Users" (
  user_id uuid primary key default extensions.gen_random_uuid(),
  email text not null unique,
  display_name text not null,
  password_hash text not null,
  system_role text not null default 'user' check (system_role in ('sysadmin','user')),
  is_active boolean not null default true,
  must_change_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public."TblP112Sessions" (
  session_id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public."TblP112Users"(user_id) on delete cascade,
  session_token_hash text not null unique,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  last_seen_at timestamptz,
  user_agent text,
  last_ip text,
  is_active boolean not null default true
);

create table public."TblP112Units" (
  unit_id uuid primary key default extensions.gen_random_uuid(),
  unit_name text not null,
  unit_type text not null default 'lab',
  description text,
  contact_email text,
  photo_email text,
  timezone text not null default 'Asia/Taipei',
  is_active boolean not null default true,
  created_by uuid references public."TblP112Users"(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public."TblP112UnitSettings" (
  unit_id uuid primary key references public."TblP112Units"(unit_id) on delete cascade,
  slot_minutes integer not null default 30,
  allow_standby boolean not null default true,
  standby_credit_rate numeric(5,2) not null default 0.10,
  require_work_items boolean not null default true,
  require_work_summary boolean not null default true,
  require_photo_email boolean not null default true,
  photo_email_instruction text default '請於簽到或簽退後，拍攝現場或工作成果照片，另寄 email 給管理者作為人工佐證。',
  checkin_grace_minutes integer not null default 10,
  checkout_grace_minutes integer not null default 10,
  enable_lab_code boolean not null default false,
  enable_device_token boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public."TblP112UnitMembers" (
  unit_member_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  user_id uuid not null references public."TblP112Users"(user_id) on delete cascade,
  unit_role text not null default 'worker' check (unit_role in ('unit_admin','supervisor','worker')),
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique(unit_id, user_id)
);

create table public."TblP112DutySlots" (
  slot_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  slot_date date not null,
  start_time time not null,
  end_time time not null,
  regular_capacity integer not null default 1 check (regular_capacity >= 0),
  standby_capacity integer not null default 1 check (standby_capacity >= 0),
  is_open boolean not null default true,
  note text,
  created_by uuid references public."TblP112Users"(user_id),
  created_at timestamptz not null default now(),
  unique(unit_id, slot_date, start_time, end_time)
);

create table public."TblP112Reservations" (
  reservation_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  slot_id uuid not null references public."TblP112DutySlots"(slot_id) on delete cascade,
  user_id uuid not null references public."TblP112Users"(user_id) on delete cascade,
  reservation_type text not null check (reservation_type in ('regular','standby')),
  status text not null default 'reserved' check (status in ('reserved','checked_in','completed','cancelled','absent','replaced')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);

create unique index "IdxTblP112ReservationsOneActiveUserTypePerSlot"
  on public."TblP112Reservations"(slot_id, user_id, reservation_type)
  where status in ('reserved','checked_in','completed');

create table public."TblP112AttendanceLogs" (
  attendance_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  reservation_id uuid references public."TblP112Reservations"(reservation_id) on delete set null,
  user_id uuid not null references public."TblP112Users"(user_id) on delete cascade,
  checkin_time timestamptz,
  checkout_time timestamptz,
  checkin_ip text,
  checkout_ip text,
  checkin_user_agent text,
  checkout_user_agent text,
  work_summary text,
  abnormal_note text,
  photo_email_reminded boolean not null default true,
  status text not null default 'checked_in' check (status in ('checked_in','completed','abnormal','cancelled')),
  created_at timestamptz not null default now()
);

create table public."TblP112WorkCategories" (
  category_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  category_name text not null,
  description text,
  display_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(unit_id, category_name)
);

create table public."TblP112WorkItems" (
  item_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  category_id uuid references public."TblP112WorkCategories"(category_id) on delete set null,
  item_name text not null,
  standard text,
  estimated_minutes integer,
  is_required boolean not null default false,
  requires_approval boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(unit_id, item_name)
);

create table public."TblP112AttendanceWorkItems" (
  attendance_work_item_id uuid primary key default extensions.gen_random_uuid(),
  attendance_id uuid not null references public."TblP112AttendanceLogs"(attendance_id) on delete cascade,
  item_id uuid not null references public."TblP112WorkItems"(item_id) on delete restrict,
  note text,
  completed boolean not null default true,
  created_at timestamptz not null default now(),
  unique(attendance_id, item_id)
);

create table public."TblP112HourTransactions" (
  transaction_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  user_id uuid not null references public."TblP112Users"(user_id) on delete cascade,
  source_type text not null default 'manual',
  source_id uuid,
  hours_delta numeric(8,2) not null,
  reason text not null,
  approved_by uuid references public."TblP112Users"(user_id),
  created_at timestamptz not null default now()
);

create table public."TblP112AbnormalFlags" (
  flag_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  user_id uuid references public."TblP112Users"(user_id) on delete set null,
  attendance_id uuid references public."TblP112AttendanceLogs"(attendance_id) on delete cascade,
  flag_type text not null,
  flag_message text not null,
  is_resolved boolean not null default false,
  resolved_by uuid references public."TblP112Users"(user_id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- V2 reserved tables. Not used in V1.
create table public."TblP112LabDevices" (
  device_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public."TblP112Units"(unit_id) on delete cascade,
  device_name text not null,
  device_token_hash text,
  is_active boolean not null default false,
  registered_by uuid references public."TblP112Users"(user_id),
  registered_at timestamptz,
  last_seen_at timestamptz,
  last_ip text,
  note text
);

create table public."TblP112DisplaySessions" (
  display_session_id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid references public."TblP112Units"(unit_id) on delete cascade,
  device_id uuid references public."TblP112LabDevices"(device_id) on delete cascade,
  started_at timestamptz not null default now(),
  last_seen_at timestamptz,
  is_active boolean not null default false
);

-- Enable RLS and do not create direct table policies. All operations go through SECURITY DEFINER RPC functions.
alter table public."TblP112Users" enable row level security;
alter table public."TblP112Sessions" enable row level security;
alter table public."TblP112Units" enable row level security;
alter table public."TblP112UnitSettings" enable row level security;
alter table public."TblP112UnitMembers" enable row level security;
alter table public."TblP112DutySlots" enable row level security;
alter table public."TblP112Reservations" enable row level security;
alter table public."TblP112AttendanceLogs" enable row level security;
alter table public."TblP112WorkCategories" enable row level security;
alter table public."TblP112WorkItems" enable row level security;
alter table public."TblP112AttendanceWorkItems" enable row level security;
alter table public."TblP112HourTransactions" enable row level security;
alter table public."TblP112AbnormalFlags" enable row level security;
alter table public."TblP112LabDevices" enable row level security;
alter table public."TblP112DisplaySessions" enable row level security;

revoke all on all tables in schema public from anon, authenticated;

-- =========================
-- Helper Functions
-- =========================

create or replace function public.p112_token_hash(p_token text)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;

create or replace function public.p112_normalize_email(p_email text)
returns text
language sql
immutable
as $$
  select lower(trim(p_email));
$$;

create or replace function public.p112_session_user_id(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_user_id uuid;
begin
  if p_token is null or length(p_token) < 20 then
    return null;
  end if;

  select s.user_id into v_user_id
  from public."TblP112Sessions" s
  join public."TblP112Users" u on u.user_id = s.user_id
  where s.session_token_hash = public.p112_token_hash(p_token)
    and s.is_active = true
    and s.expires_at > now()
    and u.is_active = true;

  if v_user_id is not null then
    update public."TblP112Sessions"
    set last_seen_at = now()
    where session_token_hash = public.p112_token_hash(p_token);
  end if;

  return v_user_id;
end $$;

create or replace function public.p112_is_sysadmin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public."TblP112Users"
    where user_id = p_user_id and system_role = 'sysadmin' and is_active = true
  );
$$;

create or replace function public.p112_has_unit_role(p_user_id uuid, p_unit_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.p112_is_sysadmin(p_user_id)
    or exists(
      select 1 from public."TblP112UnitMembers"
      where user_id = p_user_id
        and unit_id = p_unit_id
        and is_active = true
        and unit_role = any(p_roles)
    );
$$;

-- =========================
-- Auth-like RPC, without Supabase Auth
-- =========================

create or replace function public.p112_bootstrap_sysadmin(p_email text, p_password text, p_display_name text default '系統管理員')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_user_id uuid;
begin
  if exists(select 1 from public."TblP112Users" where system_role = 'sysadmin' and is_active = true) then
    raise exception 'A sysadmin already exists. Use p112_admin_create_user or p112_admin_reset_password.';
  end if;
  if length(coalesce(p_password,'')) < 8 then
    raise exception 'Password must be at least 8 characters.';
  end if;

  insert into public."TblP112Users"(email, display_name, password_hash, system_role, is_active, must_change_password)
  values(public.p112_normalize_email(p_email), p_display_name, extensions.crypt(p_password, extensions.gen_salt('bf')), 'sysadmin', true, false)
  returning user_id into v_user_id;

  return jsonb_build_object('ok', true, 'user_id', v_user_id, 'email', public.p112_normalize_email(p_email));
end $$;

create or replace function public.p112_login(p_email text, p_password text, p_user_agent text default null, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public."TblP112Users"%rowtype;
  v_token text;
begin
  select * into v_user
  from public."TblP112Users"
  where email = public.p112_normalize_email(p_email)
    and is_active = true;

  if v_user.user_id is null or v_user.password_hash <> extensions.crypt(p_password, v_user.password_hash) then
    raise exception 'Invalid email or password.';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public."TblP112Sessions"(user_id, session_token_hash, user_agent, last_ip)
  values(v_user.user_id, public.p112_token_hash(v_token), p_user_agent, p_ip);

  return jsonb_build_object(
    'ok', true,
    'session_token', v_token,
    'user_id', v_user.user_id,
    'email', v_user.email,
    'display_name', v_user.display_name,
    'system_role', v_user.system_role,
    'must_change_password', v_user.must_change_password
  );
end $$;

create or replace function public.p112_logout(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public."TblP112Sessions" set is_active = false where session_token_hash = public.p112_token_hash(p_token);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.p112_get_current_user(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_user_id uuid; v_user public."TblP112Users"%rowtype;
begin
  v_user_id := public.p112_session_user_id(p_token);
  if v_user_id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_user from public."TblP112Users" where user_id = v_user_id;
  return jsonb_build_object('user_id', v_user.user_id, 'email', v_user.email, 'display_name', v_user.display_name, 'system_role', v_user.system_role, 'must_change_password', v_user.must_change_password);
end $$;

create or replace function public.p112_change_password(p_token text, p_old_password text, p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_user_id uuid; v_hash text;
begin
  v_user_id := public.p112_session_user_id(p_token);
  if v_user_id is null then raise exception 'Invalid or expired session.'; end if;
  if length(coalesce(p_new_password,'')) < 8 then raise exception 'New password must be at least 8 characters.'; end if;
  select password_hash into v_hash from public."TblP112Users" where user_id = v_user_id;
  if v_hash <> extensions.crypt(p_old_password, v_hash) then raise exception 'Old password is incorrect.'; end if;
  update public."TblP112Users" set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')), must_change_password = false, updated_at = now() where user_id = v_user_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.p112_admin_create_user(p_token text, p_email text, p_display_name text, p_password text, p_system_role text default 'user', p_must_change_password boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_new uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_is_sysadmin(v_actor) then raise exception 'Permission denied.'; end if;
  if p_system_role not in ('sysadmin','user') then raise exception 'Invalid system_role.'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'Password must be at least 8 characters.'; end if;
  insert into public."TblP112Users"(email, display_name, password_hash, system_role, must_change_password)
  values(public.p112_normalize_email(p_email), p_display_name, extensions.crypt(p_password, extensions.gen_salt('bf')), p_system_role, p_must_change_password)
  returning user_id into v_new;
  return jsonb_build_object('ok', true, 'user_id', v_new);
end $$;

create or replace function public.p112_admin_reset_password(p_token text, p_user_id uuid, p_new_password text, p_must_change_password boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_is_sysadmin(v_actor) then raise exception 'Permission denied.'; end if;
  if length(coalesce(p_new_password,'')) < 8 then raise exception 'Password must be at least 8 characters.'; end if;
  update public."TblP112Users" set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')), must_change_password = p_must_change_password, updated_at = now() where user_id = p_user_id;
  return jsonb_build_object('ok', true);
end $$;

-- =========================
-- Unit and duty RPC
-- =========================

create or replace function public.p112_create_unit(p_token text, p_unit_name text, p_unit_type text default 'lab', p_description text default null, p_contact_email text default null, p_photo_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_unit uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_is_sysadmin(v_actor) then raise exception 'Permission denied.'; end if;
  insert into public."TblP112Units"(unit_name, unit_type, description, contact_email, photo_email, created_by)
  values(p_unit_name, coalesce(p_unit_type,'lab'), p_description, p_contact_email, p_photo_email, v_actor)
  returning unit_id into v_unit;
  insert into public."TblP112UnitSettings"(unit_id) values(v_unit);
  insert into public."TblP112UnitMembers"(unit_id, user_id, unit_role) values(v_unit, v_actor, 'unit_admin');
  return jsonb_build_object('ok', true, 'unit_id', v_unit);
end $$;

create or replace function public.p112_get_units(p_token text)
returns table(unit_id uuid, unit_name text, unit_type text, photo_email text, role_in_unit text, is_sysadmin boolean)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_sys boolean;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  v_sys := public.p112_is_sysadmin(v_actor);
  if v_sys then
    return query select u.unit_id, u.unit_name, u.unit_type, u.photo_email, 'sysadmin'::text, true from public."TblP112Units" u where u.is_active order by u.unit_name;
  else
    return query select u.unit_id, u.unit_name, u.unit_type, u.photo_email, m.unit_role, false
    from public."TblP112UnitMembers" m join public."TblP112Units" u on u.unit_id=m.unit_id
    where m.user_id=v_actor and m.is_active and u.is_active order by u.unit_name;
  end if;
end $$;

create or replace function public.p112_add_unit_member(p_token text, p_unit_id uuid, p_user_id uuid, p_unit_role text default 'worker')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin']) then raise exception 'Permission denied.'; end if;
  if p_unit_role not in ('unit_admin','supervisor','worker') then raise exception 'Invalid unit_role.'; end if;
  insert into public."TblP112UnitMembers"(unit_id, user_id, unit_role)
  values(p_unit_id, p_user_id, p_unit_role)
  on conflict(unit_id, user_id) do update set unit_role=excluded.unit_role, is_active=true;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.p112_list_users(p_token text)
returns table(user_id uuid, email text, display_name text, system_role text, is_active boolean)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_is_sysadmin(v_actor) then raise exception 'Permission denied.'; end if;
  return query select u.user_id, u.email, u.display_name, u.system_role, u.is_active from public."TblP112Users" u order by u.display_name;
end $$;

create or replace function public.p112_create_duty_slot(
  p_token text,
  p_unit_id uuid,
  p_slot_date date,
  p_start_time time,
  p_end_time time,
  p_note text default null,
  p_regular_capacity integer default 1,
  p_standby_capacity integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_slot uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;
  if coalesce(p_regular_capacity,0) < 0 or coalesce(p_standby_capacity,0) < 0 then
    raise exception 'Capacity cannot be negative.';
  end if;
  insert into public."TblP112DutySlots"(unit_id, slot_date, start_time, end_time, regular_capacity, standby_capacity, note, created_by)
  values(p_unit_id, p_slot_date, p_start_time, p_end_time, coalesce(p_regular_capacity,1), coalesce(p_standby_capacity,1), p_note, v_actor)
  on conflict(unit_id, slot_date, start_time, end_time) do update set
    is_open=true,
    note=excluded.note,
    regular_capacity=excluded.regular_capacity,
    standby_capacity=excluded.standby_capacity
  returning slot_id into v_slot;
  return jsonb_build_object('ok', true, 'slot_id', v_slot);
end $$;

create or replace function public.p112_get_slots(p_token text, p_unit_id uuid, p_from date default current_date, p_to date default current_date + 14)
returns table(
  slot_id uuid,
  unit_id uuid,
  unit_name text,
  slot_date date,
  start_time time,
  end_time time,
  regular_user text,
  standby_user text,
  regular_count integer,
  standby_count integer,
  regular_capacity integer,
  standby_capacity integer,
  is_open boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;
  return query
  select s.slot_id, s.unit_id, un.unit_name, s.slot_date, s.start_time, s.end_time,
    coalesce(string_agg(u.display_name, '、' order by u.display_name) filter (where r.reservation_type='regular'), '') as regular_user,
    coalesce(string_agg(u.display_name, '、' order by u.display_name) filter (where r.reservation_type='standby'), '') as standby_user,
    count(r.reservation_id) filter (where r.reservation_type='regular')::integer as regular_count,
    count(r.reservation_id) filter (where r.reservation_type='standby')::integer as standby_count,
    s.regular_capacity,
    s.standby_capacity,
    s.is_open
  from public."TblP112DutySlots" s
  join public."TblP112Units" un on un.unit_id=s.unit_id
  left join public."TblP112Reservations" r on r.slot_id=s.slot_id and r.status in ('reserved','checked_in','completed')
  left join public."TblP112Users" u on u.user_id=r.user_id
  where s.unit_id=p_unit_id and s.slot_date between p_from and p_to
  group by s.slot_id, s.unit_id, un.unit_name, s.slot_date, s.start_time, s.end_time, s.regular_capacity, s.standby_capacity, s.is_open
  order by s.slot_date, s.start_time;
end $$;

create or replace function public.p112_create_reservation(p_token text, p_slot_id uuid, p_reservation_type text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_unit uuid;
  v_res uuid;
  v_capacity integer;
  v_current integer;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  if p_reservation_type not in ('regular','standby') then raise exception 'Invalid reservation_type.'; end if;

  select unit_id,
         case when p_reservation_type='regular' then regular_capacity else standby_capacity end
    into v_unit, v_capacity
  from public."TblP112DutySlots"
  where slot_id=p_slot_id and is_open=true;

  if v_unit is null then raise exception 'Slot not found or closed.'; end if;
  if not public.p112_has_unit_role(v_actor, v_unit, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;

  select count(*)::integer into v_current
  from public."TblP112Reservations"
  where slot_id=p_slot_id
    and reservation_type=p_reservation_type
    and status in ('reserved','checked_in','completed');

  if v_current >= coalesce(v_capacity,0) then
    raise exception 'This % slot is full. Capacity: %, current reservations: %.', p_reservation_type, v_capacity, v_current;
  end if;

  insert into public."TblP112Reservations"(unit_id, slot_id, user_id, reservation_type)
  values(v_unit, p_slot_id, v_actor, p_reservation_type)
  returning reservation_id into v_res;
  return jsonb_build_object('ok', true, 'reservation_id', v_res, 'capacity', v_capacity, 'current_after', v_current + 1);
exception when unique_violation then
  raise exception 'You already have an active % reservation for this slot.', p_reservation_type;
end $$;

create or replace function public.p112_get_my_reservations(p_token text, p_unit_id uuid default null)
returns table(reservation_id uuid, unit_id uuid, unit_name text, slot_date date, start_time time, end_time time, reservation_type text, status text)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  return query
  select r.reservation_id, r.unit_id, un.unit_name, s.slot_date, s.start_time, s.end_time, r.reservation_type, r.status
  from public."TblP112Reservations" r
  join public."TblP112DutySlots" s on s.slot_id=r.slot_id
  join public."TblP112Units" un on un.unit_id=r.unit_id
  where r.user_id=v_actor and r.status in ('reserved','checked_in') and (p_unit_id is null or r.unit_id=p_unit_id)
  order by s.slot_date, s.start_time;
end $$;

create or replace function public.p112_checkin(p_token text, p_reservation_id uuid, p_user_agent text default null, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_res public."TblP112Reservations"%rowtype; v_att uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_res from public."TblP112Reservations" where reservation_id=p_reservation_id and user_id=v_actor and status='reserved';
  if v_res.reservation_id is null then raise exception 'Reservation not found or not available.'; end if;
  insert into public."TblP112AttendanceLogs"(unit_id, reservation_id, user_id, checkin_time, checkin_ip, checkin_user_agent)
  values(v_res.unit_id, v_res.reservation_id, v_actor, now(), p_ip, p_user_agent)
  returning attendance_id into v_att;
  update public."TblP112Reservations" set status='checked_in' where reservation_id=p_reservation_id;
  return jsonb_build_object('ok', true, 'attendance_id', v_att);
end $$;

create or replace function public.p112_ad_hoc_checkin(p_token text, p_unit_id uuid, p_user_agent text default null, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_slot uuid;
  v_res uuid;
  v_att uuid;
  v_now timestamptz := now();
  v_slot_date date;
  v_start time;
  v_end time;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;

  v_slot_date := (v_now at time zone 'Asia/Taipei')::date;
  v_start := make_time(extract(hour from (v_now at time zone 'Asia/Taipei'))::int, (floor(extract(minute from (v_now at time zone 'Asia/Taipei')) / 30)::int * 30), 0);
  v_end := (v_slot_date + v_start + interval '30 minutes')::time;

  insert into public."TblP112DutySlots"(unit_id, slot_date, start_time, end_time, regular_capacity, standby_capacity, note, created_by)
  values(p_unit_id, v_slot_date, v_start, v_end, 99, 0, '系統自動建立：未預約臨時簽到時段', v_actor)
  on conflict(unit_id, slot_date, start_time, end_time) do update set
    is_open=true,
    regular_capacity=greatest(public."TblP112DutySlots".regular_capacity, 99)
  returning slot_id into v_slot;

  insert into public."TblP112Reservations"(unit_id, slot_id, user_id, reservation_type, status)
  values(p_unit_id, v_slot, v_actor, 'regular', 'checked_in')
  returning reservation_id into v_res;

  insert into public."TblP112AttendanceLogs"(unit_id, reservation_id, user_id, checkin_time, checkin_ip, checkin_user_agent)
  values(p_unit_id, v_res, v_actor, now(), p_ip, p_user_agent)
  returning attendance_id into v_att;

  insert into public."TblP112AbnormalFlags"(unit_id, user_id, attendance_id, flag_type, flag_message)
  values(p_unit_id, v_actor, v_att, 'ad_hoc_checkin', '使用未預約簽到功能；請管理者視需要確認。');

  return jsonb_build_object('ok', true, 'reservation_id', v_res, 'attendance_id', v_att, 'slot_id', v_slot, 'ad_hoc', true);
exception when unique_violation then
  raise exception 'You already have an active regular reservation/check-in for the current time slot.';
end $$;

create or replace function public.p112_checkout(p_token text, p_reservation_id uuid, p_work_summary text, p_abnormal_note text default null, p_work_item_ids uuid[] default array[]::uuid[], p_user_agent text default null, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_att public."TblP112AttendanceLogs"%rowtype; v_hours numeric(8,2); v_item uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_att from public."TblP112AttendanceLogs" where reservation_id=p_reservation_id and user_id=v_actor and status='checked_in' order by created_at desc limit 1;
  if v_att.attendance_id is null then raise exception 'Active attendance log not found.'; end if;

  update public."TblP112AttendanceLogs"
  set checkout_time=now(), checkout_ip=p_ip, checkout_user_agent=p_user_agent, work_summary=p_work_summary, abnormal_note=p_abnormal_note, status='completed'
  where attendance_id=v_att.attendance_id;

  foreach v_item in array coalesce(p_work_item_ids, array[]::uuid[]) loop
    insert into public."TblP112AttendanceWorkItems"(attendance_id, item_id) values(v_att.attendance_id, v_item) on conflict do nothing;
  end loop;

  select greatest(0.0, round(extract(epoch from (now() - v_att.checkin_time)) / 3600.0, 2)) into v_hours;
  insert into public."TblP112HourTransactions"(unit_id, user_id, source_type, source_id, hours_delta, reason)
  values(v_att.unit_id, v_actor, 'attendance', v_att.attendance_id, v_hours, '正常簽到簽退自動計入');

  update public."TblP112Reservations" set status='completed' where reservation_id=p_reservation_id;

  if coalesce(trim(p_abnormal_note),'') <> '' then
    insert into public."TblP112AbnormalFlags"(unit_id, user_id, attendance_id, flag_type, flag_message)
    values(v_att.unit_id, v_actor, v_att.attendance_id, 'user_reported', p_abnormal_note);
  end if;

  return jsonb_build_object('ok', true, 'hours_delta', v_hours);
end $$;

create or replace function public.p112_get_work_items(p_token text, p_unit_id uuid)
returns table(item_id uuid, category_name text, item_name text, standard text)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;
  return query
  select wi.item_id, coalesce(c.category_name,'未分類'), wi.item_name, wi.standard
  from public."TblP112WorkItems" wi
  left join public."TblP112WorkCategories" c on c.category_id=wi.category_id
  where wi.unit_id=p_unit_id and wi.is_active
  order by c.display_order, c.category_name, wi.item_name;
end $$;

create or replace function public.p112_admin_add_work_category(p_token text, p_unit_id uuid, p_category_name text, p_description text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_id uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;
  insert into public."TblP112WorkCategories"(unit_id, category_name, description)
  values(p_unit_id, p_category_name, p_description)
  on conflict(unit_id, category_name) do update set description=excluded.description, is_active=true
  returning category_id into v_id;
  return jsonb_build_object('ok', true, 'category_id', v_id);
end $$;

create or replace function public.p112_admin_add_work_item(p_token text, p_unit_id uuid, p_category_id uuid, p_item_name text, p_standard text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_id uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;
  insert into public."TblP112WorkItems"(unit_id, category_id, item_name, standard)
  values(p_unit_id, p_category_id, p_item_name, p_standard)
  on conflict(unit_id, item_name) do update set category_id=excluded.category_id, standard=excluded.standard, is_active=true
  returning item_id into v_id;
  return jsonb_build_object('ok', true, 'item_id', v_id);
end $$;

create or replace function public.p112_get_hour_summary(p_token text, p_unit_id uuid default null)
returns table(unit_id uuid, unit_name text, user_id uuid, display_name text, total_hours numeric)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  if p_unit_id is not null and not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;

  return query
  select h.unit_id, un.unit_name, h.user_id, u.display_name, coalesce(sum(h.hours_delta),0)::numeric(8,2)
  from public."TblP112HourTransactions" h
  join public."TblP112Users" u on u.user_id=h.user_id
  join public."TblP112Units" un on un.unit_id=h.unit_id
  where (p_unit_id is null or h.unit_id=p_unit_id)
    and (public.p112_is_sysadmin(v_actor) or h.user_id=v_actor or public.p112_has_unit_role(v_actor, h.unit_id, array['unit_admin','supervisor']))
  group by h.unit_id, un.unit_name, h.user_id, u.display_name
  order by un.unit_name, u.display_name;
end $$;

-- Grants: allow public anon key to execute controlled RPC only. Direct table access remains blocked by RLS.
grant execute on all functions in schema public to anon, authenticated;

-- Create a view-like function for installation check.
create or replace function public.p112_healthcheck()
returns jsonb
language sql
security definer
as $$ select jsonb_build_object('ok', true, 'version', 'TblP112_NoAuth_V1', 'time', now()); $$;
grant execute on function public.p112_healthcheck() to anon, authenticated;
