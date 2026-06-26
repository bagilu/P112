# P112 部署步驟

## 1. 建立或選擇 Supabase Project

可以使用新的 Supabase Project。由於本版不使用 Supabase Authentication，因此不會受到 P38 或其他專案的 Auth redirect 設定影響。

## 2. 執行資料庫 SQL

到 Supabase Dashboard：

SQL Editor → New query

貼上並執行：

```text
sql/p112_schema.sql
```

這份 SQL 會：

1. drop 舊版 `p112_` tables/functions
2. drop 新版 `TblP112` tables/functions
3. 建立所有 `TblP112...` 資料表
4. 建立所有 `p112_...` RPC functions
5. 啟用 RLS
6. 關閉直接 table access
7. 只允許透過 RPC 操作

## 3. 建立第一位 sysadmin

執行：

```sql
select public.p112_bootstrap_sysadmin(
  'teacher@example.com',
  'ChangeMe2026!',
  '系統管理員'
);
```

請改成您的 email 與密碼。密碼至少 8 碼。

## 4. 設定 config.js

複製：

```text
config.sample.js
```

改名成：

```text
config.js
```

填入 Supabase Project URL 與 anon key：

```js
window.P112_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-SUPABASE-ANON-KEY'
};
```

## 5. GitHub Pages 部署

把整個資料夾內容上傳到 GitHub repository。

Repository Settings → Pages → Deploy from branch → main / root。

等 GitHub Pages 網址生效後，打開 `index.html`。

## 6. 第一次登入

使用剛剛 `p112_bootstrap_sysadmin()` 設定的 email 與密碼登入。

登入後進入管理端：

1. 建立單位
2. 建立使用者
3. 將使用者加入單位
4. 建立值班時段
5. 建立工作分類與工作項目
6. 學生即可到學生端預約、簽到、簽退

## 7. 忘記密碼

本版不使用 email reset。

由 sysadmin 建立新密碼或重設密碼。可在未來版本擴充前端重設密碼介面。

## 8. V2 預留

`display.html`、`TblP112LabDevices`、`TblP112DisplaySessions` 保留給未來現場動態碼與裝置 token 功能。V1 不啟用。

## SQL Functions / RPC 補充說明

本版所有 function 都是 PostgreSQL SQL Functions，不是 Supabase Edge Functions。因此不需要 CLI、npx deploy，也沒有 `supabase/functions` 部署步驟。

請在 Supabase Dashboard → SQL Editor 手動貼上 SQL。

推薦方式：直接執行 `sql/p112_schema.sql`，它已包含完整 functions。

若您想分段檢查，可依序執行：

1. `sql/p112_reset_drop_all.sql`
2. `sql/p112_tables_and_policies_only.sql`
3. `sql/functions/p112_all_rpc_functions.sql`
4. `sql/p112_bootstrap_example.sql`


## V1.1 多人時段容量

若您已安裝前一版，請在測試階段直接重新執行：

```sql
sql/p112_schema.sql
```

本版會重建資料表與 functions。重建後，請再次執行 bootstrap sysadmin SQL。

建立時段時，管理端可以設定「正式名額」與「待命名額」。若正式名額為 2，同一時段即可有兩位正式出勤者各自打卡。


## 既有 MultiCapacity 版升級到 V1.1

如果您已經成功安裝前一版，而且不想清掉資料，請不要重新執行完整 `p112_schema.sql`。請改執行：

```sql
-- Supabase SQL Editor
-- 貼上 sql/p112_migration_ad_hoc_unitfix.sql 的內容後執行
```

然後重新上傳新版網站檔案，並用 `Ctrl + F5` 或網址加 `?v=adhoc-unitfix` 清除瀏覽器快取。

若是全新安裝或測試資料可清除，則可直接執行新版 `sql/p112_schema.sql`。
