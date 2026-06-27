# P112 我來值班｜LabDuty V1

## 版本定位

本版本是 P112 的重新整理版：

- 不使用 Supabase Authentication。
- 使用自建帳號表 `TblP112Users`。
- 使用自建登入 session 表 `TblP112Sessions`。
- 所有資料表名稱皆以 `TblP112` 開頭。
- 所有資料庫 function / RPC 皆以 `p112_` 開頭。
- 第一版不啟用現場動態碼與 device token。
- 第一版採用「系統簽到簽退 + email 照片人工佐證」。
- 支援多單位：不同實驗室、部門、公司、中心或專案團隊可共用同一套系統。
- 同一位使用者可加入多個單位，並在不同單位擁有不同角色。

## 技術架構

- Frontend: GitHub Pages 靜態網站
- Database: Supabase PostgreSQL
- Login: 自建 table-based login，不使用 Supabase Auth
- Security: 前端只呼叫 RPC；資料表啟用 RLS 且不開放直接存取
- Password: 使用 PostgreSQL `pgcrypto` 的 `crypt()` 儲存 hash，不存明文密碼

## 角色設計

### 系統層級

| 角色 | 說明 |
|---|---|
| `sysadmin` | 系統管理員，可建立單位、建立使用者、管理全系統 |
| `user` | 一般使用者，需加入單位後才能使用該單位功能 |

### 單位層級

| 角色 | 說明 |
|---|---|
| `unit_admin` | 管理該單位成員、排班、工作項目與報表 |
| `supervisor` | 可協助管理該單位時段與工作項目 |
| `worker` | 可預約、簽到、簽退、填寫工作紀錄 |

## 主要資料表

| 資料表 | 用途 |
|---|---|
| `TblP112Users` | 使用者、email、password hash、系統角色 |
| `TblP112Sessions` | 自建登入 session token |
| `TblP112Units` | 單位、實驗室、部門、公司或專案團隊 |
| `TblP112UnitSettings` | 單位設定 |
| `TblP112UnitMembers` | 使用者與單位關聯、單位角色 |
| `TblP112DutySlots` | 值班時段 |
| `TblP112Reservations` | 正式值班與待命預約 |
| `TblP112AttendanceLogs` | 簽到簽退與工作摘要 |
| `TblP112WorkCategories` | 工作分類 |
| `TblP112WorkItems` | 工作項目與完成標準 |
| `TblP112AttendanceWorkItems` | 出勤紀錄與工作項目關聯 |
| `TblP112HourTransactions` | 時數帳本 |
| `TblP112AbnormalFlags` | 異常紀錄 |
| `TblP112LabDevices` | V2 現場碼裝置預留 |
| `TblP112DisplaySessions` | V2 看板 session 預留 |

## 第一位管理員

執行 `sql/p112_schema.sql` 後，請執行：

```sql
select public.p112_bootstrap_sysadmin(
  'teacher@example.com',
  'ChangeMe2026!',
  '系統管理員'
);
```

之後即可用該 email 與密碼登入 `index.html`。

## 注意事項

1. 本版不使用 Supabase Auth，所以 Supabase Authentication 的 reset password、redirect URL、email template 都不影響本系統。
2. 密碼不存明文，資料表內欄位為 `password_hash`。
3. 忘記密碼時，由 `sysadmin` 在管理端重設，或直接呼叫 `p112_admin_reset_password()`。
4. 本版會 drop 舊有 `p112_` tables/functions 與 `TblP112` tables/functions，適合測試重裝。正式上線後請不要任意重新執行 schema。

## Functions / RPC 檔案位置

本版有 Functions。它們是 Supabase RPC 使用的 PostgreSQL SQL Functions，不是 Edge Functions。

完整 function 已包含於：

- `sql/p112_schema.sql`

另提供獨立 function 檔方便檢查與手動貼上：

- `sql/functions/p112_all_rpc_functions.sql`
- `docs/functions_list.md`

若要一次安裝，執行 `sql/p112_schema.sql` 即可。若要分段安裝，請參考 `docs/functions_list.md`。


## V1.1 更新：支援同一時段多人出勤

本版將原本「一個時段一位正式值班者」的限制改為容量制。管理者建立時段時可設定：

- 正式名額：`regular_capacity`
- 待命名額：`standby_capacity`

學生端會顯示「已預約人數 / 名額」，例如 `2/3`。只要尚未額滿，多位成員即可預約同一時段並各自簽到、簽退與累積時數。

部署時請重新執行 `sql/p112_schema.sql`。此檔案包含 reset/drop 機制，會清除前版 `p112_` 與 `TblP112` 物件後重建；正式資料上線後請勿直接使用 reset 版 schema。


## V1.1 更新：單位顯示與未預約臨時簽到

- 可預約時段表格加入「單位」欄位，避免多單位測試時誤判資料來源。
- 學生切換單位時，系統會自動重新讀取該單位的時段、我的預約、工作項目與時數。
- 新增 `p112_ad_hoc_checkin()`：允許未預約臨時簽到。系統會自動建立目前半小時的臨時時段與已簽到預約，並標記 `ad_hoc_checkin` 異常旗標供管理者確認。
- 一般流程仍建議先預約再簽到；臨時簽到用於臨時支援、忘記預約或特殊任務。


## 本版新增：管理端工具

本版以 `P112_LabDuty_Tbl_NoAuth_V1_AdHocUnitFix` 為基準，新增：

1. 管理端可讀取目前單位成員，並將成員退出該單位。退出採 `is_active=false`，不刪除歷史紀錄。
2. 管理端可讀取目前單位值班時段，並刪除尚未有人預約、簽到或簽退的時段。
3. 登入頁刪除較長的說明文字，底部改為 `P112 LabDuty | SBI Lab`。

若資料庫已部署舊版，不需重跑完整 schema，可執行：

```sql
-- SQL Editor
-- 執行 sql/p112_migration_admin_tools.sql
```
