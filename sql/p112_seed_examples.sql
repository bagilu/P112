-- P112 optional seed examples.
-- Replace UUIDs and emails before running.

-- 1. Create or update teacher profile as system_admin after creating Auth user.
-- insert into public.p112_profiles(user_id,email,display_name,system_role)
-- values('YOUR-AUTH-USER-UUID','teacher@example.edu.tw','林老師','system_admin')
-- on conflict(user_id) do update set system_role='system_admin', email=excluded.email, display_name=excluded.display_name;

-- 2. Create or update student profile after creating Auth user.
-- insert into public.p112_profiles(user_id,email,display_name,system_role)
-- values('STUDENT-AUTH-USER-UUID','student@example.edu.tw','王小明','user')
-- on conflict(user_id) do update set email=excluded.email, display_name=excluded.display_name;

-- 3. Work category/item examples are best created from admin.html after login.
