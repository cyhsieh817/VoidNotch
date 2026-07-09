# 第三方軟體聲明（Third-Party Notices）

VoidNotch（MIT）包含或衍生自下列第三方軟體。各上游皆為 MIT 授權，VoidNotch
保留其著作權標示以盡 MIT 義務。完整授權條文以各上游 repo 的 LICENSE 為準。

---

## Stats

- 來源: https://github.com/exelban/stats
- 授權: MIT
- 著作權: Copyright © 2019 Serhiy Mytrovtsiy
- 用途: VoidNotch **移植/改寫** 其系統監控邏輯：
  - `Sources/CSensors/{CSensors.h, sensors.m}` — 移植自 Stats `Modules/Sensors/{bridge.h, reader.m}`（Apple Silicon IOHID 溫度列舉）
  - `Sources/SystemMonitor/ThermalReader.swift` — 溫度彙整邏輯（依 Stats 感測器命名前綴）
  - `Sources/SystemMonitor/{CPUReader, RAMReader}.swift` — Mach syscall 取樣演算法參考自 Stats `Modules/{CPU,RAM}/readers.swift`
    （CPU/RAM 本身僅用 Apple 公開 API，演算法形態取法 Stats）

> ⚠️ 移植檔案的檔頭均已標注「移植自 Stats（MIT, © 2019 Serhiy Mytrovtsiy）」。

## DynamicNotchKit

- 來源: https://github.com/MrKai77/DynamicNotchKit
- 授權: MIT
- 著作權: Copyright © Kai Azim
- 用途: notch 外殼 SPM 依賴（`App/Shell/NotchShell.swift` 封裝其 `DynamicNotch`）。
  以套件形式連結，不複製原始碼。

## CodexBar / CodexBarCore

- 來源: https://github.com/steipete/CodexBar
- 授權: MIT
- 著作權: Copyright © Peter Steinberger
- 用途: AI Token 用量抓取（**v2 規劃**）。以 SPM 依賴連結 `CodexBarCore`，不複製原始碼。
  目前僅 spike 驗證（見 `docs/research/codexbarcore-spike.md`），尚未併入 v1。

---

## 純技術參考（未採用任何程式碼）

## boring.notch

- 來源: https://github.com/TheBoredTeam/boring.notch
- 授權: **GPL-3.0**
- 狀態: **僅作設計觀念參考，未複製任何一行程式碼**。因 GPL-3.0 copyleft 與 VoidNotch 的
  MIT + open-core 不相容，刻意隔離。見 `docs/research/distribution-and-entitlements.md`。
