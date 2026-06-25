# P112 我來值班：逐步部署指引

本指引假設您使用：

- GitHub Pages 作為靜態網站。
- Supabase 作為 Auth + Database + SQL RPC。
- 不使用 CLI / npx deploy。
- 不使用 Edge Function 部署。

---

## Step 1：建立 Supabase Project

1. 登入 Supabase。
2. 建立新 Project。
3. 記下：
   - Project URL
   - anon public key
4. 到 Project Settings → API 可找到上述資訊。

---

## Step 2：執行 SQL

1. 開啟 Supabase Dashboard。
2. 進入 SQL Editor。
3. 開啟本專案檔案：

```text
sql/p112_schema.sql
```

4. 全部複製。
5. 貼到 SQL Editor。
6. 執行。

執行後應建立：

- `p112_profiles`
- `p112_duty_slots`
- `p112_reservations`
- `p112_attendance_logs`
- `p112_work_categories`
- `p112_work_items`
- `p112_hour_transactions`
- `p112_lab_devices`
- 以及所有 `p112_` 開頭的 RPC functions。

---

## Step 3：建立第一個管理員帳號

1. 到 Supabase Dashboard → Authentication → Users。
2. 建立一個使用者，例如老師自己的 Email。
3. 複製該使用者的 User UID。
4. 到 Table Editor → `p112_profiles` 新增一筆：

| 欄位 | 值 |
|---|---|
| id | 剛剛複製的 User UID |
| email | 老師 Email |
| full_name | 老師姓名 |
| role | `admin` |
| status | `active` |

5. 回到網站 `index.html`，用該帳號登入。

---

## Step 4：建立學生帳號

對每位學生：

1. 到 Supabase Authentication → Users 新增使用者。
2. 設定初始密碼。
3. 複製 User UID。
4. 進入網站管理端 `admin.html`。
5. 到「學生」頁籤建立 profile：
   - User UUID
   - Email
   - 姓名
   - 角色：`student`
   - 狀態：`active`

密碼遺失時，第一版不使用 Email 忘記密碼，請在 Supabase Authentication Dashboard 手動重設。

---

## Step 5：建立 display 專用帳號

1. 到 Supabase Authentication → Users 新增一個帳號，例如：

```text
display01@example.com
```

2. 複製 User UID。
3. 到管理端或 Table Editor 建立 profile：

| 欄位 | 值 |
|---|---|
| id | display 帳號的 User UID |
| email | display 帳號 Email |
| full_name | 實驗室看板機 |
| role | `display` |
| status | `active` |

---

## Step 6：設定 config.js

1. 到 `js/` 資料夾。
2. 複製：

```text
config.sample.js
```

3. 重新命名為：

```text
config.js
```

4. 填入 Supabase URL 與 anon key：

```javascript
window.P112_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT-ID.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-SUPABASE-ANON-KEY",
  APP_NAME: "P112 我來值班",
  TIMEZONE: "Asia/Taipei"
};
```

重要：之後若重新產生新版程式，請保留自己的 `config.js`，不要覆蓋。

---

## Step 7：上傳 GitHub Pages

1. 建立 GitHub repository。
2. 將整個 `P112_LabDuty_MVP` 資料夾內的檔案上傳。
3. 確認包含：

```text
index.html
student.html
admin.html
display.html
css/
js/
sql/
docs/
readme.md
```

4. 到 repository Settings → Pages。
5. Source 選擇 `Deploy from a branch`。
6. Branch 選擇 `main` / root。
7. 儲存。
8. 等待 GitHub Pages 產生網址。

---

## Step 8：建立值班時段

1. 以 admin 登入網站。
2. 進入 `admin.html`。
3. 到「時段」頁籤。
4. 選擇日期、開始時間、結束時間、間隔分鐘。
5. 按「批次建立時段」。

第一版預設每半小時為一格。

---

## Step 9：註冊實驗室看板機

請在「實驗室現場那台電腦或平板」操作。

1. 在看板機上開啟網站。
2. 用 admin 帳號登入。
3. 進入 `admin.html`。
4. 到「看板裝置」頁籤。
5. 輸入裝置名稱，例如：

```text
實驗室看板機01
```

6. 按「註冊本機」。
7. 系統會把 device token 存到該瀏覽器 localStorage。
8. 登出 admin。
9. 用 display 帳號登入 `display.html`。
10. 若授權成功，就會看到六位數現場碼。

---

## Step 10：學生使用流程

1. 學生登入 `student.html`。
2. 查看可預約時段。
3. 預約正式值班或待命。
4. 到實驗室後，看現場碼看板。
5. 在學生端輸入六位數現場碼簽到。
6. 工作完成後，輸入新的現場碼簽退。
7. 勾選工作項目。
8. 填寫工作摘要。
9. 填寫異常回報，若無則填「無」。
10. 系統自動產生出勤時數交易。

---

## Step 11：管理者查看紀錄

管理者可在 `admin.html` 查看：

- 學生 profile。
- 開放時段。
- 工作分類與工作項目。
- 出勤與工作紀錄。
- 異常紀錄。
- 學生累積時數。
- 看板裝置最後連線時間。

---

## Step 12：重要維護提醒

- 不要公開 `config.js` 以外的敏感金鑰；本系統只使用 anon key，不使用 service role key。
- service role key 絕對不要放到 GitHub Pages。
- 若看板機無法顯示現場碼，先檢查：
  1. 是否用 display 帳號登入。
  2. 該瀏覽器是否曾由 admin 註冊為看板裝置。
  3. `p112_lab_devices` 中該裝置是否 `is_active = true`。
  4. config.js 是否正確。
- 若學生登入後看不到資料，檢查 `p112_profiles` 是否有對應該 Auth user id。
