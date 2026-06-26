# P112 LabDuty Multi-Unit V1 系統規格書

## 1. 系統名稱

中文：P112 我來值班  
英文：P112 LabDuty  
副標題：多單位值班排程、簽到簽退、工作紀錄與時數管理系統

## 2. 系統目的

本系統用於管理實驗室、辦公室、中心、公司部門或專案團隊之值班與工作紀錄。第一版重點是降低部署與使用門檻，因此不在系統內蒐集照片，而是透過 email 照片人工佐證方式處理到場證明。

## 3. 技術架構

- Frontend：HTML / CSS / JavaScript
- Hosting：GitHub Pages
- Backend：Supabase Auth + PostgreSQL + SQL RPC
- Deployment：Supabase Dashboard 手動貼 SQL，不使用 CLI

## 4. 功能需求

### 4.1 多單位管理

系統管理員可建立多個單位。每個單位有獨立設定、成員、排班、工作項目與報表。

### 4.2 成員管理

同一使用者可加入多個單位。角色包含 unit_admin、supervisor、worker。

### 4.3 排班

單位管理員可依日期、起迄時間與時段長度建立 duty slots。預設半小時。

### 4.4 預約

worker 可預約正式值班或待命。第一版允許每時段一位正式值班者與一位待命者。

### 4.5 簽到簽退

使用者可針對自己的預約簽到與簽退。系統記錄時間、user agent、工作摘要與異常回報。

### 4.6 工作項目

單位管理員可建立工作分類與工作項目。簽退時使用者需依單位設定勾選工作項目。

### 4.7 時數

系統以 `p112_hour_transactions` 作為時數帳本。簽退完成後產生 attendance transaction。

### 4.8 報表

管理端可查看出勤報表與累積時數報表，並可匯出 CSV。

## 5. 非功能需求

- 所有資料表與 function 使用 `p112_` 前綴。
- 系統不覆蓋既有 `config.js`，只提供 `config.sample.js`。
- 第一版不使用 Edge Function 部署。
- 第一版不使用照片上傳。
- 第一版不使用 Gmail API。
- 第一版保留 V2 現場碼架構但不啟用。

## 6. 安全與隱私

- 使用 Supabase Auth 進行登入。
- 使用 Row Level Security 控管資料存取。
- 使用者只能查看自己的出勤資料。
- 單位管理者只能查看自己管理單位的資料。
- 系統管理員可建立與管理單位。
- 照片不進入系統資料庫或 storage。

## 7. V2 擴充方向

- display 專用帳號
- 授權裝置 token
- 實驗室現場動態碼
- 自動缺席標記
- 待命補位自動判定
- Gmail/Drive 整合
- 管理審核流程

