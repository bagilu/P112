# P112 LabDuty Multi-Unit V1 部署步驟

以下步驟以 GitHub Pages + Supabase Dashboard 為主，不使用 CLI，也不使用 npx deploy。

---

## 一、建立 Supabase 專案

1. 登入 Supabase。
2. 建立新 Project。
3. 記下：
   - Project URL
   - anon public key
4. 前往 Authentication > Providers，確認 Email 登入啟用。

---

## 二、執行 SQL

1. 進入 Supabase Dashboard。
2. 開啟 SQL Editor。
3. 打開本 ZIP 內的：

```text
sql/p112_schema.sql
```

4. 全部複製貼到 SQL Editor。
5. 執行。
6. 若沒有錯誤，資料表、RLS policy 與 RPC function 會建立完成。

---

## 三、建立第一個管理員帳號

1. 前往 Authentication > Users。
2. 新增一個使用者，例如老師自己的 email。
3. 複製該使用者的 User UID。
4. 回到 SQL Editor，執行以下 SQL，請自行替換 UID 與 email：

```sql
insert into public.p112_profiles(user_id,email,display_name,system_role)
values('YOUR-AUTH-USER-UUID','your@email','老師','system_admin')
on conflict(user_id) do update
set system_role='system_admin', display_name=excluded.display_name, email=excluded.email;
```

---

## 四、設定網站 config.js

1. 將 `config.sample.js` 複製成 `config.js`。
2. 修改內容：

```js
window.P112_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-SUPABASE-ANON-KEY"
};
```

3. 注意：
   - 本系統只提供 `config.sample.js`。
   - 日後重新產生新版時，不應覆蓋您自己的 `config.js`。
   - 若 GitHub repository 是公開的，請自行評估是否公開 anon key；Supabase anon key 本來可用於前端，但 RLS 必須正確啟用。

---

## 五、部署到 GitHub Pages

1. 建立 GitHub repository，例如：

```text
P112_LabDuty_MultiUnit_V1
```

2. 上傳 ZIP 解壓縮後資料夾中的所有檔案。
3. 確認 repository 根目錄有：

```text
index.html
student.html
admin.html
config.js
assets/
sql/
docs/
readme.md
```

4. 到 GitHub repository > Settings > Pages。
5. Source 選擇：Deploy from a branch。
6. Branch 選擇：main / root。
7. 儲存。
8. 等待 GitHub Pages 發布。

---

## 六、第一次使用流程

1. 開啟網站首頁 `index.html`。
2. 使用 system_admin 帳號登入。
3. 進入管理端 `admin.html`。
4. 建立第一個單位，例如「智慧商情研究室」。
5. 設定照片寄送信箱。
6. 建立學生帳號：
   - 到 Supabase Auth 建立學生使用者。
   - 到 SQL Editor 新增學生 profile。
7. 在管理端以學生 email 加入單位。
8. 建立時段。
9. 建立工作分類與工作項目。
10. 學生登入後即可預約、簽到、簽退。

---

## 七、新增學生 profile 範例

建立 Auth 使用者後，複製 UID，執行：

```sql
insert into public.p112_profiles(user_id,email,display_name,system_role)
values('STUDENT-AUTH-USER-UUID','student@example.edu.tw','王小明','user')
on conflict(user_id) do update
set email=excluded.email, display_name=excluded.display_name;
```

接著在管理端用 email 把學生加入單位。

---

## 八、建議的第一批工作分類

可在管理端建立：

1. 環境整理
2. 設備檢查
3. 展示維護
4. 專案協助
5. 老師指定任務

---

## 九、建議的第一批工作項目

### 環境整理

- 桌面整理：桌面無垃圾，公共物品歸位。
- 白板整理：保留指定內容，其餘擦除；白板筆與板擦歸位。
- 垃圾處理：垃圾桶滿 80% 以上需打包並更換垃圾袋。

### 設備檢查

- 公共電腦檢查：確認可開機、可連網、可登入展示頁面。
- 展示螢幕檢查：指定專案頁面可正常顯示，無錯誤畫面。

### 專案協助

- P101 展示維護
- P104 WhisperTour 測試
- P109 請小聲喔測試
- P110 SmoothRide 資料整理
- P112 系統測試

---

## 十、V1 的照片 email 操作建議

若單位啟用照片 email 佐證，學生簽到後請寄信給單位設定的信箱。

建議主旨：

```text
P112簽到照片｜單位名稱｜姓名｜日期時間
```

系統不會自動檢查 email 是否送達。此設計是第一版簡化策略。

---

## 十一、V2 預留功能說明

資料庫已保留：

- `p112_lab_devices`
- `p112_lab_code_audit`
- `p112_get_display_code()`
- `display.html`

但 V1 不建議啟用。若未來要防止宿舍打卡，可升級為：

```text
display 專用帳號 + 授權裝置 token + 現場動態碼
```

---

## 十二、常見問題

### 1. 為什麼不做忘記密碼 email？

第一版為降低複雜度，密碼重設由管理員在 Supabase Auth 後台處理。

### 2. 為什麼不在系統內上傳照片？

避免隱私、儲存、權限與刪除管理問題。第一版改由學生 email 給老師或主管。

### 3. 同一學生可以加入多個單位嗎？

可以。`p112_unit_members` 支援同一位使用者加入多個單位。

### 4. 不同單位的時數會混在一起嗎？

不會。所有時段、預約、簽到、時數紀錄都有 `unit_id`。

