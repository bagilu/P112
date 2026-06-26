# P112 系統規格書

## 系統名稱

P112 我來值班 / P112 LabDuty

## 系統目的

建立一套多單位值班管理系統，使實驗室、部門、公司、中心或專案團隊能夠管理工作時段、正式值班、待命預約、簽到簽退、工作項目、異常回報與時數統計。

## V1 範圍

### 包含

- 自建帳號密碼登入
- sysadmin / user 系統角色
- unit_admin / supervisor / worker 單位角色
- 多單位管理
- 同一使用者加入多個單位
- 半小時或自訂時段排班
- 正式值班與待命預約
- 簽到與簽退
- 工作項目清單
- 工作摘要與異常回報
- 時數交易紀錄
- 累積時數摘要
- email 照片人工佐證提醒

### 不包含

- Supabase Authentication
- Supabase email reset password
- Gmail API
- 系統內照片上傳
- GPS
- 現場動態碼實際啟用
- 裝置 token 實際啟用

## 帳號安全

密碼不得以明文儲存。系統使用 PostgreSQL `pgcrypto` 產生 `password_hash`。登入成功後產生隨機 session token，前端儲存在 localStorage。

## 權限模型

所有資料表啟用 RLS，不提供前端直接 select/insert/update/delete。前端只呼叫 `p112_` RPC functions，由 function 檢查 session token、系統角色與單位角色。

## 照片佐證策略

V1 不在系統內儲存照片。若單位設定 `photo_email`，學生簽到後由系統提醒寄送照片 email 給管理者。照片保存責任不在 P112 資料庫內。

## 命名規則

- Tables: `TblP112...`
- Functions: `p112_...`
- CSS/JS 檔案：一般靜態檔命名

## V1.1 多人同時出勤修正

本版支援同一個時段安排多位正式出勤者與多位待命支援者。

### 資料結構

`TblP112DutySlots` 新增／使用以下欄位：

- `regular_capacity`：正式出勤名額，預設 1。
- `standby_capacity`：待命支援名額，預設 1；管理介面預設可設為 0。

`TblP112Reservations` 不再限制同一時段只能有一位 `regular` 或一位 `standby`。系統改由 `p112_create_reservation()` 檢查容量。

### 預約規則

- 同一時段可有多位 `regular` 預約者，數量不得超過 `regular_capacity`。
- 同一時段可有多位 `standby` 預約者，數量不得超過 `standby_capacity`。
- 同一位使用者不可在同一時段重複建立同類型有效預約。
- 每位出勤者各自簽到、簽退、勾選工作項目、填寫摘要，並各自產生時數交易紀錄。


## V1.1 更新：單位顯示與未預約臨時簽到

- 可預約時段表格加入「單位」欄位，避免多單位測試時誤判資料來源。
- 學生切換單位時，系統會自動重新讀取該單位的時段、我的預約、工作項目與時數。
- 新增 `p112_ad_hoc_checkin()`：允許未預約臨時簽到。系統會自動建立目前半小時的臨時時段與已簽到預約，並標記 `ad_hoc_checkin` 異常旗標供管理者確認。
- 一般流程仍建議先預約再簽到；臨時簽到用於臨時支援、忘記預約或特殊任務。
