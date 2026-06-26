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
