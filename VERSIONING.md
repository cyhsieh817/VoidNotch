# VoidNotch 版本號規則

> 生效：2026-07-09 重基線（從 `0.1.0` 重新計算）  
> 權威：**本檔**（repo 根）；`CHANGELOG.md` / git tag / `VERSION` 必須與此一致。  
> 通用依據：契約者 SemVer 預設（MAJOR.MINOR.PATCH；LGD 為已知例外）。

---

## 1. 格式

```
MAJOR.MINOR.PATCH[-dev]
```

- 正式發佈：`0.6.0`、`1.0.0`（git tag 加 `v` 前綴 → `v0.6.0`）
- 進行中（未打 tag）：`0.6.0-dev`（寫在 `VERSION` 與 CHANGELOG 標題，**不**打 git tag）
- 禁止：日期版號、Y.MM.N、跳號無說明、同一 tag 內容改寫

| 欄位 | 語意（App 產品） |
|:--|:--|
| **MAJOR** | 不相容變更：設定/資料格式無法自動遷移、公開 API 破壞、產品定位大翻轉；或離開 0.x 進入穩定產品 |
| **MINOR** | 向後相容的**使用者可感知能力**（新指標、新 provider、新設定區塊、新打包路徑） |
| **PATCH** | 修 bug、文案、效能微調、重構且**不**新增對外能力 |

---

## 2. 0.x 與 1.0.0 閘門

| 區間 | 意義 |
|:--|:--|
| **0.y.z** | 公開可用但仍屬 pre-stable：功能可增減、known issues 可列、預設 ad-hoc 簽名 |
| **1.0.0** | 首個「穩定產品」發佈，須同時滿足下列閘門 |

**升 1.0.0 必備：**

1. 真機常駐驗收通過（建議 ≥30 分鐘，無明顯漏記體／卡死）
2. `swift test` 與 `swift run vn-selftest` 綠
3. 發佈物：Developer ID 簽 + Notarization（或文件明確標示「僅源碼自建」且不宣稱正式 binary 散佈）
4. `CHANGELOG` 有完整 1.0.0 節；known issues 寫清

未達閘門前，再大的功能也只加 **0.y**，不硬上 1.0。

---

## 3. 何時升哪一欄（決策表）

| 變更類型 | 升 | 例 |
|:--|:--|:--|
| 新系統指標族、新 provider live、新設定大區塊、新建置/安裝路徑 | **MINOR** | Disk/Net 監控、Grok live、`make_app.sh` |
| 崩潰修復、錯誤顯示、clamp、死碼刪除 | **PATCH** | refresh 重入、onChange 警告 |
| 設定 schema 無法遷移、移除已發佈能力且無 fallback | **MAJOR**（0.x 時極少用；優先標 breaking 並仍可走 0.y） | 清空 UserDefaults 鍵且無遷移 |
| 僅內部文件 / research | **不升版** | `docs/research/*` |
| 僅開發中、尚未要 tag | 在下一目標 MINOR 加 **`-dev`** | `0.6.0-dev` |

**0.x 特例：** 產品仍在快速迭代時，**MINOR 可較積極**（每個可敘述的能力里程碑一號）；PATCH 留給 hotfix。不要把「一週所有 commit」塞進同一個 MINOR 又不寫 CHANGELOG。

---

## 4. 單一真相與落地位置

| 產物 | 規則 |
|:--|:--|
| **`VERSION`**（repo 根） | 目前行銷／Info.plist 版本字串；開發中為 `Y.Z.0-dev`，打 tag 當日改為 `Y.Z.0` |
| **git tag** | 僅正式版：`vMAJOR.MINOR.PATCH`（annotated）；對應 commit 必須已含該版 CHANGELOG |
| **`CHANGELOG.md`** | Keep a Changelog；新節插在最上方；`-dev` 可先寫，tag 時去掉 `-dev` 並填日期 |
| **`CFBundleShortVersionString`** | = `VERSION` 去掉可選的敘事後綴處理：`make_app.sh` 優先讀 `VERSION`，再 fallback 最近 tag |
| **`CFBundleVersion`** | 建置序（`git rev-list --count HEAD`），**不是** SemVer |
| **GitHub Release** | 一 tag 一 release；body 摘自 CHANGELOG 該節 |

---

## 5. 發佈流程（砍 tag 前 checklist）

1. `swift test`、`swift run vn-selftest`、`swift build --product VoidNotch`（或 `scripts/make_app.sh`）通過  
2. `CHANGELOG`：`[X.Y.Z-dev]` → `[X.Y.Z] - YYYY-MM-DD`，Pending 移到 Known issues 或下一 `-dev`  
3. 根目錄 `VERSION` 改為 `X.Y.Z`（無 `-dev`）  
4. `git tag -a vX.Y.Z -m "VoidNotch vX.Y.Z — <一句話>"`  
5. push tag +（可選）`gh release create`  
6. 下一輪開發：立刻把 `VERSION` 與 CHANGELOG 頂節改為下一目標 `X.(Y+1).0-dev` 或 `X.Y.(Z+1)-dev`

---

## 6. 2026-07-09 重基線對照

舊 CHANGELOG／口語版號曾交錯（`0.2.0` tag 內容 ≠ 後續文件稱的 0.2，且 `0.3`–`0.5` 多未 tag）。**自本日起以本表為準；舊編號僅作考古。**

| 新版號 | 產品主題 | 對應舊稱呼（約） |
|:--|:--|:--|
| **0.1.0** | 資料層 + Notch 外殼 + CPU/RAM/溫度 | `0.1.0-dev` |
| **0.2.0** | Token／Agent 產品面 + Settings + Xcode app | `0.2.0-dev`（App 功能大段） |
| **0.3.0** | VoidNotchKit、並行抓取、自適應輪詢、Theme | 舊 git tag **`v0.2.0`** 內容 |
| **0.4.0** | 展開防截斷、compact 策略、選單列共存 | 舊文 `0.3.0` |
| **0.5.0** | CLI 打包、i18n、元件庫、AGY 多帳、Grok live | 舊文 `0.4.0-dev` |
| **0.6.0** | 系統 status 擴充 + compact 佈局／指標偏好 + App icon | 舊文 `0.5.0-dev` |

**現況（2026-07-09）：** 正式發佈 **`0.6.0`**（tag `v0.6.0`）。  
**歷史 git tag `v0.2.0`：** 語意對應**新** `0.3.0`，且可能不在目前 `main` 可達歷史上；**勿再當最新版**。正式重 tag 須契約者許可後另案執行（刪舊 tag／補打 `v0.1.0`…）。

---

## 7. 一句話口訣

> **能力進 MINOR、修補進 PATCH、穩定進 1.0；開發中加 `-dev`，只有验收过的才打 `v*` tag。**
