# VoidNotch

macOS Notch 系統監控 + AI Token 追蹤工具。

將 MacBook 的 Notch 區域變成即時儀表板：CPU / RAM / 溫度 / AI Provider Token 流量。

## 目前狀態

> 最後更新：2026-07-09

- Notch compact / expanded dashboard：系統監控（CPU、RAM、Disk、Network、Battery、Health、Processes…）+ AI Token / Agent 用量。
- 純 CLI 建置與打包（`Package.swift` + `scripts/make_app.sh`），也可開 `VoidNotch.xcodeproj`。
- UI：**zh-TW / EN** 語言切換；Settings 可調 compact 兩側內容、寬高、system metrics 顯示項目。
- Token：Codex / Claude / Copilot / Gemini (Agy) / **Grok** 等（via CodexBarCore）；unsupported provider 會明確標示。
- 已知限制：部分機型 IOHID 溫度可能讀不到（best-effort，顯示 `—`）；GPU util 亦為 best-effort。

## 建置與掛載（免開 Xcode）

機器需裝完整 Xcode 工具鏈（`xcode-select -p` 指向 Xcode.app；因 DynamicNotchKit 用到 SwiftUI `@Entry` 巨集，CommandLineTools-only 編不過），但**全程不需開 Xcode GUI**：

```bash
scripts/make_app.sh            # swift build -c release → build/VoidNotch.app（ad-hoc 簽名）
scripts/make_app.sh --run      # 打包後直接啟動
scripts/make_app.sh --install  # 打包後掛到 /Applications 並啟動
```

想用 Xcode（Preview / 除錯）時再開 `VoidNotch.xcodeproj`；其依賴已改走本地 `Package.swift`，兩條路徑用同一組 pin。

## 技術棧

- Swift / SwiftUI + AppKit
- macOS 14+（Sonoma）
- SPM (Swift Package Manager)

## 架構來源

| 層 | 來源 Repo | 用途 |
|:---|:---------|:-----|
| Notch UI 外殼 | [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | compact 左/右側可各自常開或縮起，並支援 expanded dashboard；需完整 Xcode app target |
| 系統監控 | [Stats](https://github.com/exelban/stats) | CPU/RAM/Apple Silicon 溫度邏輯參考與移植 |
| Token 追蹤 | [CodexBar](https://github.com/steipete/CodexBar) | v2 使用 CodexBarCore；app target revision 釘選，adapter 已接線 |
| 授權不相容參考 | [boring.notch](https://github.com/TheBoredTeam/boring.notch) | GPL-3.0，僅讀架構，不 vendoring |

## 功能規劃

- [x] CPU / RAM / Disk / Network / Battery / Health / Processes
- [x] 溫度（CPU / GPU / SOC，best-effort）
- [x] System metrics 可選顯示；compact 兩側內容與長寬可調
- [x] Widget 顯示控制（System / Token / Agent）
- [x] AI Provider Token / quota（CodexBarCore adapter）
- [x] 狀態列開啟 Notch dashboard
- [x] Compact：左鍵展開、右鍵設定、離開後收回

## 快速驗證

```bash
swift run vn-selftest
swift test
swift run vn-probe 5
swift build --product VoidNotch
xcodebuild -project VoidNotch.xcodeproj -scheme VoidNotch -configuration Debug -destination platform=macOS build
```

`vn-selftest` 是自帶斷言 smoke test；`swift test` 是 XCTest 正式單元測試；`vn-probe` 會列印即時 CPU/RAM/溫度供人工對照；`swift build --product VoidNotch` 是免 Xcode 的 App 編譯 gate。

## 目前檔案分層

| 位置 | 狀態 | 說明 |
|:---|:---|:---|
| `Sources/SystemMonitor` | 已可驗證 | 純資料層，零 SwiftUI，供 CLI 與 App 使用 |
| `Sources/CSensors` | 已可驗證 | Apple Silicon IOHID 溫度橋接，非 Mac App Store 路線 |
| `Sources/vn-probe` | 已可驗證 | 即時探針 |
| `Sources/vn-selftest` | 已可驗證 | CommandLineTools 可跑的自測 |
| `Tests/SystemMonitorTests` | 已可驗證 | 使用 XCTest，需 Xcode toolchain |
| `App/` | 已接線 | SwiftUI / DynamicNotchKit app 源碼；SPM executable target 與 `VoidNotch.xcodeproj` 皆可編譯 |
| `VoidNotch.xcodeproj` | 已可建置 | Xcode 入口（Preview/除錯用）；依賴走本地 `Package.swift` 依賴圖 |
| `scripts/make_app.sh` | 已可驗證 | 免 Xcode CLI 打包：swift build → .app bundle → ad-hoc 簽名 → 掛載 |

## 文件

- `README.md` — 本檔
- `CHANGELOG.md` — 公開版本紀錄
- `LICENSE` / `THIRD-PARTY-NOTICES.md` — 授權與第三方聲明
- `App/README.md` — App target 備註

內部開發筆記（`docs/`、`ACTIONLOG.md` 等）預設不納入公開 repo（見 `.gitignore`）。
