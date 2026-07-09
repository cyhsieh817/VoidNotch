# App/ — Xcode app target 源碼（SwiftUI 層）

> 此目錄由 `VoidNotch.xcodeproj` 的 macOS app target 編譯。它依賴 SwiftUI + DynamicNotchKit 的 `@Entry` 巨集，
> 須以**完整 Xcode**（非 CommandLineTools）編譯（DynamicNotchKit 依賴 SwiftUI `@Entry` 巨集）。

請直接開：

```text
/Users/cyuh/Downloads/APPDev/102_Github/VoidNotch/VoidNotch.xcodeproj
```

## 為何與 `Sources/` 分離

| 目錄 | 內容 | 編譯環境 |
|:--|:--|:--|
| `Sources/SystemMonitor`, `Sources/CSensors` | 純資料層（已在真機 `swift run vn-probe` 驗證） | CommandLineTools 即可 |
| `App/` | SwiftUI 外殼 / widget / @main | **須完整 Xcode** |

## 接線狀態

- [x] 建 macOS App target（SwiftUI、macOS 14+、LSUIElement = YES 無 Dock 圖示）。
- [x] 加 DynamicNotchKit SPM 依賴：`https://github.com/MrKai77/DynamicNotchKit`。
- [x] 將本地 SPM 套件 `VoidNotch`（本 repo 根，提供 `SystemMonitor`）加入 app target 依賴。
- [x] 把 `App/**/*.swift` 加入 app target；`App/VoidNotch.entitlements` 設為 target 的 Code Signing Entitlements。
- [x] 開發階段使用 Sign to Run Locally；發佈階段再切 Developer ID Application + Hardened Runtime（見 `distribution-and-entitlements.md` §4）。
- [x] CLI build 通過。
- [x] Build & Run → 有瀏海 MacBook 已看到 compact 條；現行啟動後進入 compact，預設左側系統資訊常開、右側 AI 縮入劉海。
- [x] Token provider adapter → app target build 通過。
- [x] 設定入口 → 狀態列 VoidNotch 圖示開啟 `VoidNotch Settings...`。
- [x] Gemini (Agy) quota adapter → 透過 provider pipeline 讀 Gemini quota window。
- [x] Gemini (Agy) 多帳號管理 → Settings 可匯入目前 Antigravity OAuth credentials、貼上 refresh token/OAuth JSON/Antigravity-Manager export JSON、匯出 refresh-token JSON、列出/切換/skip/移除 Google account，active account 會 scope quota fetch；帳號列會顯示 live quota / status / Best account，手動或 403/ban 類錯誤標記的 skipped 帳號會排除於刷新與推薦之外。
- [x] Token 展開 UI → provider icon、5 小時/每週 quota 條、剩餘/已用切換。
- [x] Agent Activity scaffold → Codex / Claude / Gemini (Agy) lifecycle widget 已接入 app target。
- [x] PeonPing JSONL relay adapter → App 端讀取 `agent-events.jsonl`，hook 端提供 relay script。
- [x] Notch Layout → `Left metrics` / `Right AI` 可各自選擇 `Open` 或 `Collapsed`；collapsed 側不渲染 widget，避免實體劉海外側殘留。
- [x] Click 行為 → compact 狀態滑鼠移入 notch 後左鍵點擊才展開 dashboard；右鍵點擊 notch 會開啟 VoidNotch Settings；離開 dashboard 後會自動收回 compact。
- [x] Widget Visibility → VoidNotch Settings 可切換 Token / Agent Activity 顯示；System Metrics 固定保留於 dashboard。
- [ ] Token 真機資料驗收 → 對照 Claude/Codex/Gemini (Agy) 等本機紀錄與 provider dashboard。
- [ ] PeonPing 真機事件驗收 → 註冊 Claude/Codex/Gemini (Agy) hooks 後對照 notch 顯示。

## 檔案地圖

```
App/
├─ VoidNotchApp.swift          @main + AppDelegate（組裝全鏈）
├─ VoidNotch.entitlements      非沙箱 + disable-library-validation
├─ Monitors/
│  ├─ ObservableSystemMonitor  ← 包裝已驗證的 SystemMonitorManager（live update）
│  ├─ TokenStore               ← Phase 3 provider 狀態 + 5 分鐘輪詢
│  ├─ AgentActivityStore        ← agent lifecycle events + PeonPing JSONL reader
│  ├─ CodexBarTokenUsageProvider ← token usage adapter
│  └─ CodexBarTokenAccountManager ← AGY token-account bridge
├─ Widgets/
│  ├─ NotchWidget              protocol（解硬編碼）
│  ├─ WidgetRegistry           [any NotchWidget] 管理
│  ├─ SystemWidget             消費真實 CPU/RAM/溫度
│  ├─ TokenWidget              展示 token / cost / quota / provider 狀態
│  └─ AgentActivityWidget      展示 agent lifecycle timeline
├─ Settings/
│  └─ ProviderSettingsView     provider 勾選 + refresh + Notch Layout + widget visibility
└─ Shell/
   └─ NotchShell               DynamicNotchKit 接縫（API 已 spike 驗證）
```

## 驗證狀態

- ✅ 資料層在真機跑通（CPU 對 `top`、RAM 對 sysctl、溫度 IOHID 實測）
- ✅ SwiftUI 層已由 Xcode app target 編譯，且真機 compact 條曾出現；現行 compact 支援左/右側 Open/Collapsed
- ✅ Token usage adapter 已可建置；unsupported provider 會在 UI 顯示狀態
- ✅ Gemini (Agy) 已接 quota adapter；顯示主要 quota 使用百分比與來源
- ✅ Gemini (Agy) 多帳號管理已接 Settings：active Google account 會注入 CodexBarCore fetch context，並支援 token/JSON import、export、skip/enable、per-account live quota / Best account 標記
- ✅ Token widget 已支援多 quota window 與剩餘/已用顯示模式
- ✅ Agent Activity 初版已接入；PeonPing JSONL relay adapter 已連線
- ✅ Collapsed 側 compact slot 保持 0 寬內容，控制不外顯於 notch 本體
- ✅ Compact hover 後左鍵展開、右鍵開設定、離開 dashboard 後自動收回的控制迴圈已接入
- ✅ Expanded dashboard 頂部已加額外留白，避免內容直接貼齊螢幕頂邊被遮住
- ✅ CodexBarCore real keychain cache 在 VoidNotch process 內停用，避免 `CodexBar Cache` 錯品牌系統提示
- ✅ Widget Visibility 已接入 VoidNotch Settings；Token / Agent Activity 可隱藏
- ⏳ 有瀏海 MacBook 需重新驗收：左/右任一側設為 `Collapsed` 後，該側實體劉海外側不得有殘留
- ⏳ Click-to-expand / 右鍵設定 / 自動收回需真機手感驗收
- ⏳ Widget Visibility 需真機操作驗收：切換後 dashboard expanded 應即時反映
- ⏳ PeonPing hook 註冊與真實事件顯示仍待完成
- ⏳ live update、30 分鐘常駐穩定性、Activity Monitor 對照仍待完成
