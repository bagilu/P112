# P112 我來值班 / P112 LabDuty

**版本：Multi-Unit V1**  
**定位：多單位值班排程、簽到簽退、工作紀錄與時數管理系統**

本系統以 GitHub Pages 作為靜態網站，Supabase 作為資料庫與登入驗證。第一版採用「系統簽到簽退 + email 照片人工佐證」作為現場到場記錄方式，不在系統內儲存照片，也不啟用現場動態碼與授權裝置 token。現場碼相關資料表與函式保留為第二版升級路徑。

---

## 1. 核心設計

P112 V1 的核心不是單一實驗室，而是「多單位」架構。系統可以建立多個單位，例如：

- 智慧商情研究室
- 好玩實驗室
- 系辦公室
- 某中心
- 某公司部門
- 某專案團隊

同一位使用者可以同時加入多個單位，並在不同單位有不同角色、排班、出勤紀錄與時數統計。

---

## 2. 角色設計

### 2.1 系統層級角色

| 角色 | 說明 |
|---|---|
| `system_admin` | 可建立單位、管理全系統基礎設定 |
| `user` | 一般使用者 |

### 2.2 單位層級角色

| 角色 | 說明 |
|---|---|
| `unit_admin` | 管理該單位成員、時段、設定、工作項目、報表 |
| `supervisor` | 可查看該單位紀錄與報表 |
| `worker` | 可預約、簽到、簽退、填寫工作紀錄 |

---

## 3. 第一版功能範圍

### 3.1 學生端 / 工作者端

- 登入
- 選擇所屬單位
- 查看可預約時段
- 預約正式值班
- 預約待命
- 查看自己的預約
- 系統簽到
- 系統簽退
- 勾選工作項目
- 填寫工作摘要
- 填寫異常回報
- 查看自己的累積時數
- 若單位要求照片，依提示另外 email 給老師或主管

### 3.2 管理端

- 建立單位
- 選擇管理單位
- 新增單位成員
- 設定照片寄送信箱
- 設定是否要求 email 照片佐證
- 設定是否啟用待命
- 產生半小時或其他長度的排班時段
- 建立工作分類
- 建立工作項目與完成標準
- 查看出勤與工作紀錄
- 查看學生累積時數
- 匯出 CSV

### 3.3 保留但預設停用

- `display` 現場碼看板
- 授權裝置 token
- 現場動態碼
- lab device audit

---

## 4. 第一版刻意不做的功能

| 功能 | V1 狀態 | 原因 |
|---|---|---|
| 系統內照片上傳 | 不做 | 避免隱私、儲存空間與刪除管理問題 |
| 現場動態碼 | 保留但停用 | 第一版降低部署難度 |
| 授權裝置 token | 保留但停用 | 第二版再啟用 |
| Gmail 自動驗證照片 | 不做 | 涉及 Gmail API、權限與自動化複雜度 |
| Email 忘記密碼 | 不做 | 密碼重設由管理員在 Supabase Auth 後台處理 |
| GPS | 不做 | 隱私與準確性問題 |
| 固定 IP 限制 | 不做 | 動態 IP 不可靠 |
| 自動通知待命者 | 不做 | 通知送達與責任歸屬複雜 |

---

## 5. 主要資料表

| 資料表 | 用途 |
|---|---|
| `p112_profiles` | 使用者基本資料與系統角色 |
| `p112_units` | 單位資料，例如實驗室、部門、公司 |
| `p112_unit_members` | 使用者與單位的多對多關係 |
| `p112_unit_settings` | 每個單位的打卡、待命、照片 email 設定 |
| `p112_duty_slots` | 半小時或自訂長度的值班時段 |
| `p112_reservations` | 正式值班與待命預約 |
| `p112_attendance_logs` | 簽到、簽退、工作摘要與異常回報 |
| `p112_work_categories` | 工作分類 |
| `p112_work_items` | 工作項目與完成標準 |
| `p112_attendance_work_items` | 每次簽退完成的工作項目 |
| `p112_hour_transactions` | 時數加減帳本 |
| `p112_lab_devices` | V2 授權看板裝置預留 |
| `p112_lab_code_audit` | V2 現場碼事件稽核預留 |

---

## 6. 主要 SQL RPC / Function

| Function | 用途 |
|---|---|
| `p112_get_my_units()` | 取得登入者可使用的單位 |
| `p112_create_unit()` | system_admin 建立新單位 |
| `p112_add_unit_member_by_email()` | 將已存在 profile 的使用者加入單位 |
| `p112_generate_slots()` | 依日期、起迄時間、時段長度產生值班時段 |
| `p112_make_reservation()` | 預約正式值班或待命 |
| `p112_get_my_reservations()` | 取得自己的預約 |
| `p112_checkin()` | 簽到 |
| `p112_checkout()` | 簽退並建立時數紀錄 |
| `p112_get_my_hours()` | 查看自己的累積時數 |
| `p112_admin_attendance_report()` | 管理端出勤報表 |
| `p112_admin_hours_report()` | 管理端時數報表 |
| `p112_get_display_code()` | V2 現場碼預留 |

---

## 7. Email 照片佐證規則

第一版不在系統內收照片。若單位啟用 `require_photo_email`，學生簽到後應依系統提示，以 email 傳送照片給單位設定的 `photo_email`。

建議 email 主旨格式：

```text
P112簽到照片｜單位名稱｜姓名｜日期時間
```

照片保存責任由收件信箱管理者負責。系統僅保存簽到簽退、工作紀錄與時數資料。

---

## 8. 部署架構

```text
GitHub Pages
  index.html
  student.html
  admin.html
  display.html  # V2 預留
  assets/css/style.css
  assets/js/app.js
  config.js     # 由 config.sample.js 複製，不納入公開版

Supabase
  Auth
  PostgreSQL tables
  SQL RPC functions
  Row Level Security policies
```

---

## 9. 風格設定

本版採用「美式專業智庫風」：

- 深藍主色
- 白色卡片
- 金色重點
- 清楚表格
- 報告式排版
- 低裝飾、高可讀性

---

## 10. 版本路線

| 版本 | 核心 |
|---|---|
| V1 | 多單位、排班、簽到簽退、工作紀錄、時數、email 照片提醒 |
| V2 | 現場動態碼、display 專用帳號、授權裝置 token |
| V3 | Gmail/Drive 整合、自動通知、審核流程、進階統計 |

