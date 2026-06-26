-- P112 migration: unit-filter display fix + ad hoc check-in
-- Use this on an existing MultiCapacity deployment without dropping data.
-- 1) p112_get_slots return signature is changed to include unit_id and unit_name, so it must be dropped first.

drop function if exists public.p112_get_slots(text, uuid, date, date);

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



-- Add unplanned / ad-hoc check-in function.

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



grant execute on function public.p112_get_slots(text, uuid, date, date) to anon, authenticated;
grant execute on function public.p112_ad_hoc_checkin(text, uuid, text, text) to anon, authenticated;
