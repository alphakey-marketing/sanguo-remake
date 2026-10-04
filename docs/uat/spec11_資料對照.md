# Spec 11 — 資料對照 / 導入地圖：應有導入器 + 數據完整性對照

> 用途：你逐項睇（數據來源有冇對應 remake、導入器有冇跑、缺咗啲咩），去核對，比 feedback。✅=已導入　🟡=部分/過渡　❌=未做。
> **Spec 11 唔係玩法 UI，係「導入器/數據對照」UAT** —— 唔使入 Game 撳掣，主要係睇 `client/data/*.json` 有冇、`tools/*.py --check` 過唔過、同原版 `D:\Download\sanguo\extracted\text\*` 對唔對到。
> 現況權威 = spec 11 + PLAN §1（第 11 行）+ PLAN §4 延後掛鈎表。**`docs/plan/S11.md` 唔存在**（spec 11 未拆細步檔，PLAN §1 列「進行中」）。
> 產出格式對照 `spec01_角色成長.md`。

## ⏸️ 進度暫停點（2026-09-29）

- **已導入 ✅**：items/monsters/generals/recipes/titles/jewels/general_skills 全部 `--check` 過。
- **待改**：
  - `material_ids.json` → 實質已做（items `materials` 已 `{id,count,name}`），剔走 spec §11
  - 商城 price 衝突（UAT-015）
  - recruitinfo 說明頁（資料齊冇 UI）❌
  - warbtl 對照（跟 Spec 10）❌
- **待用家**：箭矢分種威力（`ammo.gd` 淨泛用 cat49）、渾天儀來源（有資料冇商店賣）。

## 0. 快速狀態總表

| 導入目標 | 來源檔 | 產出檔 | 導入器 | 狀態 |
|---|---|---|---|---|
| items 物品 | items.json（原版 6068→現 6114） | `client/data/items.json` | 已導入 | ✅ |
| monsters 怪物+掉落 | npc_drops.csv | `client/data/monsters.json` | `tools/import_drops.py` | ✅（46+ 怪） |
| generals 武將 | general_npc.csv | `client/data/generals.json` | `tools/gen_generals.py` | ✅ |
| recipes 配方 | items.json `materials` | `client/data/recipes.json` | `tools/import_recipes.py` | ✅（2318 配方） |
| titles 頭銜 | 攻略 sy2_8_4 | `client/data/titles.json` | `tools/gen_titles.py` | ✅（60 階） |
| jewels 寶石 | jewel.csv | `client/data/jewels.json` | `tools/gen_jewels.py` | ✅ |
| general_skills 武將特技 | general_skills.csv | `client/data/general_skills.json` | 已導入 | ✅ |
| **material_ids（開項）** | items.json `materials`（名稱字符串） | **─（無獨立檔）** | 攞物品導入器已內建 join | 🟡（見 §B） |
| **箭矢種類定義** | items.json cat 49 | `rules/ammo.gd` | S11c 已實作 | ✅（份見 §B2） |
| **商城道具單機化** | items.json cat 250 + sy2_14/15 | `data/mall.json` + `mall_panel.gd` | S11a 已實作（精選） | ✅（份見 §B3） |
| **recruitinfo 說明頁** | recruitinfo.txt | `help_panel.gd` | S11d 已實作（靜態5頁） | ✅（首次彈窗未做） |
| **warbtl 對照** | warbtl.txt | —（PLAN §1 欠缺） | — | ❌（跟 Spec 10） |

> ⚠️ 原版來源檔（`npc_drops.csv`/`general_npc.csv`/`recruitinfo.txt`/`warbtl.txt`/`material_sources.csv`/`general_skills.csv`/`jewel.csv`）全部喺 `D:\Download\sanguo\extracted\text\` 齊存。本 repo 導入器產出由 `tools/run_tests.sh` 每項 `--check` 核對（drops/recipes/generals/titles），**全 PASS 先准剔格**。

---

## A. 已導入（✅ 已落地）

### 1. items.json —— 物品（6068→6114 件）
- ✅ `client/data/items.json` 全量；`id/name/cat/cat_label/price/weight/req_lv/effects/materials/template`
- ✅ `materials` 欄已由導入器做咗**名稱→id join**：每項係 `{"id": 25001, "count": 5, "name": "石頭"}`（唔係 specs 死嘅純名稱字符串）→ 配方導入直接讀 `m["id"]`
- ✅ effects 已解析部分：武器強度/命中/物防/術防（`GameData`）；heals 14/16
- 🟡 cat 250（消耗/特殊=商城道具類）582 件入齊檔，但**絕大部分未接遊戲內取得途徑**（見 §C3）

### 2. monsters —— 怪物 + 掉落（npc_drops.csv）
- ✅ `tools/import_drops.py`：揀等級帶怪（spec 04 §2 分區表）；rate→p（/100000）；p≥0.05 常用掉落、<0.05 稀有掉落（合併 `dropTables`）
- ✅ hp 有攻略就用、冇就模板生成；對應 items.json 校驗 id 報 missing
- ✅ 已實作怪（田鼠/野狗…）drop id 61501 田鼠碎骨 等喺 items.json 對到
- ✅ `--check` 喺 run_tests 有

### 3. generals —— 武將（general_npc.csv，1261 人）
- ✅ `tools/gen_generals.py`：f101=戰等直接做等級（攻略 sy2_6_2 42 人全中）；f116≈智力用嚟分文官小類
- ✅ 9 技能 id:lv → `general_skills.json` 對照；同名多版（曹操 26/1396/1462）Tier1 用第一個、其餘 tier=-1 唔入池
- ✅ 類型/6 小類【自訂】規則喺檔頂註解；`--check` 有

### 4. recipes —— 配方（items.json materials）
- ✅ `tools/import_recipes.py`：craft_kind 9/10/11/12/13 → smithing/mending/cooking/alchemy/carpentry；craft_lv 做所需技能等級
- ✅ 2318 配方；craft_kind 0 但有 materials 嘅 149 件（原版冇指定技能）**唔導入**（by design）
- ✅ `--check` 對 items.json 一致性

### 5. titles —— 頭銜（攻略 sy2_8_4）
- ✅ `tools/gen_titles.py`；60 階 + `soldiers` 帶兵量；`--check` 對攻略表

### 6. jewels + general_skills
- ✅ `jewels.json`（`tools/gen_jewels.py`）：204 實錘 + 攻略 40 屬性石 + 輔助/特殊石；對 cat 262（25075 紅寶石…）join
- ✅ `general_skills.json`：skill_id 對照 + 攻略 70 特技描述 → 規則化效果表
- ✅ 434/物品 24525…（材料 25xxx/26xxx）分類齊，工作採集/商店/掉落來源反查用 `material_sources.csv` + `item_droppers.csv`（來源檔齊存）

---

## B. 開項現況逐個核對（PLAN §1「欠缺」欄 + spec 11 §11 open）

### B1. `material_ids.json`（spec open：`[ ] materials 名稱→id 對照表生成`）
- **現況：🟡（實質已完成於其他形式）** —— 冇獨立 `client/data/material_ids.json` 檔案，但 **items.json 嘅 `materials` 欄已經係 `{id,count,name}` 對象**（導入時已做名→id join）。
- 所以「生成 material_ids.json」呢個 open item **已變多餘**：配方導入（import_recipes.py）直接讀 `m["id"]`，唔再需要獨立對照表。
- **你嘅 feedback：** 呢格應否 **標為已解決**（刪走 spec §11 呢行 / 改註「已內建於 items.materials」）定係用家想保留獨立 `material_ids.json` 做參考落差查表？現況 coding 層面唔阻任何嘢。

### B2. 箭矢種類定義（S11c 已實作）
- **現況：✅ S11c 已實作** —— `rules/ammo.gd` 加咗 `ARROWS` 等級表：38 支真箭（名箭 12101~12120 + 等箭 12201~12220）各有 `lv/power(武器強度加成)/atk_pct(傷害加成%)`；兩系由低到高等。56402/62150（火紅布料/雪精靈魄）唔算箭，唔入表。
- 弩攻擊出手時（`sim_ai.gd`）攞身上**最高等箭**（`RulesAmmo.best_arrow`）做武器強度加成 + 箭特效% → 入 `calc_damage`；每發仍然扣 1 支箭（`consume_arrow` 已改爲跨堆逐支扣）。
- 測試：`tests/run_ammo.gd`（52 項）已接入 `run_tests.sh` —— 覆蓋箭表 vs items.json 全 cat 49、best_arrow、attack_bonus、consume。
- **仲欠：** 箭喺邊度買/製（商店/木匠）未加貨單；`atk_pct` 特效只畀傷害%，未做「穿心/奔雷」等特殊機制（要 S10+ 先會）。

### B3. 商城道具單機化（S11a 已實作 + 精選批次）
- **現況：✅ 已實作（精選批次）** —— 新 `client/data/mall.json` 定義「貨金商城」精選貨單（19 件，有金價）+ `sim_econ.gd` 加 `cmd_mall_buy`/`mall_view`（以金兩買、受魅力/交易折扣）；新 `ui/panels/mall_panel.gd` + more_panel「貨金商城（系統→店鋪）」入口（portal_ui）。
- **商品齊 5 種 職業丹 + 行動丸/歷練神丹/技能神丹/戰騎神丹/升官令牌 + 6 件既有特殊道具 + 三件死亡道具（65016/65029/65030）**；價位全部【自訂】（原點數→金，`mall.json.prices`）。
- **各道具功能（S11b）已接 `cmd_use_item`：** 行動丸→回滿行動力；歷練神丹→歷練+10（封頂100）；技能神丹→全部已學專長 exp+50；戰騎神丹→出戰戰騎 exp+200；升官令牌→頭銜+1；**5 種 職業丹**（開鎖/竊聽/潛行/超渡/透視）→ `cmd_use_class_pill`（sim_skill，要對應職業、唔使已學，食丹即刻施展該職業特技）。
- **藥膳師價確認：** 幸運符 65016=600 / 護身符 65029=800 / 還魂丹 65030=1500（items.json price；**PLAN §4 記「500/800/1500」係舊——實際 data 600/800/1500，未對齊**）。
- 冴：**渾天儀 26029 仍冇商店賣**（等 S06e 左慈渾天儀任務/商城定案，見 PLAN §4）；cat 250 其餘 5xx 件（轉昇冊/免戰金牌/無效道具盒/附身丹…）**未接效果/未入商城**（記錄未做）。
- 測試：`tests/run_mall.gd`（15 項）已接入 `run_tests.sh`：mall_view 貨單、買扣金、行動丸/歷練/技能/升官/職業丹功能。
- **你嘅 feedback：** (1) 藥膳師三件價 600/800/1500 vs PLAN 500/800/1500 邊個啱？(2) 精選批次收唔收？(3) 其餘「荒蕪道具」（5xx 件）想點處理（淨係扔/賣 + 記錄，定要逐件俾效果）？

### B4. recruitinfo 說明頁（S11d 已實作）
- **現況：✅ 已實作說明頁** —— 新 `ui/panels/help_panel.gd`（5 個分頁：介面/戰鬥/賺錢/組隊/飲食）+ more_panel「說明（新手教程）」入口；內容係原版 guide 新手教學精簡改寫做單機觸屏適用。
- **你條「全部單機適用功能第一次都彈出簡介」** → 現時係**靜態說明頁**（可手動開），**未做「首次使用自動彈窗」**（要逐個面板 hook + ch.helpSeen 記錄，量較大）→ 記錄爲延後。
- **你嘅 feedback：** 靜態 5 頁說明夠唔夠？定係要真·首次彈窗教程（更大工程，建議專 UI Step）？

### B5. warbtl 對照（spec 11 §9 → Spec 10；PLAN §1 列欠缺）
- **現況：❌** —— `warbtl.txt`（cs_WarBtl.wcl 解碼，國戰戰役場景/兵力配置）來源檔齊存，但**未做 spec 對照表**、未數據化。
- 掛鈎：國戰 = **Spec 10**，而 Spec 10 成個係 ❌（**D-3 戰局形式仍未定案**【待決】）。
- 已完成嘅 6 場歷史戰役（張牛角…十常侍，spec 06 §7）屬單機演義戰役，唔涉及國戰 warbtl。
- **你嘅 feedback：** 呢項應唔應該跟 Spec 10 一齊（國戰方向定咗先做 warbtl 數據化），而唔係而家獨自做？定要先整「對照索引」留待數據化？

### B6. 怪物逃跑表現（spec 11 §11 open：`[ ] 逃跑表現（sprite 冇）`）
- **現況：🟡** —— 逃跑**機制**已實作（spec 04 怪物逃跑 sim），淨係**冇 sprite 動畫表現**（placeholder 色塊，素材規則：成品前全換走）。
- **你嘅 feedback：** 呢項係咪直接歸入「素材全面換走」批次，而家唔使特別處理？

---

## C. 橫向完整性核對（spec 11 §10 攻略 113 頁 → spec 索引）

- ✅ 攻略已合併成 27 檔 `docs/guide/`（`README.md` 每檔 → 對應 spec；`guide_links.tsv` 133 頁）
- ✅ spec 11 §10 對照表：sy1_1/1_2→01、sy2_1/2_2→02/05、sy2_3→04、sy2_4/5→07、sy2_6→09、sy2_7→06/09、sy2_8→08、sy2_9→02/03/10、sy2_10→02、sy2_11/12→04、sy2_13→01、sy2_14/15→商城、sy3_*→06、sy4→商城 —— 全部頁已歸 spec
- 🟡 全程用嚟補完嘅攻略：sy2_14（大福神）已合併 `sy2_14_fortune.txt`、sy2_15（虛寶）`sy2_15_virtual.txt`（guide README 標「─」冇對 spec）、sy3_2（一般任務）、sy3_7（特技絕招，缺頁）→ **呢啲就係供應商城道具（B3）/說明（B4）嘅原料**

---

## 你嘅 feedback 重點（Spec 11 / 數據完整性為主）
1. **`material_ids.json`（B1）**：開項其實已內建於 items.materials（對象有 id）——要唔要保留獨立對照表？定幫 spec §11 剔走呢格？
2. **箭矢種類（B2，S11c 已做）**：38 支箭已有威力/特效表 —— 但**箭喺邊度買/製未加貨單**；特效只做傷害%，特殊機制（穿心/奔雷）要 S10 先會。收唔收？
3. **藥膳師三件價（B3）**：**600/800/1500 vs PLAN「500/800/1500」邊個啱**？**精選商城批次**（19 件，以金兩賣）收唔收？
4. **荒蕪道具（B3）**：cat 250 其餘 5xx 件（轉昇冊/免戰金牌/無效道具盒/附身丹…）而家啲只有扔/賣 —— 想逐件接效果，定記錄延後？
5. **recruitinfo 說明頁（B4，S11d 已做）**：而家係靜態 5 頁說明 —— **「首次使用自動彈窗」** 未做（要 hook 逐個面板 + ch.helpSeen）。收唔收 / 要唔要真·首次彈窗？
6. **warbtl（B5）**：跟 Spec 10（D-3 國戰定案）一齊做定先行對照索引？
7. **晿（其他）**：`_chest_daily` 冇定義（sim.gd:102 有 call）+ 多個舊測試（mount/class/recruit/general/guard/down/ui_smoke）fail —— 係 working tree 半成品狀態，唔關 S11 features；要唔要一齊跟？

## 已接入測試
- `tests/run_ammo.gd`（52 項）+ `tests/run_mall.gd`（15 項）已接入 `tools/run_tests.sh`，全 PASS。
- 修復咗令成個 sim 起唔到嚟嘅 pre-existing compile error：`quest_panel.gd` (`def`→`func`) + `sim_quest.gd`（`merge()` 返 void 誤用 + Variant 推斷）。
7. **怪物逃跑表現（B6）**：歸入素材替換批次就得？

## 已知自動測試（相關）
- `tools/run_tests.sh` 每項導入器 `--check`（drops/recipes/generals/titles）全 PASS 先准剔 —— 本 UAT 純數據核對，冇 interactive handle；變數據後必須重跑全部 `--check`
## UAT 修正記錄（2026-09-29）
- ✅ B1 `material_ids.json`：剔走（items.materials 已內建 id），spec §11 該格標已解決
- ✅ B3 藥膳師價：維持 data 600/800/1500（Spec 05 已定）
- ✅ feedback 7：`_chest_daily` 已定義（sim_skill.gd:552）；舊測試已修，run_tests ALL OK
- 🟡 B5 warbtl：跟 Spec 10，Spec 10 未定就唔做
- 🟡 B6 怪物逃跑 sprite：歸入素材替換批次
- ⏳ 待用家：箭矢入商店貨單、cat 250 其餘 5xx 道具、首次彈窗教程
- ✅ 箭矢入貨單：5 間武器店加低階箭（鐵箭/鋼箭/木箭/十等箭）；襄陽/宛城/汝南再加獸骨箭～八等箭（待用家手測）
- ✅ cat 250 其餘 5xx：確認延後
- ✅ 首次開面板自動彈簡介：`rules/help_intro.gd` + `GamePanel._maybe_intro` + `cmd_help_seen`（`ch.helpSeen` 記低，只彈一次；待用家手測）


## 物品功能補完（2026-10-04，待用家手測）
- ✅ **全物品說明**：`rules/item_desc.gd` 按實際邏輯生成（寶石/特殊道具/座騎飼料/武將寶物/未實裝標示）；測試 `run_itemdesc`。
- ✅ **解狀態藥**（effect 28~33）：`sim_econ._use_cure`；冇狀態唔扣藥；測試 `run_cure`。
- ✅ **限時 buff 丹**【自訂】（`rules/pill.gd`，`ch.pills`）：1 分鐘 = 600 tick。霸王(物攻%)/老君(術攻%)/防護(物防%)/封靈(術防%)/帝王·封魔(防禦點)/回復(安全區回復%)/元氣(HP 上限點)/岩壁(迴避%)/加持四款/經驗丹 type 1·4·22(擊殺經驗×倍，同款取大)。
- ✅ **丸/速度/光/湯/戒**【自訂】：金剛/守護/大力丸 +20%（精煉 +40%）30 分鐘；神速丸 +50% 移速；快跑/急速/神速丹 +25/50/75% 移速；光 (type 59) 夜間照明；湯/水 (type 18) 飲水度；行動之戒 (type 72) AP 上限 +5。
- 🟡 **仍未實裝**：技能/戰騎仙丹限時版 (type 2/3)；水晶 type 56~58（原作用途不明）；聖者/仁者之戒·項鍊 (type 3/6，用家唔記得)。
- ✅ 背包「使用」掣涵蓋新物品 (`RulesPill.usable`)。
