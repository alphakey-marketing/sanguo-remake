# Sanguo Remake — 新 session 接手簡報

私人本地原型：自家代碼重做三國演義 Online 普通玩法（即時制打怪練功），**目標平台 = 手機單機**，NPC 由 LLM(API) 驅動。只本機跑，唔連任何真實伺服器。

## 先讀（按序）
1. `docs/PLAN.md` — **路線圖 v6**：§1 各 spec 現況表、§3 逐份 spec 補完路線（S01~S12）、§4 延後掛鈎表
2. 當前 Step 對應嘅 `docs/spec/NN_*.md` — **完整系統邏輯規格**；改機制前先睇
3. `docs/DESIGN.md` — 整體設計 v2（手機、豫荊、LLM NPC 架構、市場模擬、待決事項 D-3）
4. `docs/普通玩法_系統摘要.md` — 玩法規格（【原】= 官方攻略；【自訂】= 自己設計）
5. 需要時：`docs/PLAN_v5_history.md`（Step 1~19 做法 + 每步「偏離 spec」記錄）、`docs/guide/` 攻略原文 113 頁（連結表 `docs/guide_links.tsv`）、`docs/GODOT_NOTES.md`、`README.md`

## 路線（2026-09-24 定）
- **由 spec 01 順序做到 spec 12**，每份 spec = 一個大 Step（S01~S12），拆細步 a/b/c…
- **每細步 = 邏輯 + UI 一齊交**（rules → sim → UI 面板/掣 → `--uitest`），冇 UI 唔准剔格（純後台項除外）
- 大 Step 開工先「核實」spec vs 代碼，更新 PLAN §1 同清單
- 跨 spec 依賴：先做資料 + 掛鈎 + 測試，效果喺後面 Step 接，記入 PLAN §4
- PLAN 標【待決】= 做到嗰步先問用家，唔好自己估
- **下一步 = PLAN §3 第一個未剔 `[ ]`**（2026-09-25：S02c-巫女完，下一步 S02c-辯士）

## 現況 (2026-09-25，S02c 道士開放完)
- **全部喺 `client/` (Godot 4.7, GDScript)**：`rules/`(純函數)、`sim/`(單機世界模擬，狀態可存檔、種子 RNG)、`ui/`(`touch/` HUD 觸控 + `panels/` 正式面板)、`tests/`
- 詳細現況 = PLAN §1；已做系統 → 檔案索引：

| 系統 | rules | sim | data |
|---|---|---|---|
| 角色/點數/測驗/修練/行動力/飲水/專長/職階（二轉三轉） | `stats.gd` `quiz.gd` `title.gd` `expert.gd` `class.gd` | `sim_char.gd` | `classes.json` `quiz.json` `experts.json` |
| 戰鬥/術法/寶石/絕招/融合 | `combat.gd` `spell.gd` `jewel.gd` | `sim_combat.gd` `sim_skill.gd` `sim_ai.gd` | `monsters.json`(掉落由 `tools/import_drops.py` 生成) |
| 職業特技（義士融合內建；仕女開鎖、道士超渡、**巫女潛行**已開） | `class_skill.gd` + `stealth.gd` | `sim_skill.gd`（`cmd_use_skill`/`cmd_skill_pick`/`cmd_stealth_cross`） | `class_skills.json` |
| 裝備/耐久 | `equip.gd` | `sim_econ.gd` | `equip.json` |
| 善惡 | `karma.gd` | `sim_combat.gd` | — |
| 生產/修理/天地商行/捐獻/市場 | `work.gd` `tiandi.gd` `market.gd` `shop.gd` | `sim_econ.gd` | `work.json` `recipes.json`(生成) `shops.json` `donation.json` |
| 任務/歷史/委託/收集冊 | `quest.gd` `commission.gd` | `sim_quest.gd` `sim_comm.gd` | `quests.json` `quest_npcs.json` `commissions.json` |
| 頭銜/官宅/官令 | `title.gd` | `sim_office.gd` | `titles.json`(生成) `office.json` |
| 登用/同伴/武將特技 | `recruit.gd` `general.gd` | `sim_recruit.gd` | `generals.json`(生成) `general_skills.json` `quiz_generals.json` |
| 座騎/繁衍/馬戰 | `mount.gd` `mount_battle.gd` | `sim_mount.gd` | `mounts.json` `mount_weapons.json` |
| 戰騎（**純規則，sim/UI 未接**） | `war_beast.gd` | — | `war_beasts.json` |
| 戰役（張牛角 playable，其餘 5 場資料殼） | `battle.gd` | `sim_battle.gd`(夾喺 sim_econ/sim_combat 之間) | `battles.json` |
| 地圖/驛站/天災/時鐘 | `path.gd` `station.gd` `disaster.gd` `clock.gd` | `sim_core.gd` `sim_station.gd` | `maps.json` + `maps/*.txt` `world.json` `facilities.json` |
| 居民/記憶/brain | `npc_memory.gd` | `bot_sys.gd` `npc_brain.gd` | — |

- 已知 UI 欠債：座騎面板未有繁衍/馬戰/改名掣（`main.gd` 已有派送）；戰騎冇面板；建角面板仍係 debug 版；戰役只有報名對話
- 地圖：B1~B3 做完（spec 12）；改地圖直接改 `data/maps/*.txt`（`tools/map_draft.py` 只係起稿，再跑會覆蓋）；新 txt 要喺 export include_filter（`data/maps/*.txt`）；其他數據寫 `map` + 地圖內座標，GameData 載入轉全域
- 生成檔唔好手改：`monsters.json` 掉落、`recipes.json`、`generals.json`、`titles.json`（改導入器再跑）
- `legacy/server/`：舊 Node+ws server，只作參考（`tools/export_vectors.ts` 由佢導出向量）

## 測試
- `sh tools/run_tests.sh` = 全部：rules 對拍向量 + 各 `tests/run_*.gd` + hud 版面 + `--autotest` 端到端 + `--uitest` 觸控煙霧 + 導入器 `--check`（drops/recipes/generals/titles），**全 PASS 先准剔格**
- 新系統加 `tests/run_<系統>.gd` 並接入 `run_tests.sh`；sim 改動要確認決定性 + 存檔 roundtrip（含舊存檔兼容）

## 已定決策
- 手機單機（橫屏觸控，Android 先）；範圍 豫州+荊州，新手城 許昌/襄陽/新野；豫荊以外地點遇到先問用家
- 義士先行（其他 5 職 = S02c）；戰鬥即時制，sim 權威，client 只發意圖
- NPC = LLM(API)：**LLM 只揀動作/生成話語，唔直接改數值**；分 Tier；一定要有規則/模板後備（離線可玩）；測試用 mock，唔碰網絡
- 公式全部【自訂】，放 `client/rules/` + 測試，數值放 `client/data/`；rules 保持純函數 + 數據驅動
- **架構 A2**：sim/規則/存檔全部喺 Godot(GDScript)；UI 只發 `sim.cmd_*` 意圖、聽 `event_emitted`、讀 `view_ents()`/`player_ch()`；sim 狀態 = 純資料 Dictionary，`save_string()`/`Sim.load_string()`；所有隨機經 `SimRng`（種子），測試要可重現
- **LLM**：OpenRouter（OpenAI 相容），**玩家自填 key**（本機存，唔入存檔/log），模型名可設定；B2 行為（規則主導+搭話即時+每日反思）；R1 記憶（結構化事實+摘要）
- UI 風格：三國群英傳M；面板 = `ui/panels/` 正式 Control，玩家自己揀自己確認
- 待決：D-3 戰局形式（DESIGN §8，S10 前要定）

## 工具 / 路徑
- Godot: `D:\Download\Sengoku\godot\Godot_v4.7.2-stable_win64_console.exe`；Godot 踩坑筆記 `docs/GODOT_NOTES.md`
- 8080 port 被別個程式佔用，唔好殺（舊 server 用 8765，已退役）
- 逆向研究資料（原版表/素材/協議筆記）: `D:\Download\sanguo\`（`docs/INDEX.md`、`extracted/`）；原版客戶端 `D:\Download\Sanguo_Client\`
- 原版無公式（server 權威）、無怪物/人物 sprite（未解）
- Bash heredoc 遇中文+引號會壞，寫檔用 Write 工具
- Windows Python 睇唔到 `/tmp`，暫存用 scratchpad

## 素材規則（重要）
`client/assets_placeholder/` = 佔位素材（placeholder，**唔係原版素材**），唔入 git（已 .gitignore）。引用一律經 `res://assets_placeholder/`。成品前全部換走。角色暫用頭像、怪物色塊。APK / web 匯出包含佢冇問題。

## 工作方式
- 每細步：spec → `rules/*.gd` + 測試 → sim 指令 + 場景測試 → UI → `--uitest` → `run_tests.sh` 全 PASS → 剔 PLAN 格
- 偏離 spec 一律寫入 PLAN 該細步「偏離」行；spec 同代碼唔同 → 以 spec 為準（【自訂】且已有測試就改 spec）
- 做完大 Step：更新 PLAN §1、本檔「現況」、spec 頂「現狀」
- 回覆用廣東話
