-- P112 migration: admin tools for member removal and unused slot deletion.
-- Safe to run after AdHocUnitFix / MultiCapacity schema.



create or replace function public.p112_list_unit_members(p_token text, p_unit_id uuid)
returns table(user_id uuid, email text, display_name text, unit_role text, is_active boolean, joined_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;
  return query
  select u.user_id, u.email, u.display_name, m.unit_role, m.is_active, m.joined_at
  from public."TblP112UnitMembers" m
  join public."TblP112Users" u on u.user_id=m.user_id
  where m.unit_id=p_unit_id
  order by m.is_active desc, m.unit_role, u.display_name;
end $$;

create or replace function public.p112_remove_unit_member(p_token text, p_unit_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_role text; v_active_admins integer;
begin
  v_actor := public.p112_session_user_id(p_token);
  if not public.p112_has_unit_role(v_actor, p_unit_id, array['unit_admin']) then raise exception 'Permission denied.'; end if;

  select unit_role into v_role
  from public."TblP112UnitMembers"
  where unit_id=p_unit_id and user_id=p_user_id and is_active=true;

  if v_role is null then
    raise exception 'Active unit member not found.';
  end if;

  if v_role='unit_admin' and not public.p112_is_sysadmin(v_actor) then
    select count(*)::integer into v_active_admins
    from public."TblP112UnitMembers"
    where unit_id=p_unit_id and unit_role='unit_admin' and is_active=true;
    if v_active_admins <= 1 then
      raise exception 'Cannot remove the last active unit_admin in this unit.';
    end if;
  end if;

  update public."TblP112UnitMembers"
  set is_active=false
  where unit_id=p_unit_id and user_id=p_user_id;

  return jsonb_build_object('ok', true, 'unit_id', p_unit_id, 'user_id', p_user_id, 'action', 'deactivated');
end $$;



create or replace function public.p112_delete_duty_slot(p_token text, p_slot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_unit uuid; v_res_count integer; v_att_count integer;
begin
  v_actor := public.p112_session_user_id(p_token);
  if v_actor is null then raise exception 'Invalid or expired session.'; end if;

  select unit_id into v_unit from public."TblP112DutySlots" where slot_id=p_slot_id;
  if v_unit is null then raise exception 'Duty slot not found.'; end if;
  if not public.p112_has_unit_role(v_actor, v_unit, array['unit_admin','supervisor']) then raise exception 'Permission denied.'; end if;

  select count(*)::integer into v_res_count
  from public."TblP112Reservations"
  where slot_id=p_slot_id;

  select count(*)::integer into v_att_count
  from public."TblP112AttendanceLogs" a
  join public."TblP112Reservations" r on r.reservation_id=a.reservation_id
  where r.slot_id=p_slot_id;

  if v_res_count > 0 or v_att_count > 0 then
    raise exception 'Cannot delete duty slot because it already has reservations or attendance logs.';
  end if;

  delete from public."TblP112DutySlots" where slot_id=p_slot_id;
  return jsonb_build_object('ok', true, 'slot_id', p_slot_id, 'action', 'deleted');
end $$;


grant execute on all functions in schema public to anon, authenticated;
