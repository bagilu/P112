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

