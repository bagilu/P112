# P112 SQL Functions / RPC 清單

本版不使用 Supabase Authentication，也不使用 Edge Function / CLI / npx deploy。
所有登入、權限、排班、簽到、簽退、工作紀錄與時數查詢，都透過 PostgreSQL SQL Functions / Supabase RPC 完成。

## 安裝方式

最簡單方式：

1. 在 Supabase SQL Editor 執行 `sql/p112_schema.sql`
   - 這個檔案已包含資料表、索引、RLS、權限與所有 function。

若希望分段貼上：

1. 先執行 `sql/p112_reset_drop_all.sql`
2. 再執行 `sql/p112_tables_and_policies_only.sql`
3. 再執行 `sql/functions/p112_all_rpc_functions.sql`
4. 最後執行 `sql/p112_bootstrap_example.sql`

## 核心 Functions

- `p112_bootstrap_sysadmin(email, password, display_name)`：建立第一位系統管理員。
- `p112_login(email, password, user_agent, ip)`：登入並建立 session token。
- `p112_logout(token)`：登出。
- `p112_get_current_user(token)`：讀取目前登入者。
- `p112_change_password(token, old_password, new_password)`：自行修改密碼。
- `p112_admin_create_user(token, email, display_name, password, system_role, must_change_password)`：sysadmin 建立使用者。
- `p112_admin_reset_password(token, user_id, new_password, must_change_password)`：sysadmin 重設密碼。
- `p112_create_unit(token, unit_name, unit_type, description, contact_email, photo_email)`：建立單位。
- `p112_get_units(token)`：取得目前使用者可見單位。
- `p112_add_unit_member(token, unit_id, user_id, unit_role)`：加入單位成員。
- `p112_list_users(token)`：列出使用者。
- `p112_create_duty_slot(token, unit_id, slot_date, start_time, end_time, note)`：建立值班時段。
- `p112_get_slots(token, unit_id, from, to)`：取得時段清單。
- `p112_create_reservation(token, slot_id, reservation_type)`：建立正式值班或待命預約。
- `p112_get_my_reservations(token, unit_id)`：取得自己的預約。
- `p112_checkin(token, reservation_id, user_agent, ip)`：簽到。
- `p112_checkout(token, reservation_id, work_summary, abnormal_note, work_item_ids, user_agent, ip)`：簽退與工作紀錄。
- `p112_get_work_items(token, unit_id)`：取得工作項目。
- `p112_admin_add_work_category(token, unit_id, category_name, description)`：新增工作分類。
- `p112_admin_add_work_item(token, unit_id, category_id, item_name, standard)`：新增工作項目。
- `p112_get_hour_summary(token, unit_id)`：取得時數統計。
- `p112_healthcheck()`：檢查 RPC 是否可用。
