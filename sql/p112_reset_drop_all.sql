-- P112 reset script for development/testing only. This deletes all P112 data.
-- Run this only if you need to clear a failed early installation.

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
