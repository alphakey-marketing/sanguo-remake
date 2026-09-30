# Spec 04 — 怪物 / 地圖 / 練功區：應有 UI + 邏輯對照

> 用途：你逐項睇（應有咩 UI / 邏輯），去試，比 feedback。✅=已實作　🟡=部分　❌=未做。
> 現況權威 = spec 04 + PLAN S04 + code。對應攻略 sy2_12_2（怪物大全）、sy3_8（戰役）、sy3_10_1~7（特殊場景）。
> sim：`sim.gd`、`sim_combat.gd`、`sim_battle.gd`、`sim_scene.gd`；data：`monsters.json`、`battles.json`、`scenes.json`、`maps.json`、`maps/*.txt`。
> 自動測試：`run_monsters.gd`(1464)、`run_battle.gd`(297)、`run_scene.gd`(107) ✅。

## ⏸️ 進度暫停點（2026-09-29）

- **移動速度 / 奔跑力 / 桃花渡入口** 三項 feedback 已記（本 session feedback 段），**doc_only 未改 code**（用家指示，暫停先記）。
- **桃花渡/七彩入口**：查到底 七彩門(44,34)=blocked 格被水包圍 + 受 calendar/等級 gate 影響 → 待真正重現確認主因。
- **掉落拾取** = UAT-010/011（用家手測無問題→疑誤判，待核實）。
- `gen_battles.py`/`gen_scenes.py` `--check` 未接入 `run_tests.sh` → 待補。

## ✅ 2026-09-29 更新（用家 2026-09-26 已確認項，待手測）
- **#1 移動速度慢一半**：`world.json walkStepRate=0.5`；`sim.gd _walk_scale` 全體（玩家/NPC/同伴/怪物）步數 ×0.5，小數累積 `mvAcc`。騎乘倍數照乘。舊測試（走路/騎馬/路徑）已按新速度調整。設 1 = 還原。
- **#2 跑奔力加大**：`mounts.json runSpeed 0.005 → 0.01`（跑奔力 100：×2.0 → ×2.5；相對步行約 2.5 倍）。數值可調。
- **#3 桃花渡/七彩入口**：靜態查證 **七彩門 (44,34) 係 `b` = 橋（walk=true，非 blocked）**，同起點連通、NPC 3 格內有 31 個可行格 → 「blocked」推測不成立，**未能重現**。仍受日曆（初一~三/十五~十七）+ 等級（桃花 75+/七彩 70+）gate，唔達標 dialog 冇「進入」掣。需用家提供重現步驟（日期/等級/位置）。
- `gen_battles.py`/`gen_scenes.py` `--check` 已接入 `tools/run_tests.sh`。
- 掉落拾取 UAT-010/011：ui_smoke 已 PASS（見 CLAUDE.md §14），維持用家手測無問題。

---

## ⚠️ 本 session 用家 feedback（2026-09-26，記低待一次過改，暫時未改 code）

> 三件一次過改放入同一批。下面查咗 code 現況 + 已確認嘅位置。

| # | 事項 | 現況 code | 建議改法 | 狀態 |
|---|---|---|---|---|
| 1 | **一般移動速度死一半** | 玩家/NPC/同伴/怪物而家齊齊喺 sim.tick 郁 **1 格**（`sim.gd` `mv=1`；玩家未騎馬 `_ride_steps` 返 1），sim 10Hz → 10 格/秒。無集體「行速」掣撳。 | 全體（玩家/NPC/同伴/怪物，城內城外都計）改為每 2 tick 郁 1 格（或加 config `walkStepEvery`）＝約 5 格/秒。【用家已確認：全體都慢一半，唔淨係玩家】 | 🔲 待改 |
| 2 | **跑奔力影響騎乘速度加大** | 而家 `ride_mult = rideSpeed(1.5) + run×runSpeed(0.005)`（`rules/mount.gd`、`mounts.json`），跑奔力 run cap 100 → 極限都係 ~2.0 倍，同 1.5 差唔遠。騎乘經 `steps_at(mult)` 計步。 | 加大 run 影響（例如改 runSpeed 系數 / 曲線），令高跑奔力騎乘明顯更快。配合 #1 一齊平衡「步行 vs 騎乘」對比。【用家已確認：選加大】 | 🔲 待改 |
| 3 | **桃花渡/七彩奪寶陣入口 click NPC 冇傳送（疑似真 bug）** | sim 入口邏輯（`cmd_scene_enter` → gate 檢查 → `_scene_goto_layer`）結構上健全（run_scene 107 測試 PASS，yield day+level 啱就入到）。**但發現實位置問題**：`maps/gangkou.txt` 入面 **七彩門 (44,34) 格係 `b`（blocked）+ 周圍係水 `~`**，NPC 企喺唔通行格；桃花渡門 (40,30) 位係可行格。 | 重現確認 + 將入口 NPC「考慮去可行格」。另注意：入口仲受「每月 1/2/3/15/16/17 號先開」calendar gate + 等級 gate（桃花 75+/七彩 70+）封鎖，唔達標個 dialog 只會出「今日唔係開門日」／「武等唔夠」而**冇「進入場景」掣**——手測易誤會做「入唔到」。【用家聲稱：時間+等級啱晒，click 仍冇傳送 → 要真係重現】 | 🔲 待改 |

---

## 0. 數據總覽（靜態查核，2026-09-26）

| 項目 | 應有 | 現況 | 現況 |
|---|---|---|---|
| 樸怪物 `monsters` | 46 怪 + 掉落 | `monsters.json` 全表 136 隻（含基地/術法/夜怪/戰役/場景/試煉/PK） | ✅ |
| 掉落 | npc_drops 導入 p>5% 常見 / 其餘稀有 | 98 隻帶 `drops`、一堆帶 `rareDrops`（`import_drops.py --check` ✅） | ✅ |
| 重生排期 | 普通定時 / boss 每日一次 | `_schedule_respawn`：普通 `respawnTicks`、boss 下一個子時重生 | ✅ |
| 逃跑 | 低 HP <20% 有 15% 機會 ×1.5 移速離開消失 | `sim_combat.gd:33-39` + `sim.gd:213` sprint；boss/PK/任務怪 `flee:false` 唔逃 | ✅ |
| 群攻 | 打 1 隻附近 5 格同類一齊仇恨 | `sim_combat.gd:24-25` `groups` flag + GROUP_RANGE | ✅ |
| 夜怪 | 大地圖夜晚高 1~2 級怪群 | 1006「夜狼」`night:true`，spawn `night:true`（field_1/bowang），`_sync_night_spawns` 補/清 | ✅ |
| 術法怪 | 遠程唔埋身 + 吟唱落點走位 | 1007/1008/1009 `ranged:true` | ✅ |
| 汝南洞 | 10 層傳送 | `runan_f1~f10` zone + map + 分層 spawn | ✅ |
| 地面掉落物 | 300 tick 消失 / 撳地拾取 / 背包滿 | `dropped` 實體 + `cmd_pick`（S04a） | 🟡 有 UAT-010/011 真 bug（見下） |
| 6 場戰役 | 張牛角+褚飛燕/李大目/張白騎/黃龍/十常侍 | `battles.json` 6 場全部 `playable:true` | ✅ |
| 特殊場景首批 | 桃花渡 5 層 + 七彩奪寶陣 7 層 | `scenes.json` 2 場（其餘 5 場留後） | ✅ |
| 記事 tag | 戰役 tab + 場景 tab | `quest_panel` tab 2/3 | ✅ |
| 大地圖標示 | 戰役窗口 + 場景入口 | `map_panel` | ✅ |

---

## 1. 野外練功區 / 怪物分佈

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 野外開局怪 | 郤昌城外低等（漫遊/田鼠/山賊） | zone `field_1`（1~10 帶）5 怪 | ✅ spawns 16 組 |
| 分區分層 | 各練功區啱等級怪 | 剄對等級帶怪物| ✅（spec §2 分區；郤昌/襄陽/新野沿線已開） |
| 夜間怪 | 入夜突然多咗高階怪群 | 1006 夜狼 `night:true`，天黑 spawn、天光消失 | ✅ `_sync_night_spawns` |
| 逃往/群居 | 連鎖仇恨 | 群攻 `groups`；逃跑 sprint 1.5× | ✅ |

> ⚠️ **手測重點**：夜晚（戌時~寅時）去 field_1/bowang，睇夜狼有冇現；天黑時暗怪群數、天光清唔清。打「群居」野怪（如野狗）/試曾打散仔試佢一齊沖嚟。

---

## 2. 汝南洞窟（10 層）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 入口 | 新野城外入去 | runan_road → runan_f1 | ✅ zone 串連 |
| 分層傳送 | 落樓梯過層 | f1→f2→…→f10 | ✅ 10 張 map + portal |
| 分層怪 | 5~20 帶分層配置 | spawn per zone | ✅ 每層獨立 spawn |
| 山洞規則 | 座騎唔入得（要戰騎） | Spec 07；洞內死亡另天譴（Spec 03） | 🟡 禁座騎喺 Spec07/山洞專屬處理，詳見該 Spec |

> ⚠️ **手測**：重重入 10 層，睇每層地圖/怪/層次感；死亡返入口；有座騎時入唔入得。

---

## 3. 怪物 AI / 重生 / 掉落

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 仇恨/追擊/返回 | 怪追你到 leash 返原位 | aggroRange/leash | ✅ |
| 重生 | 普通定時 / boss 每日一次 | `_schedule_respawn` | ✅ |
| 掉落 | 殺怪跌落地物品 + 即袋金 | `dropped` 實體；金直接入袋；戰役/場景怪照直入袋 | 🟡 野外拾取 bug（UAT-010/011） |
| 逃跑 | 低 HP 逃走離開 | HP<fleeHpPct<15% 機會 | ✅ |
| 群攻 | 連鎖仇恨 | groups + GROUP_RANGE | ✅ |

---

## 4. 地面掉落物（S04a）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 跌落地 | 地上物品圖示 | `dropped` 實體（S04a） | ✅ |
| 時效 | 300 tick 消失 | `capTicks` | ✅ |
| 拾取 | 行埋邊互動掣「拾取」 | `cmd_pick` | 🟡 **UAT-010/011：企正互動掣 kind 錯 + 撳冇落袋/唔消失（真 bug）** |
| 背包滿 | 負重超上限提示，留落地 | weight×件數 > capBagWeight | ✅（負重系統 S05 重磅重用） |
| 戰役/場景掉寶 | 過層即傳走，執唔返 → 照直入袋 | drop 直入袋（battle_id/scene_id） | ✅ |

> ⚠️ **手測重點**：野外殺有掉落怪 → 睇有冇跌落地 → 行埋邊互動掣係咪「拾取」→ 撳有冇落袋 + 實體消失。**呢個係 Rev 重點（UAT-010/011 未修）。**

---

## 5. 術法怪 / Boss 技能（S04b）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 遠程術怪 | 唔埋身近戰，吟唱線索落點紅圈 + 怪身框 | 1007/1008/1009 `ranged:true` | ✅ |
| 走位躲避 | 行開落點可躲 | 吟唱鎖定落點 | ✅ |
| boss 技能 | 輪流放 + 冷卻 | `skills:[{spell,cd}]` + skill_cd | ✅ 13 隻帶 skills（boss19001 + 6 場尾層大頭目 1042/1047/1053/1059/1064 + 場景 boss 1080~1086） |
| boss 每日 | 每日一次重生 | 子時節點重生 | ✅ |

> ⚠️ **手測**：術法怪離你不遠整_uint 盾？唔好埋身，睇落點紅圈；行開躲唔躲到。戰役尾王（例：十常侍尾關）放技能 + 冷卻。

---

## 6. 6 場戰役（S04c）

| 戰役 | 武等上限 | 層數 | 現況 |
|---|---|---|---|
| 張牛角 | ≤20 | 4 層 | ✅ 1015~1018 |
| 褚飛燕 | ≤30 | 4 層 | ✅ 1039~1042 |
| 李大目 | ≤40 | 5 層（第一層 2 頭目併 1） | ✅ 1043~1047 |
| 張白騎 | ≤50 | 6 層 | ✅ 1048~1053 |
| 黃龍 | ≤60 | 6 層 | ✅ 1054~1059 |
| 十常侍 | ≤70 | 5 層（尾關 10 名併 1） | ✅ 1060~1064 |
| 每日窗口 | 每日兩場、時辰窗口重開 | `window:{startKe,endKe}` | ✅ |
| 多層掉寶 | 每層頭目掉寶表齊 | per-floor drops | ✅ |
| 記事「戰役」tab | 今日窗口/武等/進度 | `view_battles()` + quest_panel tab2 | ✅ |
| 大地圖標示 | 邊場開緊 + 進度 | map_panel | ✅ |
| 報名/離場 | 許昌北門義勇士兵對話 | battle_dialog（報名參戰/放棄/進行中） | ✅ |
| 死亡/完場 | 內陣亡唔跌經驗物品、離場清殘 | `_battle_exit` | ✅ |

> ⚠️ **手測重點**：6 場逐場入 → 打多層 → 尾王（有技能）→ 掉寶齊 → 完場離場。記事 tab 睇窗口/進度。大地圖睇開緊邊場。
> 註：spec 原「原型只做張牛角」已解除，`playable:false` 提示全唔再顯示。

---

## 7. 特殊場景首批（S04d）

| 場景 | 等級 | 層數 | 開門窗口 | 現況 |
|---|---|---|---|---|
| 桃花渡 | 75+ | 5 層 | 每月初一~初三、十五~十七（game 日曆） | ✅ 15 怪 |
| 七彩奪寶陣 | 70+ | 7 層 | 同上 | ✅ 7 色孟獲（多頭目） |
| 入口 | 入口 NPC 對話（進入/離開） | quest_npcs `scene:taohuadu`/`scene:qicai` + scene_dialog | ✅ |
| game 日曆開門 | 開門日公告 | `_daily_hook` `scene_open` 事件 + `lastAnnounceDay` 去重 | ✅ |
| 記事「場景」tab | 今日幾號、開門日、入面進度 | `view_scenes()` + quest_panel tab3 | ✅ |
| 大地圖標示 | 開門場景入口 | map_panel（荊州港口） | ✅ |
| 過層/完場/死亡 | 尾層自動離場、死亡唔跌 | `_scene_on_boss_kill`/`_scene_exit` | ✅ |

> ⚠️ **手測重點**：開門日入桃花渡 → 過 5 層；入七彩 → 打 7 色孟獲（回血機制）；入口對話進入/離開；死亡捔唔跌物品；關門日入唔到。
> 註：其餘 5 個特殊場景（通天關/黑山寨/安定戰場/雪山/異族禁地）留後續批次，未做。

---

## 8. 地圖 / 傳送 / 大地圖標示

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 練功區大地圖 | 城野外進出 | zone 串連 + 座標 | ✅ |
| 汝南洞地圖 | 10 層傳送 | runan_f1~10 | ✅ |
| 戰役地圖 | 每層 16×16 | `maps/<bid>_f<n>.txt`，26 張 + 張牛角 | ✅ |
| 特殊場景地圖 | 桃花渡5+七彩7 | `maps/<scene>_f<n>.txt` | ✅ |

> ⚠️ **手測**：大地圖逐個練功區/洞穴睇；入去傳送走埋順唔順；任務/場景 marker 有冇標啱位。

---

## 9. 數據導入器

| 導入器 | 用途 | 現況 |
|---|---|---|
| `import_drops.py` | npc_drops → monsters drops/rareDrops | ✅ `--check` 已入 run_tests.sh |
| `gen_battles.py` | 6 場戰役 data | ✅ 有 `--check`，但**未入 run_tests.sh** |
| `gen_scenes.py` | 特殊場景 data | ✅ 有 `--check`，但**未入 run_tests.sh** |

> 🟡 **注**：`gen_battles/gen_scenes --check` 有但未接落 `run_tests.sh`（只有 drops/recipes/generals/titles 有）。可靠 GDScript 測試 `run_battle/run_scene` 兜底核對 data 完整性，但 CLI `--check` 建議補入腳本防 drift。

---

## 你嘅 feedback 重點（Spec 04）

### 🔴 本批一次過改（用家確認咗）
1. **移動速度全體死一半**（玩家/NPC/同伴/怪物，城內+城外）
2. **跑奔力影響騎乘速度加大**（同步行速度一齊平衡）
3. **桃花渡/七彩入口 click NPC 冇傳送**（去重現 + 修埋七彩入口 NPC 企喺唔通行格）

### 其次手測
4. **地面掉落物拾取**（重點）：殺怪跌落地 → 行埋邊互動掣係咪「拾取」→ 撳有冇落袋 + 實體消失（UAT-010/011 未修，最緊要試）
5. 野外夜晚怪群（夜狼）有冇定時出/清
6. 汝南洞 10 層傳送順唔順、分層怪啱唔啱等級
7. 術法怪吟唱紅圈走位躲唔躲到；穿戰役尾王技能流/冷卻
8. 6 場戰役逐場入層打死→掉寶→完場離場；記事「戰役」tab + 大地圖標示
9. 特殊場景開門日/入場離場/打多層（桃花渡 / 七彩孟獲）/記事「場景」tab
10. 練功「殺同級怪 ≈ 5~8 隻升一級」手感（exp 基準驗證）

## 已知自動測試問題（相關）

- **UAT-010 / UAT-011**（地面掉落拾取）：自動測試 `ui_smoke` 127→132 檔中有 2 fail（地面掉落實體交互掣 kind + 拾取冇落袋/冇消失）→ 🔴 真 bug，攔住唔係 stale，`cmd_pick`/context 要查。
- **UAT-006**（建角 stale test）：唔影響 Spec04，但在 `ui_smoke` 一齊 fail，跑全測試唔會全綠。
- `gen_battles.py` / `gen_scenes.py` 有 `--check` 但未接 `run_tests.sh`（🟡 建議補）。其餘 drops/recipes/generals/titles `--check` ✅。
- 全 baseline（2026-09-26）：`run_monsters/run_battle/run_scene` ✅ PASS；`ui_smoke` 因 UAT-010/011 + UAT-006 ~ 6 fail。