# 第三方軟體聲明（Third-Party Notices）

VoidNotch 包含或衍生自下列第三方軟體。各上游授權條文以其 repo 的 LICENSE 為準，
並就衝突部分優先於本專案自身的授權。

## 授權結構（2026-07-13 起）

| 版本 | 範圍 | 授權 |
|:--|:--|:--|
| **Community Edition** | 公開 repo tag `v0.6.0`（commit 4ebcf31） | MIT，見 `LICENSE-COMMUNITY-MIT.txt` |
| **VoidNotch Pro** | `v0.6.0` 之後的全部加層（Agent 層等） | 專有授權，見 `LICENSE` |

> **清單原則（重要，勿退回 Package.resolved 全表）**
>
> 本清單依 **product 依賴圖**核對「實際被連結進二進位」的元件，
> **不是**照 `Package.resolved` 全表列舉。`Package.resolved` 列的是 SPM *解析* 到的
> 所有套件（含未被連結的兄弟 product），照它全列會**過度列舉**，聲明不實。
>
> 真相源：`Package.swift` 只宣告兩個 product 依賴——
> `DynamicNotchKit` 與 `CodexBarCore`。二進位符號表與字串表皆無
> Sparkle / KeyboardShortcuts / Vortex / Commander 命中（2026-07-13 實測）。

---

## 一、程式碼移植（非僅連結，已改寫進本專案）

### Stats

- 來源: https://github.com/exelban/stats
- 授權: MIT
- 著作權: Copyright © 2019 Serhiy Mytrovtsiy
- 用途: VoidNotch **移植/改寫** 其系統監控邏輯：
  - `Sources/CSensors/{CSensors.h, sensors.m}` — 移植自 Stats `Modules/Sensors/{bridge.h, reader.m}`（Apple Silicon IOHID 溫度列舉）
  - `Sources/SystemMonitor/ThermalReader.swift` — 溫度彙整邏輯（依 Stats 感測器命名前綴）
  - `Sources/SystemMonitor/{CPUReader, RAMReader}.swift` — Mach syscall 取樣演算法參考自 Stats `Modules/{CPU,RAM}/readers.swift`
    （CPU/RAM 本身僅用 Apple 公開 API，演算法形態取法 Stats）

> ⚠️ 移植檔案的檔頭均已標注「移植自 Stats（MIT, © 2019 Serhiy Mytrovtsiy）」。
> MIT 允許改作與商業散布，惟必須保留著作權與授權聲明——本節即為履行該義務。

---

## 二、實際連結進二進位的相依（皆 permissive · 無 copyleft）

VoidNotch app 直接連結 `DynamicNotchKit` 與 `CodexBarCore`；後者遞移帶入
swift-crypto / swift-log / SweetCookieKit（swift-asn1 再經 swift-crypto）。

### DynamicNotchKit（直接）
- https://github.com/MrKai77/DynamicNotchKit · MIT · © 2025 Kai Azim · notch 外殼 SPM 依賴。

### CodexBar / CodexBarCore（直接）
- https://github.com/steipete/CodexBar · MIT · © 2026 Peter Steinberger · AI token 用量抓取。

### SweetCookieKit（經 CodexBarCore 遞移）
- https://github.com/steipete/SweetCookieKit · MIT · © 2026 Peter Steinberger · 瀏覽器 cookie 讀取。

### swift-crypto（經 CodexBarCore 遞移）
- https://github.com/apple/swift-crypto · Apache-2.0（含 NOTICE）· © Apple Inc. 及 Swift 專案貢獻者。

### swift-asn1（經 swift-crypto 遞移）
- https://github.com/apple/swift-asn1 · Apache-2.0（含 NOTICE）· © Apple Inc. 及 Swift 專案貢獻者。

### swift-log（經 CodexBarCore 遞移）
- https://github.com/apple/swift-log · Apache-2.0（含 NOTICE）· © Apple Inc. 及 Swift 專案貢獻者。

### MIT 授權條文

下列 MIT 條文適用於上列標示 MIT 的每一個元件，著作權標示各依其所列：

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache-2.0 授權聲明

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
these files except in compliance with the License. You may obtain a copy at:

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied.

VoidNotch **未修改**上述三個 Apache-2.0 套件（僅以 SPM 連結）。各上游發行版隨附
`NOTICE` 檔，其內容以引用方式併入本檔。

---

## 三、目前未連結，日後若引用才需補列

- **Sparkle**（MIT 主體 + BSD-2-Clause 元件：bsdiff、sais-lite、SUDSAVerifier）
  · 若日後啟用自動更新私有 feed 才會連結。
- **Commander / KeyboardShortcuts / Vortex** · 屬 CodexBar 的 CLI/app 層 product，
  **未**被 `CodexBarCore` 連結，故目前不進二進位。

> 這三行不是遺漏，是刻意排除。`Package.resolved` 會列出它們（SPM 解析所致），
> 但列進聲明即為過度列舉。改動相依後請重新核對 `Package.swift` 的 product 依賴圖。

---

## 四、純技術參考（未採用任何程式碼）

### boring.notch
- https://github.com/TheBoredTeam/boring.notch · **GPL-3.0**
- **僅作設計觀念參考，未複製任何一行程式碼**。因 GPL-3.0 copyleft 與本專案的
  open-core 不相容，刻意隔離。見 `docs/research/distribution-and-entitlements.md`。

### CodeIsland
- https://github.com/wxtsky/CodeIsland · MIT
- **僅作功能借鑑（借概念不抄碼）**，未複製任何一行程式碼。

---

## 五、無 copyleft 污染聲明

實際連結的元件全數為寬鬆授權（MIT 或 Apache-2.0），無任何 GPL／LGPL／AGPL 元件
被連結或改作。本專案整體不因第三方相依而承擔 copyleft 義務。唯一出現的 GPL 專案
（boring.notch）僅為設計參考，程式碼零採用。

## 六、音訊資產

本專案**不內嵌任何音檔**。自訂通知音效由使用者自其本機提供，不隨軟體散布。
