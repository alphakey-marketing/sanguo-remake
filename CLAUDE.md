# Sanguo Remake — 新 session 接手簡報

私人本地原型：自家代碼重做三國演義 Online 普通玩法（即時制打怪練功），**目標平台 = 手機單機**，NPC 由 LLM(API) 驅動。只本機跑，唔連任何真實伺服器。

## 先讀（按序）
1. `docs/PLAN.md` — **路線圖 v6**：§1 各 spec 現況表、§3 逐份 spec 補完路線（S01~S12）、§4 延後掛鈎表
2. 當前 Step 對應嘅 `docs/spec/NN_*.md` — **完整系統邏輯規格**；改機制前先睇
3. `docs/DESIGN.md` — 整體設計 v2（手機、豫荊、LLM NPC 架構、市場模擬、待決事項 D-3）
4. `docs/普通玩法_系統摘要.md` — 玩法規格（【原】= 官方攻略；【自訂】= 自己設計）
5. 需要時：`docs/archive/PLAN_v5_history.md`（Step 1~19 舊做法 + 每步「偏離 spec」記錄，已歸檔僅備參考）、`docs/guide/` 攻略原文（**已合併成 27 檔**）：索引 `docs/guide/README.md`（每檔含邊啲頁 + 對應 spec），連結全表 `docs/guide_links.tsv`（133 頁，正文缺 20 頁詳見 guide/README）；`docs/普通玩法_系統摘要.md` header 列咗缺邊啲）、`docs/GODOT_NOTES.md`、`docs/UI_TOUCH.md`（手機橫屏 UI 現行設計；舊 `docs/archive/UX.md` 已歸檔）、`README.md`

## 路線（2026-09-24 定）
- **由 spec 01 順序做到 spec 12**，每份 spec = 一個大 Step（S01~S12），拆細步 a/b/c…
- **每細步只做邏輯層**（rules → sim → `tests/run_*.gd`），UI 延後、唔使一齊交；剔格條件只睇邏輯 + 測試過
- 大 Step 開工先「核實」spec vs 代碼，更新 PLAN §1 同清單
- 跨 spec 依賴：先做資料 + 掛鈎 + 測試，效果喺後面 Step 接，記入 PLAN §4
- PLAN 標【待決】= 做到嗰步先問用家，唔好自己估
- **下一步 = PLAN §3 第一個未剔 `[ ]`**（2026-09-26：S09a 居民化、S09b 傳聞、S09c 特技全剔、S09d LLM 層完、S09e 結婚完 → **PLAN §3 全剔 ✅**；插隊做 UI 補完 U01~U15：U01 戰騎面板完、U02 座騎補完（改名/繁衍/馬戰）完、U03 同伴主動特技掣（遁地/挑釁/急救 + 22 職業特技冷卻加成顯示）完 → U04 NPC 拍賣場座騎/馬戰部分拍賣掣完 → U05 官宅面板：頭銜/官令/義舉/進貢/名額競爭完 → U06 官宅面板：內政 + 城池屬性完 → U07 救災完 → U08 義勇軍面板完（定居/遊說/成立/成員/階級/帶兵量）→ U09 營地面板完（設施升級/監督/22 工作/評定會議/倉庫商情訓練）→ **U10 民心/法令面板完**（新 `civic_panel.gd`：根據地城池民心/人口/稅率 3 檔/6 條法令開關；`bag_panel.gd` 加丟物品掣）→ **U11 LLM 設定+對話完**（新 `llm_panel.gd`：頁 0 設定 key/模型+啟用開關、頁 1 對話記錄；`main.gd` 新增真 HTTPRequest 接線 `_on_llm_request()`）→ **U12 結婚面板完**（新 `marriage_panel.gd`：頁 0 喜事求婚/喜餅買開分/預約禮堂/舉行婚禮、頁 1 配偶資料/召喚/叮嚀/離婚；結婚村 NPC 圖示留後）→ **U13 導航/天眼+其餘友好技完**（小地圖顯示導航/天眼/嗅血；接痛楚屏障/加成/聖靈/穩重/遁地地行；脫出/召喚/神行/回城/火焰/飛影/狂力/開光/野性/奇門冇系統掛鈎留後）→ 下一步 = U14 建角面板正式化；之後續 U15，再之後 S10 國戰（開工前 D-3 要定案））

## 現況（2026-09-26：管線權威 = PLAN §1 現況表；逐細步已拆去 `docs/plan/S01~S09.md`）
- **全部喺 `client/` (Godot 4.7, GDScript)**：`rules/`(純函數)、`sim/`(單機世界模擬，狀態可存檔、種子 RNG)、`ui/`(`touch/` HUD 觸控 + `panels/` 正式面板)、`tests/`
- 詳細現況 = PLAN §1；已做系統 → 檔案索引：

| 系統 | rules | sim | data |
|---|---|---|---|
| 角色/點數/測驗/修練/行動力/飲水/專長/職階（二轉三轉） | `stats.gd` `quiz.gd` `title.gd` `expert.gd` `class.gd` | `sim_char.gd` | `classes.json` `quiz.json` `experts.json` |
| 戰鬥/術法/寶石/絕招/融合 | `combat.gd` `spell.gd` `jewel.gd` | `sim_combat.gd` `sim_skill.gd` `sim_ai.gd` | `monsters.json`(掉落由 `tools/import_drops.py` 生成) |
| 職業特技（義士融合內建；仕女開鎖、道士超渡、**巫女潛行、辯士竊聽、美女透視**已開） | `class_skill.gd` + `stealth.gd` + `qieting.gd` + `ammo.gd` + `toushi.gd` | `sim_skill.gd`（`cmd_use_skill`/`cmd_skill_pick`/`cmd_stealth_cross`/`_try_qieting`/`_try_toushi`/`_spell_heal`）+ `sim_ai.gd`（弩箭消耗） | `class_skills.json` `rumors.json` `spells.json`（+恢復術一~七級） |
| 裝備/耐久 | `equip.gd` | `sim_econ.gd` | `equip.json` |
| 善惡/可攻擊 NPC + 死亡道具 | `karma.gd`（+`karma_after_kill_npc`/`counter_kill`/`tianqian_*`/`city_banned`/`office_blocked`）+ `combat.gd`（`death_drop_table`/`roll_death_drop_items`/`death_exp_loss_protected` + 三件 `LUCKY_CHARM`/`PROTECTION_CHARM`/`REVIVE_PILL`） | `sim_combat.gd`（`_kill_bot`/`_tianqian_reprisal`/`_kill_player` 六步）+ `bot_sys.gd`（`_pk_flee`/`_crime_find_player`/`W_SEE_DIE`）+ `sim.gd` `_city_guard_check` + `sim_econ.gd` `cmd_rest`(拒住) + `sim_office.gd` `order_block`(罪犯拒官令) + `sim_core.gd` `_half_heal` | `world.json`（`bots.criminalPct/fleeChance/crimeAggro/guardWarnTicks`） `items.json`(65016/65029/65030) `shops.json`(herbalist) |
| 生產/修理/天地商行/捐獻/市場/大宗師合成術 | `work.gd` `tiandi.gd` `market.gd` `shop.gd` `master.gd` | `sim_econ.gd` | `work.json` `recipes.json`(生成) `shops.json` `donation.json` `master_recipes.json` |
| 任務/歷史/委託/收集冊 | `quest.gd` `commission.gd` | `sim_quest.gd` `sim_comm.gd` | `quests.json` `quest_npcs.json` `commissions.json` |
| 頭銜/官宅/官令/義舉/進貢/城池屬性/救災/名額競爭/義勇軍成立/營地+義勇軍工作+評定會議/民心+法令 | `title.gd` `merit.gd` `city.gd` `disaster.gd` `militia.gd` `camp.gd` `militia_work.gd` `civic.gd` | `sim_office.gd` | `titles.json`(生成,含 `soldiers`) `office.json`(`merit`/`tribute`/`domestic`/`relief`/`competition`/`militia`) `world.json`(`cities[].attrs`/`cityAttrs`/`cityMorale`/`cityLaw`/`disasters[].reliefItem`) `camp.json`(10 設施/22 工作/功績表) |
| 登用/同伴/武將特技 | `recruit.gd` `general.gd` | `sim_recruit.gd` | `generals.json`(生成) `general_skills.json` `quiz_generals.json` |
| 結婚（**S09e + U12 完**） | `marry.gd`（+`quest.gd` `pre.gender`） | `sim_marry.gd`（`cmd_marry_propose`/`buy_cake`/`open_cake`/`share_cake`/`book`/`hold`/`summon`/`message`/`divorce` + `marry_view`）+ UI `marriage_panel.gd` | `marry.json`（+`quests.json` marry 2 條 + `quest_npcs.json` 結婚村 4 NPC） |
| 座騎/繁衍/馬戰 | `mount.gd` `mount_battle.gd` | `sim_mount.gd` | `mounts.json` `mount_weapons.json` |
| 戰騎（**S07b sim 整合 + S07c 友好特技效果 + S07d 拍賣場/馴馬完；UI 面板未做**） | `war_beast.gd` | `sim_war_beast.gd` | `war_beasts.json` |
| 戰役（**6 場全部 playable**：張牛角 + 褚飛燕/李大目/張白騎/黃龍/十常侍 26 層，monster+多層 map+掉寶齊；記事「戰役」頁 + 大地圖標示） | `battle.gd` | `sim_battle.gd`(夾喺 sim_econ/sim_combat 之間；`view_battles()` read-model) | `battles.json` + `tools/gen_battles.py` |
| 特殊場景（**首批 2 個**：桃花渡 5 層 + 七彩奪寶陣 7 層，game 日曆開門 + 入口對話 + 記事「場景」頁 + 大地圖標示；其餘 5 個留後續批次） | `scene.gd` | `sim_scene.gd`(企喺 sim_battle 之上、sim_combat 之下；`cmd_scene_enter/leave`/`view_scenes`/`scene_view`) | `scenes.json` + `tools/gen_scenes.py` |
| 地圖/驛站/天災/時鐘 | `path.gd` `station.gd` `disaster.gd` `clock.gd` | `sim_core.gd` `sim_station.gd` | `maps.json` + `maps/*.txt` `world.json` `facilities.json` |
| 居民/記憶/brain/傳聞/LLM | `npc_memory.gd` `resident.gd` `rumor.gd` `llm.gd` | `bot_sys.gd` `npc_brain.gd` `npc_brain_llm.gd` `llm_client.gd`（sim `_witness_nearby`/`_seed_rumor`/`_rumor_daily`/`rumor_view`/`known_rumors`/`cmd_llm_config`/`cmd_llm_reply`/`cmd_llm_summary`/`llm_view`/`_llm_reflect_daily`） | `residents.json` `llm.json`（key 喺 `user://llm.cfg`，唔入存檔） |

- 已知 UI 欠債：座騎面板繁衍/馬戰/改名已做（U02）；戰騎面板已做（U01，`war_beast_panel.gd`）；NPC 拍賣場戰騎部分已接（U01 寄喺戰騎面板馬廄頁），座騎/馬戰部分拍賣掣留 U04；官宅面板頭銜/官令/義舉/進貢/名額競爭已做（U05，`office_panel.gd`）；內政/城池屬性已做（U06，`office_panel.gd` 第 5 頁）；救災已做（U07，`office_panel.gd` 第 6 頁）；義勇軍成立已做（U08，新 `militia_panel.gd`：頁 0 定居、頁 1 義勇軍成立條件/擁護者/已成立詳情；遊說擁護者掛喺長按居民 menu）；營地已做（U09，新 `camp_panel.gd`：頁 0 設施升級/監督、頁 1 22 項工作、頁 2 評定會議指派/召開、頁 3 倉庫/商情/訓練度）；民心/法令已做（U10，新 `civic_panel.gd`：根據地城池民心/人口/稅率 3 檔/6 條法令開關；`bag_panel.gd` 加丟物品掣）；導航/天眼/嗅血友好技已接（U13，小地圖顯示最近城池名/NPC名牌/低血怪標黃；另接痛楚屏障/加成/聖靈/穩重/遁地地行 5 個純數值友好技；脫出/召喚/神行/回城/火焰/飛影/狂力/開光/野性/奇門冇合適系統掛鈎，留後）；名額競爭 `title_contest_view` read-model 已備（競爭狀態 + 上次結果）但無面板顯示；LLM 設定/對話已做（U11，新 `llm_panel.gd`：頁 0 設定 key/模型+啟用開關/用量顯示、頁 1 對話記錄；`main.gd` 新增真 HTTPRequest 接線 `_on_llm_request()` 補 key header 發送 + 回填 `cmd_llm_reply`/`cmd_llm_summary`）；`acceptQuest`/摘要目標未驅動行為；結婚面板已做（U12，新 `marriage_panel.gd`：頁 0 喜事求婚/喜餅買開分/預約禮堂/舉行婚禮、頁 1 配偶資料/召喚/叮嚀留言/離婚）；結婚村 4 NPC 冇專屬圖示（留後，非阻塞）；建角面板仍係 debug 版
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
`client/assets_placeholder/` = 佔位素材（placeholder，**唔係原版素材**），入 git（已由 .gitignore 移除，會推上 GitHub）。引用一律經 `res://assets_placeholder/`。成品前全部換走。角色暫用頭像、怪物色塊。APK / web 匯出包含佢冇問題。

## 工作方式
- 每細步：spec → `rules/*.gd` + 測試 → sim 指令 + 場景測試 → `run_tests.sh` 全 PASS → 剔 PLAN 格（UI 唔喺呢個範圍，留返後面專門 UI Step 一齊補）
- 偏離 spec 一律寫入 PLAN 該細步「偏離」行；spec 同代碼唔同 → 以 spec 為準（【自訂】且已有測試就改 spec）
- 做完大 Step：更新 PLAN §1 現況表（現況細節已拆去 `docs/plan/SXX.md`，唔再喺本檔重複）、spec 頂「現狀」
- 回覆用廣東話
