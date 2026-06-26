-- P112 first sysadmin bootstrap example
-- Run this after p112_schema.sql.
-- Change email, password, and display name before execution.
-- Password must be at least 8 characters.

select public.p112_bootstrap_sysadmin(
  'teacher@example.com',
  'ChangeMe2026!',
  '系統管理員'
);
