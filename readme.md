# P112 我來值班 / P112 LabDuty

**副標題：** 實驗室值班預約、現場簽到、工作紀錄與時數管理系統  
**Architecture:** GitHub Pages static website + Supabase Auth + Supabase PostgreSQL/RPC

本專案是 P112 第一版 MVP。設計目標是讓實驗室輪值學生可以預約值班或待命，到現場後以「現場動態碼」簽到，離開時簽退並登錄工作項目與摘要。管理者可查看所有預約、出勤、工作內容、異常與時數。

---

## 1. 設計風格

本版採用「**美式專業智庫風**」：

- 深藍、灰白、金色點綴。
- 重視資訊層次、制度感與可信度。
- 避免過度裝飾，適合實驗室管理、研究團隊與正式場合。

---

## 2. 第一版功能範圍

### 2.1 學生端

- Email / Password 登入。
- 查看可預約時段。
- 預約正式值班。
- 預約待命。
- 輸入實驗室現場動態碼簽到。
- 輸入實驗室現場動態碼簽退。
- 簽退時勾選工作項目。
- 填寫工作摘要。
- 填寫異常回報。
- 查看個人累積時數。
- 查看個人預約與出勤紀錄。

### 2.2 管理端

- 建立 / 更新 `p112_profiles`。
- 批次建立半小時值班時段。
- 管理工作分類與工作項目。
- 查看所有出勤與工作紀錄。
- 查看學生累積時數。
- 匯出時數 CSV。
- 匯出出勤 CSV。
- 註冊本機為現場碼看板裝置。

### 2.3 現場碼看板端

採用：

> display 專用帳號 + 授權裝置 token + 現場動態碼

看板端只顯示：

- 六位數現場碼。
- 有效時間。
- 下一次更新倒數。
- 授權裝置名稱。

看板端不顯示學生個資，不提供管理功能。

---

## 3. 第一版刻意不做的功能

- 不上傳照片。
- 不使用 GPS。
- 不依賴固定 IP。
- 不提供 Email 忘記密碼。
- 不處理 Line / Email / SMS 通知送達證明。
- 不自動倒扣時數。
- 不讓工作項目直接換算時數。

---

## 4. 檔案結構

```text
P112_LabDuty_MVP/
├── index.html
├── student.html
├── admin.html
├── display.html
├── css/
│   └── styles.css
├── js/
│   ├── config.sample.js
│   ├── supabaseClient.js
│   ├── common.js
│   ├── student.js
│   ├── admin.js
│   └── display.js
├── sql/
│   └── p112_schema.sql
├── docs/
│   └── deployment_steps.md
└── supabase_functions/
    └── p112_lab_code/
        └── index.ts
```

---

## 5. Supabase 資料表

所有資料表皆以 `p112_` 開頭。

| 資料表 | 用途 |
|---|---|
| `p112_profiles` | 使用者 profile、角色、狀態。 |
| `p112_settings` | 系統設定，目前含現場碼 secret。 |
| `p112_duty_slots` | 半小時值班時段。 |
| `p112_reservations` | 正式值班與待命預約。 |
| `p112_attendance_logs` | 簽到、簽退、現場碼驗證、摘要、異常。 |
| `p112_work_categories` | 工作分類。 |
| `p112_work_items` | 工作項目與完成標準。 |
| `p112_attendance_work_items` | 某次出勤完成哪些工作項目。 |
| `p112_hour_transactions` | 時數交易紀錄。 |
| `p112_lab_devices` | 授權現場碼看板裝置。 |

---

## 6. Supabase Function / RPC

所有 function 皆以 `p112_` 開頭。

| Function | 用途 |
|---|---|
| `p112_touch_updated_at()` | 自動更新 `updated_at`。 |
| `p112_current_role()` | 取得目前登入者角色。 |
| `p112_is_admin()` | 判斷目前登入者是否為 admin。 |
| `p112_lab_code_bucket()` | 將時間切成 5 分鐘區段。 |
| `p112_generate_lab_code()` | 根據 secret 與時間區段產生六位數現場碼。 |
| `p112_verify_lab_code()` | 驗證學生輸入的現場碼。 |
| `p112_get_display_code()` | 驗證看板裝置 token 並回傳目前現場碼。 |
| `p112_create_slots()` | 批次建立半小時時段。 |

本版主要使用 Supabase SQL RPC，不需要 CLI / npx deploy。

---

## 7. 角色設計

| 角色 | 說明 |
|---|---|
| `student` | 學生，可預約、簽到、簽退、看自己的紀錄。 |
| `admin` | 管理者，可管理 profile、時段、工作項目、出勤、時數與看板裝置。 |
| `display` | 看板帳號，只用於登入 display.html。真正能否顯示現場碼仍需本機 device token。 |

---

## 8. 現場動態碼安全設計

現場碼不是寫在前端 JavaScript 裡，而是由 Supabase SQL RPC 產生。

流程：

1. 管理者在實驗室看板機上登入 admin。
2. 到管理端「看板裝置」頁註冊本機。
3. 系統產生隨機 token，將 token 存在該瀏覽器 localStorage。
4. 資料庫只存 token 的 SHA-256 hash。
5. 看板機用 display 帳號登入 display.html。
6. `display.html` 呼叫 `p112_get_display_code(device_id, token)`。
7. Supabase 驗證 token 後回傳現場碼。

---

## 9. 目前限制

這是 MVP，不是完整商用系統。

- 學生仍可能透過共謀方式取得現場碼；本系統目標是提高宿舍打卡成本，而不是達到監控等級防弊。
- 第一版出勤時數由簽到與簽退時間差自動計算；待命 10% 與補位規則可在第二版進一步自動化。
- 管理員建立 Auth 使用者與重設密碼仍需到 Supabase Dashboard 操作。
- 若重新部署新版，請不要覆蓋自己的 `js/config.js`。

---

## 10. 建議第二版功能

- 待命 10% 自動計入。
- 正式值班缺席後待命者補位自動判斷。
- 缺席統計與警示。
- 管理員人工時數調整介面。
- 每週 / 每月報表。
- 看板機心跳異常提醒。
- 工作項目完成頻率統計。
