# UAT 檢驗記錄（User Acceptance Testing）

> 方式：**人手測試**（用家） + **Code/Spec 靜態查核**（agent）。範圍 = **全部功能**（UI 面板 + 核心玩法 + 12 Spec）。
> 每功能一檔：`docs/uat/<功能>.md`。本文 = 總索引 + 全體問題清單（發現到就記低，**一批過改**）。
> 驗證基準：`sh tools/run_tests.sh` 全 PASS（2026-09-26 基線：**SOME FAILED**，見下方）。

---

## 基線測試狀態（2026-09-26 run_tests.sh）

| Leg | PASS / FAIL | 備註 |
|---|---|---|
| rules/quest/hist/group/ult/expert/b3/mount/war_beast/spell/stealth/jewel_ult/sim/residents/rumor/llm/marry/char/class/world/monsters/maps/equip/craft/master/tiandi/recruit/general/title/militia/civic/camp/battle/scene/pk/karma | ✅ ALL OK | |
| hud | ✅ 5056 fail 0 | |
| **guard** | ❌ 61 scenarios, **fail 14** | 城捕快 spawn + 巡邏時辰 13 個 fail |
| **down/onsite-revive** | ❌ 36, **fail 6** | 復活丹唔喺雜貨店 5 fail + 逾時兜底 HP 冇回一半 1 fail |
| **ui_smoke** | ❌ 129, **fail 6** | 建角 3 + 裝備卸下 1 + 掉落拾取 2 |
| drops/recipes/generals/titles 導入器 `--check` | ✅ OK | |

---

## 全體問題清單（UAT 發現，一批過改）

> 每項有 id，改嗰陣引用。分優先級：🔴 阻玩（做唔到/玩唔到） 🟠 功能錯（流程唔對） 🟡 體驗（顯示/提示/手感） 🟢 建議。

| ID | 優先 | 功能 | 描述 | 狀態 |
|---|---|---|---|---|
| UAT-001 | 🔴 | 城衛（guard） | 城捕快完全冇 spawn（實得 10 隻，預期 20+；每張 city 地圖應 2 隻；changsha/luoyang/xiapi lingling xiaopei 應 2 隻） | 待改 |
| UAT-002 | 🔴 | 城衛（guard） | 巡邏時辰判斷錯：辰 3~8 應係巡邏時辰但判定唔係；子時/亥時例外對 | 待改 |
| UAT-003 | 🟠 | 城衛（guard） | 巡邏時辰時捕快冇設目的地離開企定位（唔巡邏） | 待改 |
| UAT-004 | 🟠 | 死亡/復活（down） | 復活丹 (65338) 5 間雜貨店 (grocery/grocery_xy/grocery_rn/grocery_wc/grocery_xyc) 都冇賣 | 待改 |
| UAT-005 | 🟠 | 死亡/復活（down） | 倒地逾時 300 秒兜底：HP 冇回一半 | 待改 |
| UAT-006 | 🟡 | 建角（create） | **stale test**：面板已由 7 tab 改成 2 頁，`ui_smoke` 未更新。人手測試正常 | 待改（test） |
| UAT-007 | 🟡 | 建角（create） | ~~生日月撳完冇變~~ **stale test**（同上，面板已改 2 頁） | 待改（test） |
| UAT-008 | 🟡 | 建角（create） | ~~撳臉譜冇循環~~ **stale test**（同上） | 待改（test） |
| UAT-009 | 🟠 | 角色裝備（char_panel） | 裝備頁撳「卸下」冇卸走頭部裝備（真 bug，panel 只 tab0/1 兩頁，測試亦用舊結構？待核實） | 待改 |
| UAT-010 | 🟠 | 掉落物（地面） | 殺怪跌落地後企正互動掣唔係「拾取」（ctx kind 錯） | 待改 |
| UAT-011 | 🟠 | 掉落物（地面） | 撳「拾取」冇落袋、實體冇消失 | 待改 |
| UAT-012 | 🟠 | 天譴（善惡） | spec 03 §3 寫天譴「傳送返客棧」，但 code `_tianqian_reprisal` 只扣 50% HP 唔傳送、主角唔死唔入倒地原地企 → spec vs code 衝突要定 | 待決 |
| UAT-013 | 🟡 | 城際貿易（生產） | S05a 城際貿易搬運跨城賣**未做**（留後續） | 待決 |
| UAT-014 | 🟡 | 同伴指令（登用） | Spec 09 同伴 6 指令，實作為 4 order + skillMode（主動攻擊/支援/跟隨/原地 + 用絕招開關）→ 記偏離 | 待決 |
| UAT-015 | 🟡 | 商城道具（資料） | 藥膳師價 data 600/800/1500 vs PLAN §4 「500/800/1500」衝突；渾天儀 26029 有資料冇商店賣 | 待决 |
| UAT-016 | 🟡 | 新手城（地圖） | 新手城 homeCity 鎖死 xuchang，揀城 UI 未見（規格應可揀許昌/襄陽/新野？） | 待決 |
| UAT-017 | 🟡 | 國戰（Spec 10） | 完全未做❌；12 個決策點 P1~P12（含 D-3 戰局形式）——見 `spec10_國戰.md` §9 | 待決 |
| UAT-018 | 🟡 | 測試接入 | `gen_battles.py`/`gen_scenes.py` 有 `--check` 但未接入 `run_tests.sh` | 待改（test） |
| UAT-019 | 🟡 | 義勇軍/官宅 | 襄陽冇捐獻處/冇官宅 → 進貢/救災領令唔到；義勇軍階級管理/俸祿設定冇 UI；營地 Lv4/5 職位、軍備製作(兵工房10類)未實裝 | 待決 |
| UAT-020 | 🟡 | 建角（測試） | `ui_smoke` 仲用舊 7 tab，面板已改 2 頁 → stale test 要更新（參 UAT-006~008） | 待改（test） |

---

## 功能索引（docs/uat/）

> 逐個功能開一檔。✅已開檔 ❍未開.

## Spec 級「應有 UI + 邏輯」對照表（逐 spec 手測 + feedback）

> 用家逐份 spec 咁、試、比 feedback。每份三欄：應有 UI / 應有邏輯 / 現況(✅🟡❌) + feedback 重點 + 已知自動測試問題。

| Spec | 檔 | 手測重點 | 主要未做/偏離 |
|---|---|---|---|
| 01 角色成長 | `spec01_角色成長.md` ✅ | 建角2頁/升級+3/歷練/修練/專長 | 迷宮地圖效果；內政/救災專長→S08 |
| 02 戰鬥術法 | `spec02_戰鬥術法.md` ✅ | 六職特技/絕招/組隊exp/術法紅圈 | 術法怪紅圈UI、鎖箱實體、武器3槽切換UI |
| 03 善惡死亡 | `spec03_善惡死亡.md` ✅ | 七階/天譴/倒地/城捕快 | 捕快UAT-001~003、復活丹float、**天譴spec-code衝突** |
| 04 怪物地圖 | `spec04_怪物地圖.md` ✅ | 掉落物/術法怪/6戰役/2場景 | 掉落UAT-010/011、gen_battles --check未接入 |
| 05 生產經濟 | `spec05_生產經濟.md` ✅ | 2318配方/天空商行/大宗師 | **城際貿易未做**、御賜工具/白晝珠過渡 |
| 06 任務 | `spec06_任務.md` ✅ | 各類任務/記事面板 | 四~六招/渾天儀/國戰專長留後 |
| 07 座騎戰騎 | `spec07_座騎戰騎.md` ✅ | 繁衍/馬戰/拍賣/友好技 | 12個友好技留後無效 |
| 08 名聲義勇軍 | `spec08_名聲義勇軍.md` ✅ | 官宅/救煾/義勇軍/民心 | 襄陽冇捐~處、階級UI、營地Lv4/5、軍備製作未裝 |
| 09 登用LLM | `spec09_登用LLM.md` ✅ | 登用/同伴/LLM/結婚 | 同伴指令6→4+1、結婚村NPC圖示 |
| 10 國戰 | `spec10_國戰.md` ✅ | **【待決】12決策點 P1~P12** | 全部❌，D-3未定 |
| 11 資料對照 | `spec11_資料對照.md` ✅ | 數據完整性 | material_ids多餘、箭矢分種、商城price衝突 |
| 12 地圖世界 | `spec12_地圖世界.md` ✅ | 過圖/A*/驛站/天災 | 新手城揀城UI、B4州郡決策 |


---

## 嚴重度總結

- 🔴 阻玩：城衛 spawn + 巡邏（UAT-001~003）
- 🟠 功能：復活丹 float 判定（UAT-004）、逾時兜底 HP（UAT-005）、建角三部（UAT-006~008）、卸下裝備（UAT-009）、掉落拾取（UAT-010/011）
- 🔵 系統性根因：**JSON 整數陣列載入 Godot 變 float**，令 `Array.has(int)` / `in` 判定錯。已喺 `shop_sells` 用 `float(item)` 繞過，但 `guard.is_patrol_time` 等冇繞過。修正方向：統一 float-safe 比較 helper 或 load 時轉 int。
