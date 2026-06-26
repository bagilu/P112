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

create or replace function public.p112_create_duty_slot(p_token text, p_unit_id uuid, p_slot_date date, p_start_time time, p_end_time time, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_slot uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;
  insert into public."TblP112DutySlots"(unit_id, slot_date, start_time, end_time, note, created_by)
  values(p_unit_id, p_slot_date, p_start_time, p_end_time, p_note, v_actor)
  on conflict(unit_id, slot_date, start_time, end_time) do update set is_open=true, note=excluded.note
  returning slot_id into v_slot;
  return jsonb_build_object('ok', true, 'slot_id', v_slot);
end $$;

create or replace function public.p112_get_slots(p_token text, p_unit_id uuid, p_from date default current_date, p_to date default current_date + 14)
returns table(slot_id uuid, slot_date date, start_time time, end_time time, regular_user text, standby_user text, is_open boolean)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;
  return query
  select s.slot_id, s.slot_date, s.start_time, s.end_time,
    max(case when r.reservation_type='regular' and r.status in ('reserved','checked_in','completed') then u.display_name end) as regular_user,
    max(case when r.reservation_type='standby' and r.status in ('reserved','checked_in','completed') then u.display_name end) as standby_user,
    s.is_open
  from public."TblP112DutySlots" s
  left join public."TblP112Reservations" r on r.slot_id=s.slot_id and r.status in ('reserved','checked_in','completed')
  left join public."TblP112Users" u on u.user_id=r.user_id
  where s.unit_id=p_unit_id and s.slot_date between p_from and p_to
  group by s.slot_id, s.slot_date, s.start_time, s.end_time, s.is_open
  order by s.slot_date, s.start_time;
end $$;

create or replace function public.p112_create_reservation(p_token text, p_slot_id uuid, p_reservation_type text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_unit uuid; v_res uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;
  if p_reservation_type not in ('regular','standby') then raise exception 'Invalid reservation_type.'; end if;
  select unit_id into v_unit from public."TblP112DutySlots" where slot_id=p_slot_id and is_open=true;
  if v_unit is null then raise exception 'Slot not found or closed.'; end if;
  if not public.p112_has_unit_role(v_actor, v_unit, array['unit_admin','supervisor','worker']) then raise exception 'Permission denied.'; end if;
  insert into public."TblP112Reservations"(unit_id, slot_id, user_id, reservation_type)
  values(v_unit, p_slot_id, v_actor, p_reservation_type)
  returning reservation_id into v_res;
  return jsonb_build_object('ok', true, 'reservation_id', v_res);
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
