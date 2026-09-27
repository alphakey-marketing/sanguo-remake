# 計劃 v6（2026-09-24 重排：逐份 spec 補完 邏輯 先行 + UI 後補）

整體設計見 `DESIGN.md`。**完整系統邏輯規格** = `docs/spec/01~12`。玩法原文摘錄 = `普通玩法_系統摘要.md`。
舊路線 v5（Step 1~19 軌跡、每步「偏離 spec」記錄、驗收項目數）→ `docs/PLAN_v5_history.md`（唔再改，淨係查）。

> **接手 agent 必讀**
> 1. 路線改為 **由 spec 01 順序做到 spec 12**：每份 spec 一個大 Step（S01~S12），入面拆細步（a/b/c…）。下一步 = §3 第一個未剔 `[ ]`。
> 2. **每細步只做邏輯層**：rules 純函數 + 測試 → sim 指令 + 場景測試 → `sh tools/run_tests.sh` 相關組 PASS。UI 延後、唔使一齊交；剔格條件只睇邏輯 + 測試過（UI 欠債記入 §3 對應細步 / `CLAUDE.md`「已知 UI 欠債」）。
> 3. 每個大 Step 開工第一件事 = **核實**：逐節對 spec 同代碼，更新 §1 表同該 Step 清單（有啲可能已做，有啲可能漏列）。
> 4. 跨 spec 依賴：如果某項要用後面 spec 嘅系統（例：專長效果要官宅內政 S08），**而家做資料 + 掛鈎 + 測試，效果喺後面 Step 接**，記入 §4「延後掛鈎表」，後面 Step 開工時要清。
> 5. 每細步要 `sh tools/run_tests.sh` 全 PASS 先剔格；做完大 Step：更新 §1、`CLAUDE.md`「現況」段、相關 spec 頂「現狀」一行。
> 6. 改機制前先睇對應 spec；spec 同代碼唔同 → 以 spec 為準，除非 spec 標【自訂】而代碼已有測試，咁就改 spec 記錄。偏離 spec 一律寫入該細步「偏離」行。
> 7. 標 **【待決】** 嘅位 = 要用家拍板先做；做到嗰步先問，唔好自己估。

---

## §1 各 spec 現況（2026-09-24 核實）

圖例：✅ 做完有測試　🟡 部分　❌ 未開始

| Spec | 邏輯 | UI | 已做（主要檔案） | 欠缺（= §3 對應 Step 範圍） |
|---|---|---|---|---|
| 01 角色成長 | 🟡 | 🟡 | 建角、六屬性、HP/MP/SP、升級點數 + 自動分配、理念測驗、稱號/生日（福日 exp）/臉譜、修練場所、行動力、飲水度、專長、二轉/三轉框架（`rules/stats.gd` `expert.gd` `class.gd`、`sim_char`、`char_panel.gd`） | 三轉考試任務接掛（S04d）；地理迷宮地圖效果（S01c 偏離） |
| 02 戰鬥 | 🟡 | 🟡 | 近戰、術法、相剋、狀態、寶石、義士三招 + 融合、防具/武器 3 槽/耐久、組隊經驗分配（按傷害 70%/平分 30%）、狀態 icon 列、術法快捷列 3 本切換 UI、**仕女（特技開鎖 + 三招絕招）**、**道士（特技超渡 + 三招絕招 + 同伴倒下機制）**、**巫女（特技潛行 + 行車 QTE + 三招絕招 + 潛行避仇恨）**、**辯士（特技竊聽 + 三招絕招 + 弩箭消耗）**、**美女（特技透視 + 洞悉 + 三招絕招 + 恢復術）** | 六職完整；多絕招 HUD 已通；恢復術來源（戰役掉寶）= S04 |
| 03 善惡死亡 | ✅ | ✅ | 七階、死亡掉物品/跌經驗/價格加成、**攻擊居民/紅名 NPC + 反擊/逃跑叫衛兵（S03a）+ 天譴 + 殺人魔拒入城 + 罪犯拒官令（S03b）+ 幸運符/護身符/還魂丹 + 死亡結算彈窗（S03c）** | — |
| 04 怪物地圖 | ✅ | ✅ | 46 怪 + 掉落導入、重生、逃跑/群攻、boss 每日、夜怪、汝南洞 10 層、張牛角戰役、**地面掉落物（`dropped` 實體：300 tick 消失 + 撳地拾取 + 背包滿 + 存檔 roundtrip，S04a）**、**術法怪/boss 技能（遠程吟唱+走位可躲+吟唱線索+`skills`表輪流，S04b）**、**其餘 5 場戰役實體（褚飛燕→李大目→張白騎→黃龍→十常侍 26 層 monster+多層 map+掉寶齊，記事戰役頁+大地圖標示，S04c）** 、**特殊場景首批**（桃花渡 5 層 + 七彩奪寶陣 7 層，game 日曆開門 + 記事場景頁 + 入口對話 + 大地圖標示，S04d） | 通天關/黑山寨/安定戰場/雪山/異族禁地（留返後續批次） |
| 05 生產經濟 | 🟡 | ✅ | 6 初階 + 5 進階 + 2318 配方、修理、工具店、天地商行、捐獻、市場 | 產出 1~2 件、特製/白金/御賜工具、大宗師、4 類商店補齊、天災停進貨、城際貿易提示 |
| 06 任務 | 🟡 | ✅ | 框架、新手 5 條、義士絕招 3 條、官令 7 條、歷史 11+1 條、委託、戰役、團體任務 17 條（16 條義勇軍限定 + 紫虛上人非義勇軍版，S06c）、其他職絕招 15 條（S06d）、**專長任務 8 條（天文/地理認證 1~4 級，S06e）**、**結婚（御賜函任務 2 條 + 喜餅/開餅盒/分餅 + 禮堂/婚禮/婚戒 + 配偶頁/離婚，S09e）** | 四~六招、左慈渾天儀任務、國戰專長（→S10） |
| 07 座騎戰騎 | 🟡 | 🟡 | 17a 座騎全套 + UI；17b 繁衍/馬戰 **sim 有、`main.gd` 有派送、面板未有掣**；18 戰騎純規則；**S07b（leg 5）戰騎 sim 整合**（`sim/sim_war_beast.gd`：馬廄馴養買獸/最多 3 隻/出戰跟隨+自動攻擊+戰鬥特技/吸 exp/死亡忠誠−1/走佬/寄馬廄）；**S07c（leg 6）友好特技效果接系統**；**S07d（leg 7）NPC 拍賣場 + 武將特技「馴馬」+ 抽技固定池** | 繁衍/馬戰/改名 UI；戰騎 UI 面板；原版捕獲途徑；其餘友好技效果（聖靈/遁地/奇門/脫出/召喚/神行/回城/火焰/飛影/狂力/開光/忠誠/巨力/穩重/地行/神獸/嗅血/野性/獅魂/王者） |
| 08 名聲義勇軍 | 🟡 | ✅ | 名聲、頭銜 60 階、官宅（討取/官令/捐獻/月俸/行動丹）、**義舉證明（四類 20 項）+ 城池進貢/好感（S08a）**、**城池屬性 8 項 + 官宅內政 6 種（S08b）**、**救災（S08c）**、**名額競爭（S08d）**、**義勇軍成立 + 定居 + 帶兵量（S08e）**、**營地建設 10 設施 + 義勇軍工作 22 項 + 評定會議（S08f）**、**民心 + 6 條城池法令（S08g；邏輯層，城池佔領啟動留 S10c）** | 佔城啟動（→S10c）、法令下游（山洞商店/PK/善惡入城） |
| 09 登用武將 | 🟡 | 🟡 | 居民 bot/記憶/brain、**居民化 `residents.json`（性格/日程/role，每城 12~20，S09a）**、**傳聞擴散 `rules/rumor.gd` + 每日反思/跨城延遲 1~3 日 + 殺善 NPC→義理忠誠 −15（S09b）**、登用 v1+v2、同伴 6 指令、20 passive 特技、**內政協助 + 內政/生產/經濟被動特技 39~43/45~51（S09c-a）**、**主動特技 21 遁地/22 職業特技/32 挑釁/38 急救（S09c-b）**、**LLM 層 `rules/llm.gd` + `npc_brain_llm.gd` + `llm_client.gd`（白名單/OpenRouter 請求/每日反思摘要/Tier 分配/預算/模板後備，S09d）**、**結婚 `rules/marry.gd` + `sim_marry.gd`（御賜函男/女 + 喜餅 4 價位/開餅盒/分餅回 HP/MP/SP + 禮堂/主婚人/婚禮 + 婚戒無限召喚 50 SP + 配偶頁/叮嚀/離婚 50 萬兩，S09e）** | 鑑定 44（無系統）、國戰類 23~37/53~70（→S10）、LLM UI（設定頁/對話顯示→專 UI Step） |
| 10 國戰 | ❌ | ❌ | — | 全部（D-3【待決】） |
| 11 資料對照 | 🟡 | — | items/monsters/generals/recipes/titles 導入器 | `material_ids.json`、箭矢定義、商城道具單機化定案、recruitinfo 說明頁、warbtl 對照 |
| 12 地圖世界 | ✅(B1~B3) | ✅ | 多地圖/A*/過圖/大地圖/驛站/戰役實例 | 各 Step 需要嘅新地圖（隨 S04/S06/S08 加）；B4 其餘州郡【待決】 |

---

## §2 已完成（軌跡；詳情見 `PLAN_v5_history.md`）

Step 1~5 骨架/戰鬥/存檔/天災/居民 · 7 初階生產 · 7.5 點數+測驗 · 8 任務框架 · 9 術法 · 10 寶石絕招融合 · 11 怪物導入 · 11.5/11.7 地圖 B1/B2 · 11.6 裝備 · 12 進階生產 · 13 天地商行+捐獻 · 13.5 登用 v1 · 14 名聲頭銜官宅 · 15 登用 v2 + 特技 · 15.9 地圖 B2.5 · 16 歷史任務+委託 · 16.5 B3 驛站 · 17a 座騎 · 17b 繁衍馬戰（邏輯）· 18 戰騎（規則）· 19 戰役張牛角 · 手機 HUD + 正式面板

---

## §3 路線：逐份 spec 補完（按序）

### S01 角色成長（spec 01）
- [x] **S01a 核實 + 小缺口**：城內安全區自動回復（每 6 刻 1%，野外唔回）；練兵場小兵免費回 SP（`facilities trainer` + `cmd_facility(id,"restsp")`）；5 級前 HUD 4 鍵 → 5 級後 6 鍵；新手客棧免費補 HP 核實
  - UI：HUD 鍵數跟等級；練兵場互動掣加「回復體力」
  - 完成：`world.json regen`(每 6 tick 回 1% max hp/mp/sp，`Sim._safe_regen_tick`)；`facilities.json trainer` + `cmd_facility(id,"trainer")`→`_fac_restsp`(免費回滿 SP，150 tick 冷卻)；`cmd_rest` 5 級前(`GameData.NEWBIE_LEVEL`)免費、5 級後收 `inn.restCost`；`HudLayout.SKILL_ANGLES` 擴到 6 格(後 2 格用 `SKILL_DIST2` 較大半徑避免重疊)、`HudLayout.skill_cap(level)` 5 級前 4/後 6，`_calc_skill_slots` 用嚟 cap；新 `tests/run_char.gd`(已接入 `run_tests.sh`)
  - 偏離：義士職業內容而家最多只用到 4 格技能位（3 術書+1 絕招，只顯示最後學嘅絕招），5/6 格容量已接好但未有內容填滿——留返 S02c 多職業/多絕招顯示時再接
- [x] **S01b 建角面板正式化**（由舊 Step 27 提前）：姓名 → 稱號 → 生日 → 職業（六職顯示，未開放灰）→ 臉譜 8 部位 → 理念測驗 12 題 → 確認；全部 `ui/panels/` 正式 Control，觸控
  - 完成：`ui/panels/create_panel.gd`（7 頁 tab：姓名/稱號/生日/職業/臉譜/理念/確認，撳「出發！」先完成）；`tests/ui_smoke.gd` 覆蓋全流程（改名/改稱號/答理念測驗）；舊 debug 建角已移除，代碼冇殘留
- [x] **S01c 專長框架**：`data/experts.json`（六職上限表【原】全錄 + 效果係數【自訂】）、`rules/expert.gd`（等級/上限/效果係數純函數）、`ch.expert` + exp 掛鈎 API；**交易** 專長即刻接買賣價；天文/地理 lv≥1 效果（天災情報 / 小地圖顯示設施）即刻接
  - 完成：`data/experts.json`（12 專長 + 六職上限表 + `levelExp [10,30,60,100]`【自訂】）；`rules/expert.gd`（`cap_of/level_of_exp/eff_level/add_exp` + 交易/內政/訓練/救災 效果係數 純函數）；`ch.expert` + `sim.expert_lv()`；交易 即刻接 sim 買賣/代賣/天地商行（`RulesShop` 加 `trade_lv`）+ UI 顯示價（`main._buy_price/_sell_price` 同步）；天文 lv≥1 + 帶渾天儀(26029) → `sim.view_weather()`（各城季節/天災）；地理 lv≥1 → 小地圖顯示全部設施（`mobile_hud.gd`，非傳送點藍色）；角色面板「專長」頁（Lv 色 藍綠紅紫 + 上限 + exp 進度）；新測試入 `run_char.gd`（t_expert_rules/trade/weather_geo，已接入 `run_tests.sh`）；另修 `create_panel` LineEdit reparent（refresh 未即時脫離舊 parent 會炸）
  - 偏離：地理「迷宮地圖」效果未做（而家冇迷宮小地圖系統；小地圖顯示設施已接）
  - 延後掛鈎：內政/救災 → S08；訓練/警戒/偵查/統御/補給 → S08/S10；專長任務 → **S06e（已接）**；渾天儀來源 → S11（見 §4）
- [x] **S01d 二轉 / 三轉框架**：`classes.json` `tier2/tier3`（名/武器群/承繼）；`rules/class.gd`（`tier_of/title_of/tier_name_of/weapon_tier_required/ultimate_usable/expert_cap_bonus/promote_ok`）；`sim.cmd_class_promote`；轉職效果（職名、進階武器解鎖 req_lv 51~99 要二轉/100+ 要三轉、絕招四招起解鎖【原】、專長上限 二轉+1/三轉+2【自訂】）；二轉「轉職考試」任務 `promote_test`（50 級，新導師 NPC `promote_master` + 3 隻試煉怪 19002~19004 掉「試煉之證」×3）
  - 完成：`char_panel.gd` 顯示職名+階級、轉職掣（達標先顯示）；`equip.gd`/`sim_econ.gd` 武器裝備擋 req_tier；`sim_skill.gd` 絕招使用擋 reqTier/reqLevel + 六招「玄冰麒麟」freeze 特效；`experts.json` levelExp 加到 6 級；`run_char.gd` +5 個測試（t_class_rules/t_promote_flow/t_ult_req_tier/t_weapon_req_tier/t_expert_tier_boost）；`run_monsters.gd` CUSTOM_DROPS 白名單 +19002~19004
  - 偏離：試煉怪 id 原定 21001~21003，同 CSV 現有怪物撞號，改用 19002~19004（無主 id 段，同 19001 洞窟獸王相鄰）
  - UI：角色面板顯示職階；轉職掣（`main._send({"t":"promote"})` → `sim.cmd_class_promote`）
  - 延後掛鈎：三轉任務 `promote_test2`（七彩項鍊）→ S04 特殊場景做完先接（見 §4）
- 驗收：`tests/run_char.gd`（新）+ 相關舊測試 + `--uitest`

### S02 戰鬥（spec 02）
- [x] **S02a 核實 + 狀態 icon 列 + 術法快捷列**：血條下 status icon；術書 3 本切換 UI（`ch.equip.spellbook` 已有）
  - 核實：物理/術法/寶石/相剋/絕招/狀態/組隊 rules 已有齊全測試（見 §1 表）；術法快捷列 3 本切換 UI 已喺 `bag_panel.gd`（裝備/卸下 spellbook slot）做咗，冇缺
  - 完成：角色框底部加狀態 icon 列（`HudLayout.STATUS_ROW_H`、`mobile_hud._draw_status_icons`）— 逐個 active status 顯示短名 + 剩餘秒數；`log_rect`/`joy_zone` 相應落移 18px 讓位；`run_tests.sh` 全 PASS（`run_hud.gd` 4195 條）
- [x] **S02b 組隊經驗**：隊伍上限 6；經驗池 70% 按傷害 / 30% 平分【自訂】取代「同伴 50% 歸主公」；同伴自己有 exp/等級（用家確認：要）
  - 完成：`RulesGeneral.team_exp_split(total, dmg_by_id, cap=6)` 純函數（`rules/general.gd`）；`damage()` 記低邊個對隻怪出過幾多傷害（`m["dmg"]`）；`sim_combat._kill_mob` 死嗰陣按呢個 map 逐個隊員 `gain_exp`（掉落/金/善惡仍歸擊殺者，唔跟隊伍池分）；單一貢獻者=攞晒 100%，向下兼容舊單人/單同伴打法
  - UI：HUD 同伴框加經驗條（`companion_view().exp/needExp`）；隊伍面板：而家隊伍實質淨得 1 同伴（spec09 多登用武將未做），HUD 已夠顯示，獨立隊伍面板留返多同伴嗰步先加
  - 偏離：舊「教導」特技（`expShareAdd`，主公經驗 +25%）喺舊「同伴代打全歸主公」模型先有意思；新按傷害分模型下主公冇出手就分唔到，教導特技暫時冧咗效果，留返 Spec09 補完期一齊諗點接（`general_skills.json` 15 號特技描述未改，代碼行為已改）
  - 驗收：`tests/run_general.gd`（新 `t_team_exp_split` 12 項 pure 測試）+ `tests/run_recruit.gd`/`run_general.gd` 舊同伴殺怪測試改期望值；`run_tests.sh` 全 PASS
- [x] **S02c-仕女（用家揀：先做仕女一職試水）**：`classes.json` 啟用仕女 + 起始裝備（劍系）、職業武器對應（劍/爪/環 cat 4/5/6，`_weapon_ok` 已按 classes.weapons 檢查）、特技「開鎖」、初階三招絕招（虎嘯龍吟/金環裂地/鏡花水月）、HUD 多絕招逐招一格
  - 完成：`classes.json` shinu `enabled=true` + `starter.shinu`（11001 越女劍）；`ultimates.json` +3 招（數值模板 §5，weaponCat 6 環，任務鏈 S06d 接，quest 暫空）；`data/class_skills.json` + `rules/class_skill.gd`（def_of/learned/can_use 純函數）+ `GameData.class_skills`；`rules/quest.gd` reward 加 `skill` key（學識 → `ch.classSkill`）＋ validator 檢查 ultimate/skill；`stats.gd`/`_spawn_actor` 加 `classSkill` 欄；導師 NPC `shinu_master`（黃師姐，許昌 52,39，minLevel 5）+ 任務 `skill_unlock_shinu`（答題 → 學識開鎖）；`sim_skill.gd` `cmd_use_skill`/`cmd_skill_pick`/`_near_locked_chest`（unlock_open/unlock_done 事件）；新 `ui/panels/unlock_panel.gd`（揀真鑰匙×3 道門）+ HUD 技能扇形加「特技」掣；main 接 `use_skill`/`skill_pick`/事件/任務獎勵顯示；`cmd_debug_learn` + 更多面板「學初階絕招/學特技」debug 掣（手機無鍵盤測招式）；新 `tests/run_class.gd`（81 項）接入 `run_tests.sh`；`--uitest` 加技能扇形多絕招 + 特技掣（冇寶箱提示）
  - 偏離：仕女三招絕招全部用「環」（weaponCat 6）【自訂】——同義士全用槍矛先例；三轉後五/六招武器未定
  - 延後掛鈎：開鎖效果（任務寶箱/門實體）→ S04 寶箱實體 / S06 任務寶箱（sim 指令 + 事件 + 面板已通，見 §4）；絕招任務鏈 → S06d；HUD 4 格位喺 S01a 嘅留白而家由多絕招補埋
  - 驗收：`tests/run_class.gd`（新，81 項）+ rules 向量更新（createCharacter 加 classSkill）+ `--uitest` 技能扇形特技一項
- [x] **S02c-道士**：超渡特技（同伴死亡復活，扣 HP 20% + MP 30%）+ 導師 NPC；佢三招絕招
  - 完成：`class_skills.json` + `chaodu`（超渡，道士 lv5，導師任務 `skill_unlock_daoshi`）；導師 NPC `daoshi_master`（玄真道人，許昌 18,44，minLevel 5）+ 答題任務（答啱 reward skill=chaodu）；`ultimates.json` +3 招（虛無飄渺/如幻似真/神遊太虛，weaponCat 15 符咒，模板 §5）＝初階三招無 reqTier；HUD 特技掣／多絕招逐招一格（仕女已通，道士直用）；`sim_skill.gd` `cmd_use_skill` + `chaodu` 分支 + `_try_chaodu`（復活附近 5 格倒下同伴，靜清自己 HP20%+MP30%，emit `revive`）；main 接 `companion_down/revive/companion_ko` banner
  - 偏離：**同伴「倒下」機制改咗**（spec 02 §6 超渡需要「死亡復活」目標）——同伴被打低而家唔再即時飛返客棧，改為原地進入 `down` 狀態（hp 0）等道士「超渡」；超過 `world.combat.compDownTicks`(600) 未救先退返客棧（忠誠 -ko，堅忍特技豁免，兜底免得冇道士時同伴永久倒地）。`run_recruit.gd t_comp_ko` + `run_general.gd t_skill_misc` 對應更新
  - 測試：`tests/run_class.gd` +道士 3 組（三絕招定義+可用性／導師答題學超渡+非道士擋＋存檔 roundtrip／超渡使用：冇倒下唔扣血、靈力或體力唔夠阻擋、夠就復活回滿+扣自己、忠誠唔跌、超時未救返客棧+扣忠誠）；`tests/ui_smoke.gd` + 超渡特技掣煙霧
- [x] **S02c-巫女**：潛行特技（潛行狀態 10 分鐘避仇恨，CD 1 game 日）+ 小遊戲 + 導師；佢三招絕招
  - 完成：`classes.json` 啟用巫女（`enabled=true`）+ 起始裝備（卷軸 13038，cat 12）；`ultimates.json` +3 招（殘燈映紅/膽顫心驚/鬼哭神號，weaponCat 12）；`class_skills.json` + `yinxing`（潛行，巫女 lv5，導師任務 `skill_unlock_wunu`）；導師 NPC `wunu_master`（巫姬婆，許昌 46,34，minLevel 5）+ 答題任務；新 `rules/stealth.gd`（RulesStealth：潛行 5 tick = 10 分 / CD 720 tick = 1 game 日 / 行車 QTE pattern + 穿越判定，純函數）；`sim_skill.gd` `_try_yinxing`（開行車 QTE）+ `cmd_stealth_cross`（穿越判定：全部成功 → 入潛行 status + 設 CD；撞車 → fail）；`sim_ai.gd` 遊蕩掃描跳過潛行玩家；新 `ui/panels/stealth_panel.gd`（行車車位 + 穿梭點 + 穿過掣，`_process` update）；main 接 `stealth_open/stealth_done/stealth_fail` 事件 + `stealth_cross` 指令 + `STATUS_NAMES` 加「潛行」；HUD 註冊 stealth 面板
  - 小遊戲設計：行車之間穿越【自訂簡化】= 3 卡車逐卡，每卡週期 10 tick 但空隙安全窗 3 tick（offset 由 SimRng 生成，可重現）；玩家要喺每卡空隙嗰吓撳「穿過」，撞車即失敗
  - 偏離：巫女三招絕招全部用「卷軸」（weaponCat 12）【自訂】——同義士/仕女/道士先例；絶招任務鏈 → S06d 接；潛行用手身 status「stealth」（進 `view_ents().statuses`）而唔另開欄
  - 測試：`tests/run_stealth.gd`（新，24 項 RulesStealth 純函數）+ `tests/run_class.gd` 巫女 3 組（三招絕招定義+可用性／導師答題學潛行+非巫女擋+存檔 roundtrip／行車 QTE 全穿成功+撞車失敗+CD+潛行避主動怪仇恨）；`tests/ui_smoke.gd` + 潛行特技掣煙霧（開面板）
  - 驗收：`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [x] **S02c-辯士**：竊聽特技（居民對話竊聽情報）+ 導師；佢三招絕招；**弩箭消耗**（箭矢 cat 49 已有 items，要消耗邏輯 + 商店賣箭/木匠製箭 = S05）
  - 完成：`classes.json` 啟用辯士（`enabled=true`）+ 起始裝備（十字弩 12025 貓9 + 羽箭 12101×50）；`ultimates.json` +3 招（天道循環/吐火羅語/三分天下，weaponCat 9 弩）；`class_skills.json` + `qieting`（竊聽，辯士 lv5，導師任務 `skill_unlock_bianshi`）；導師 NPC `bianshi_master`（蔡師傅，許昌 44,36，minLevel 5）+ 答題任務；新 `data/rumors.json`（12 條傳聞線索池）+ `GameData.rumors`；新 `rules/qieting.gd`（RulesQieting：竊聽範圍 3 / CD 300 tick / 揀未聽過嘅傳聞，純函數）+ `rules/ammo.gd`（RulesAmmo：弩 cat 9 / 箭 cat 49 / count·consume，純函數）；`sim_skill.gd` `cmd_use_skill` + `_try_qieting`（附近 bot/任務 NPC 竊聽 → 記入 `ch.rumors` 情報冊 + 設 CD + emit `qieting`）；`sim_ai.gd` 弩箭消耗（用弩射箭：冇箭唔出手 + 命中每發扣 1 箭）；`sim_core.gd` `ch.rumors` 初始 []；新 `ui/panels/rumor_panel.gd`（情報冊）+ MorePanel「情報冊（竊聽）」掣 + main 接 `qieting` 事件（耳邊「…」banner）
  - 偏離：竊聽用「bot 居民 + 任務 NPC」做目標【自訂】（單機冇真玩家）；弩箭消耗淨係普通弩攻擊扣（絶招唔扣箭，spec 係話「穿心箭」等技能，今次三招唔屬於呢啲）
  - 延後掛鈎：弩箭來源（商店賣箭 / 木匠製箭）→ S05（見 §4）
  - 測試：`tests/run_class.gd` +5 組（辯士三絕招定義+可用性／起始弩+箭／導師答題學竊聽+非辯士擋+存檔 roundtrip／竊聽冇居民擋+有居民得傳聞線索+CD+去重+情報冊持久／弩箭消耗：用弩射箭扣箭+冇箭唔出手+consume 純函數）＝238 項；`tests/ui_smoke.gd` + 竊聽特技掣煙霧
  - 驗收：`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [x] **S02c-美女**：透視特技（睇 NPC/怪隱藏資訊）+ 導師；佢三招絕招（美女仲有葉/針術 + 恢復術，照術書表）
  - 完成：`classes.json` 啟用美女（`enabled=true`，spell=heal）+ 起始裝備（連珠琴 15025 cat 18 + 葉之術小 30513）；`ultimates.json` +3 招（笑撥弦步/松竹聽雨/飛花點翠，weaponCat 18 琴）；`class_skills.json` + `toushi`（透視，美女 lv5，導師任務 `skill_unlock_meinu`）；導師 NPC `meinu_master`（夢韶華，許昌 40,32，minLevel 5）+ 答題任務；新 `rules/toushi.gd`（RulesToushi：透視範圍 6 / CD 180 tick / 洞悉 150 tick / 弱點屬性 = 剋目標嗰個元素，純函數）；`sim_skill.gd` `cmd_use_skill` + `toushi` 分支 + `_try_toushi`（揀最近目標揭示隱藏資訊 HP/MP/等級/弱點 + 入洞悉狀態 +20% 攻擊，emit `toushi`）；`rules/spell.gd` `atk_mult` 加洞悉 +20% + `INSIGHT_ATK_MULT`；新增「恢復術」一~七級（items.json +30697~30703 + spells.json `huifu1~7`，kind=heal 單體補 HP，數值 50/120/220/400/700/1100/1800，MP=25/30/35/40/45/50/55）＋ `sim_skill.gd` `_spell_heal`（施法補自己/同伴，emit `restore`）＋ `cmd_cast_spell` heal 支援 target 0 = 自己；main 接 `toushi` 事件（`set_banner` 顯示資訊 + log）＋ `STATUS_NAMES` 加「洞悉」；HUD 技能扇形已通（美女自動有透視特技 + 三招絕招 + 術書格，葉/針術 classes 已有美女）
  - 偏離：美女三招絕招全部用「琴」（weaponCat 18）【自訂】——美女三武器系 16/17/18（袖帶/匕首/琴）揀一，琴符描「撥弦」（笑撥弦步）/優雅形象，同義士/仕女/巫女/辯士各職用單一主武器系先例；透視「戰鬥優勢」【自訂】＝揭示資訊 + 入洞悉狀態 +20% 攻擊力（有冷卻 180 tick）；恢復術數值【自訂】照 spec 術書表（50~1800），MP = 20+5×級，等級 10/16/22/28/34/40/46（任務/戰役掉寶）；絶招任務鏈 → S06d 接
  - 延後掛鈎：恢復術來源（戰役/任務掉寶 → S04 接）
  - 測試：`tests/run_class.gd` +6 組（美女三絕招定義+可用性／美女起始琴+背包／導師答題學透視+非美女擋+存檔 roundtrip／透視用冇目標擋+有目標資訊+入洞悉+atk_mult>1+CD／恢復術七級定義+item 存在+裝備快捷列+施法自己補 HP 唔超上限）＝317 項；`tests/ui_smoke.gd` + 透視特技掣煙霧（撳掣 → 有提示/透視，唔炸）
  - 驗收：`sh tools/run_tests.sh` 全 PASS（ALL OK）

### S03 善惡死亡（spec 03）
- [x] **S03a 可攻擊 NPC**：`cmd_attack` 開放居民/紅名 NPC（安全區照禁）；居民反擊/逃跑/叫衛兵；殺善一次過 −1000、紅殺紅 +300、反擊成功 +100
  - 完成：`rules/karma.gd` 加 `karma_after_kill_npc`（殺善居民: 非惡直接 `-1000` / 惡人累積 `-1000`；殺紅名一律 `+300`；`counter_kill` 反擊成功 `+100`）；`cmd_attack` 開放 `kind==bot` 做攻擊目標（安全區照禁，出手前 `_think_player` 擋）；`_think_player` 泛化去追/打任何 `ch` 目標（怪睇 `mob_def` 防禦，NPC 用 `player_def`）；`_kill_bot`（唔行玩家死亡流程：`damage()` 加 bot 分支路由去 `_kill_bot`，善惡 + 目擊 + 移除 + `kill_npc` 事件）；居民被襲反應（`damage()` bot 分支: 反擊 `atk_target=攻擊者` 或 `fleeChance` 逃跑）；`bot_sys.gd` 逃跑去叫衛兵（`_pk_flee` → 安全區/客棧 `guard_alert` + 消失）+ 紅名居民主動襲擊玩家（`_crime_find_player`，潛行唔會被發現）；世界配置 `world.json bots.criminalPct/fleeChance/crimeAggro`；`view_ents` 加 `criminal`；新 `tests/run_pk.gd`（31 項）接入 `run_tests.sh`；`run_tests.sh` 全 PASS（ALL OK）
  - 偏離：**紅名 NPC** 用「居民中一小部分 criminalPct 係殺人魔（紅名）」表示【自訂】——單機冇真玩家 PK，用居民警告話你知佢係殺人魔（UI 紅名顯示；`npc_brain.gd LINES_WARN_KARMA` 已備）。「反擊 +100」= 玩家冇先行襲擊嗰隻 bot（自衛反殺）先計，疊加喺紅殺/殺善基礎上
  - UI：長按 NPC（居民）出「攻擊」menu + 二次確認（`_handle_long_press`/`_open_npc_attack`，安全區灰）；紅名居民紅字顯示；`kill_npc`/`guard_alert` 事件入日誌
  - 延後掛鈎：叫衛兵 `guard_alert` / 目擊記錄 → S03b 城門衛兵拒入 + 罪犯拒官令（見 §4）
- [x] **S03b 天譴 + 城門**：殺居民（非自衛）→ 雷劈 50% HP + 傳送客棧 + 公告；殺人魔城門衛兵拒入 + 警告；罪犯以下唔接官令
  - 完成：`rules/karma.gd` 加 `tianqian_hp`（HP×50% 最少 1）/`tianqian_announce`/`tianqian_blocks_revive`（還魂丹無效 invariant，S03c 用）/`city_banned`（tier6）/`office_blocked`（tier≥4）/`guard_warn_text`；`sim_combat.gd _kill_bot` 殺善居民（非紅名＋玩家先行出手=非自衛）→ `_tianqian_reprisal`（雷劈現有 HP 50% + 傳返最近客棧 + ch.tianqian 旗 + kill_npc/tianqian 事件帶公告）；`sim.gd _city_guard_check`（殺人魔喺安全區 → 定時 `guard_warn`，節流 ticks = `world.json bots.guardWarnTicks`）；`sim_econ.gd cmd_rest` 殺人魔留宿被拒；`sim_office.gd order_block` 罪犯以下拒接官令（sim + UI 灰掣同步）；UI `main.gd` `tianqian` banner + `guard_warn` log；`tests/run_pk.gd` 加 10 組（規則 + 天譴 + 自衛唔啪天譴 + 衛兵警告 + 休息拒 + 罪犯拒官令 + 中立接官令對照），pk 65 項目；`run_tests.sh` 全 PASS（ALL OK）
  - 偏離/設計決策：**城門「拒入城」**喺連續地圖單機化用「城內服務拒絶（客棧留宿）+ 定期衛兵警告 guard_warn」實現，而唔係硬閂城門——單機死亡喺客棧重生，先天唔兼容「硬性禁入」；用善惡「鉅觀開/關」剔除城內服務最穏（spec 03 §5），見 §4。
  - UI：天譴「雷劈」世界橫幅公告 + 日誌；城門衛兵警告入日誌；官令掣因 order_block 自動灰
  - 接 S03a 延後掛鈎（§4 S03a 行）：guard_alert 事件已由 UI 處理；目擊 `W_KILL_NPC` 已有；殺人魔城門 / 罪犯拒官令接晒
- [x] **S03c 死亡道具**：幸運符（唔跌物品）/護身符（經驗減半）/還魂丹（天譴無效）；來源【待決，同 spec 11 商城道具定案 → 淨返票先由藥膳師庫存頂住，見 §4】；死亡流程 6 步順序照 §4.3
  - 完成：`rules/combat.gd` 加 `LUCKY_CHARM/PROTECTION_CHARM/REVIVE_PILL`、`death_drop_table()`（七階掉物表全檔 §4.1）、`roll_death_drop_items()`（逐件獨立擲骰 + 上限，唔跌裝備件）、`death_exp_loss_protected()`（護身符經驗減半）；`sim/sim_combat.gd _kill_player` 改照 §4.3 六步（還魂丹存活先消耗 → 扣經驗護身符半 → 掉物幸運符擋 → 傳客棧回一半 → 目擊死亡 → 耐久 −10%），death 回血改滿→半（`sim_core.gd _half_heal`）；`bot_sys.gd W_SEE_DIE=2`（目擊死亡好心微升）；`data/items.json` 加三件（型 200 消耗品、價 500/800/1500）+ `data/shops.json` 藥膳師庫存補三件；UI `main.gd` `_death_report()` 死亡結算彈窗（跌咗乜/扣幾多/道具消耗）+ `die` 事件富欄位（exp_lost/dropped/revived/lucky/huhushen）；`game_panel.gd` 說明 render value-0 效果作純 label；新 `tests/run_karma.gd`（41 項目：規則 + 死流程 + 三道具 + 天譴還魂無效）接入 `run_tests.sh`；`run_tests.sh` 全 PASS（神 PASS：sim 死亡回血改半 → 舊 `run_sim.gd` 期望回滿 → 同步改半）
  - 設計決策：**死亡回血原版全滿改半**（spec §4.3 step 3 已寫「回一半」）；**還魂丹**單機下死亡本就回客棧，效果=「消耗一件丹」（可見效果），物品/經驗照掉，天譴唔消耗（`tianqian` 旗擋）；**掉物唔跌裝備件**【自訂】只喺未裝嘅件數入面擲（§4.1「優先裝備槽」單機化）；**來源**：三件暫時入藥膳師（herbalist）庫存，價格 500/800/1500，spec 11 商城定案時再改（§4）
  - UI：背包說明、死亡結算彈窗（跌咗乜/扣幾多）、`_death_report` 文言富欄位
  - 驗收：`tests/run_karma.gd`（41 項目）+ `ui_smoke.gd` 死亡結算文言 + 真死一次（uitest 114 項目）

### S04 怪物地圖（spec 04）
- [x] **S04a 地面掉落物**：`dropped` 實體（300 tick 消失）、撳地拾取、背包滿處理；存檔 roundtrip
  - UI：地上物品圖示 + 拾取掣
  - 偏離【待決→用推薦方針】:
    - 「背包滿」= 揀負重式（`items.json` weight × 件數 加埋 ＞ `world.json dropped.capBagWeight` 預設 1000）【自訂】；負重上限公式 / 稱號加成等 S05 城際貿易再定（見 §4 S04a 行）。負重系統 S05 重磅重用。
    - 戰役掉落（battle_id≠""）：過層即傳送走，跌落地執唔返 → 掉寶照直入袋（保留戰役獎勵／恢復術來源），野外/普通怪才跌落地。
  - 驗收：`tests/run_monsters.gd` 加 5 組（掉落地/300 tick/拾取/背包滿/存檔 roundtrip + 重量規則）+ `ui_smoke` 拾取煙霧 → 全 PASS
- [x] **S04b 術法怪 / boss 技能列表**：遠程術攻擊（唔埋身近戰，吟唱鎖定落點，行開走位可躲）+ 吟唱線索（UI 落點紅圈 + 怪身框）；boss 技能表資料化（`monsters.json` 每 boss 加 `skills:[{spell,cd}]`，`_think_mob` 輪流放 + `skill_cd` 記低）
  - 數據：術法怪 1007/1008/1009 加 `ranged:true`（遠程唔埋身近戰）；boss 19001 張牛角加 `skills`（huo_s cd300 / huo_m cd540）
  - 偏離：
    - boss 技能只配 19001（今批得張牛角 boss）；其餘 5 場戰役 boss 留 S04c 實裝時加 `skills`（重用 `d.get("skills")` 路徑）。
    - 術法怪能力用現有術書（huo_s/seal/hex），唔另設新手軍書；boss 技能 reuse 術書 spell id（`item` 欄 mob 唔讀）。
  - 驗收：`tests/run_monsters.gd` 加 6 組（遠程境地法/座落點躲避/唔埋身近戰/boss 技能輪流+skill_cd/吟唱線索透出/存檔 roundtrip）+ `ui_smoke` 吟唱線索煙霧 → 全 PASS（monsters 1464）
- [x] **S04c 其餘 5 場戰役實裝**：褚飛燕 → 李大目 → 張白騎 → 黃龍 → 十常侍（每場 monster + 多層 map + 掉寶齊）；戰役狀態入記事/大地圖
  - UI：記事「戰役」頁（今日窗口/進度）、大地圖標示
  - 完成：`tools/gen_battles.py`（新導入器，--check 核對、idempotent）將 `data/battles.json` 5 場補齊 playable：每層配 `monster`（boss id 1039~1064，26 隻，數值【自訂】按 lv template 遞增）+ `map`（26 張 16×16 戰役地圖 `maps/<bid>_f<n>.txt`，自動打包揾 free 位、地圖間 ≥20 格分隔唔相撞）；`rules/battle.gd can_enter` 移除「原型只做張牛角戰役」；`sim_battle.gd` 加 `view_battles()` read-model；UI 記事加「戰役」tab（今日窗口/武等/進度）+ 大地圖加戰役窗口標示
  - 設計決策【自訂】：**每層一格 boss**（sim 單一格 boss/層盡頭目），攻略一層多頭目 = 併入嗰層 boss 名（「X/…」），掉寶照攻略全併入嗰層 monster drops（保持原掉寶表）；**尾層大頭目加 `skills`**（延續 S04b），interim 層頭目用近戰（唔加技能）；**boss 數值** = `hp=6.5·lv²+400 / atk=3.2·lv+2 / exp=95·lv`【自訂】隨 lv 遞增（練功打寶戰役頭目，較強）；**戰役地圖 16×16**（跟張牛角）由 generator 起稿
  - 測試：`run_battle.gd` 297 項（t_data 全部 6 場 playable+monster/map/drops 完整性 + t_five_battles 逐場入層打死完場掉寶齊 + t_enter 改做褚飛燕）；`run_monsters.gd` 手寫怪計數 38→64 + `CUSTOM_BATTLE` 白名單（1039~1064）；`ui_smoke` 加戰役 tab/view_battles 煙霧 → 全 PASS（battle 297 / monsters 1464 / maps 2807 / ui_smoke 124）
  - 踩坑：GDScript 嘅 `var x :=` 唔識推斷 function 回傳 Dictionary 型（quest_panel/map_panel/ui_smoke）→ 改顯式 `var x: Dictionary =` 先編譯到（否則主面板 load 唔到 → uitest watchdog 超時）
- [x] **S04d 特殊場景框架 + 首批**：`data/scenes.json`（schema 照 §4）、game 日曆開門、公告；首批 = 桃花渡 → 七彩奪寶陣（接 S01d 三轉）
  - UI：入口 NPC 對話（進入/離開場景）、記事「場景」頁（今日 = 幾號、各場開門日/入面進度）、大地圖標示
  - 完成：`rules/scene.gd`（RulesScene：日曆開門 `is_open`/`day_of_month`/`can_enter`/層數/尾層/`layer_boss` 純函數）；`data/scenes.json`（桃花渡 15 隻怪 5 層 + 七彩奪寶陣 7 色孟獲 7 層，攻略掉寶全表落每隻怪 `drops`）；`tools/gen_scenes.py`（新導入器，--check 核對、idempotent，將怪物/地圖分發落 `monsters.json`/`maps.json`/`maps/<id>_f<n>.txt`，共 22 隻怪 + 12 張地圖）；`sim/sim_scene.gd`（企喺 `sim_battle` 之上、`sim_combat` 之下：`cmd_scene_enter`/`cmd_scene_leave`/`_scene_goto_layer`/`_scene_on_boss_kill`/`_scene_exit`/`view_scenes`/`scene_view`）；`sim_combat._kill_mob` 打死場景 boss 掛鈎 `_scene_on_boss_kill`；`sim.gd` 每日子時場景開門日公告（`scene_open` 事件，去重 `lastAnnounceDay`）；`data/quest_npcs.json` 加桃花渡/七彩奪寶陣入口 NPC（`scene:<id>` 標記）；`ui/touch/context_actions.gd` `scene_dialog`（進入/離開場景掣）；`ui/panels/quest_panel.gd` 加「場景」tab（`_scene_section`）；`ui/panels/map_panel.gd` 大地圖顯示場景進度
  - 單機化：七彩奪寶陣原版限真實時間（週六晚）→ 改 game 日曆開門（每月初一~初三、十五~十七，公告提示），桃花渡跟同一窗口【自訂簡化，spec 冇明確桃花渡時窗】
  - 場景 boss 死亡掛鈎：未到尾層過下層（重新 spawn 該層怪 + 傳送玩家）、到尾層自動離場傳返入口 + 清晒殘留場景怪；場景內死亡唔跌經驗/物品（同戰役），傳返入口原位
  - 測試：`tests/run_scene.gd`（新，107 項：純函數日曆/資格/層 + 資料完整性 + sim 入場/過 5 層完場/七彩 7 色孟獲逐層/死亡唔跌/離開/等級閘/關門日/存檔 roundtrip/決定性）；`run_monsters.gd` 手寫怪計數 64→86 + `CUSTOM_SCENE` 白名單（1065~1086）；`ui_smoke` 加場景 tab/入口對話/入場離場煙霧 → 全 PASS（scene 107 / monsters 1464 / ui_smoke 126）
- 驗收：`tests/run_monsters.gd`/`run_battle.gd` 擴充 + `tests/run_scene.gd`（新）

### S05 生產經濟（spec 05）
- [x] **S05a 小缺口**：初階產出 1~2 件；4 類商店補齊（工具/藥房/食物/雜貨）；天災大/中規模停進貨 `shutdownDays`；城際價差（地圖面板顯示各城市價）
  - 產出 1~2 件：農耕/伐木/採礦加 `work.json` 各技能 `doubleChance:0.15`（一般成功額外 15% 多收 1 件，同大成功 0.5% 不重疊），對應 spec §2 表；狩獵/釣魚/採藥表寫「1 件」冇加（維持只有大成功罕有雙倍）
  - 4 類商店：`shops.json` 5 城（許昌/新野/汝南/宛城/襄陽）各補齊工具商/藥膳師/食坊/雜貨店（新增 17 間店），座標揀現有商店同款地格（`:`）
  - 天災停進貨：`world.json` 加 `shopShutdown:{min:1,max:3}`；`rules/disaster.gd roll_day()` 大/中規模天災額外算 `shutdownEnd`/`shutdownCats`；`sim_econ.gd cmd_buy` 擋購買 + 訊息提示
  - 城際價差 UI：`sim.gd view_market_prices()` 新 read-model + `map_panel.gd` 新「市價」頁（文字列表，代表物資 × 各城現價）
  - 偏離：「城際貿易搬運跨城賣」（§6 表）未做，留後續批次（見 spec 05 §9）；雜貨店定義用 items.json cat 250（消耗/特殊）頂替【自訂】
- [x] **S05b 特製/白金/御賜工具**：3 等工具耐久/成功率；來源 = 任務獎勵（團體任務 S06c 前先用官宅兌換過渡）
  - 偏移：items.json 原有 26041~26073（33 件，每技能 3 等）已係特製/白金/御賜工具，直接用原 id，冇加新自訂 item；`work.json` 各技能 `tiers` 對照 + 頂層 `tierBonus`（特製耐久800/+5%、白金2000/+10%、御賜5000/+15%【自訂數值，spec 只寫特製/白金】）。御賜工具（u24=1 綁定）用 `sim_office.gd cmd_office_redeem_tool` 官宅貢獻兌換（初階 200 / 進階 400 貢獻，**過渡**，等 S06c 團體任務「初階御賜工具的取得」開返正式來源，見 §4 表）。UI：官宅面板「換御賜工具…」+ 野外工作/工房裝工具自動揀背包最好嗰件。
- [x] **S05c 大宗師合成術**：條件 100/20、新初階/進階材料、白晝之珠、5 合成寶石、進階大宗師（`data/master_recipes.json`）
  - 完成：新增 22 件 item（`tools/add_master_items.py` 一次性寫入 `items.json`，追加式唔打亂原有順序）：6 新初階材料（黃金稻穗/飛天龍魚/荒野虎肉/璀璨晶礦/鐵樹精華/九命人參）+ 5 新進階材料（茗香泉水/煉獄礦石/雪羽晶塊/天山樹鬚/不老丹藥）+ 白晝之珠 + 5 合成寶石（扈江/玄牝/炎冥/仲卿/山淵之石）+ 5 虛擬寶物（龍威寶鼎等）；新 `rules/master.gd`（`gem_ready`/`has_need`/`gem_count_ok`/`synth_chance`/`pick_treasure` 純函數）+ `data/master_recipes.json`（條件/材料表/寶石配方/虛寶池/合成成功率公式）；`sim_econ.gd` 加 `_master_gather_bonus`（掛喺 `cmd_work`/`cmd_craft` 尾、用御賜工具時額外機會夾埋材料，唔加額外 SP/耐久/exp）+ `cmd_master_gem`/`cmd_master_treasure`/`cmd_master_redeem_baizhu`/`view_master`；`main.gd` 接 3 個新指令；`craft_panel.gd` 廚房/藥房/工房加「大宗師」頁（兌換白晝之珠/合成寶石/進階合成虛寶）
  - 偏離：**新材料產出地**（原文豫荊外六城：廬江/北平/壽春/北海/南皮/柴桑）單機只做豫荊【自訂簡化，用家確認方針】→ 改為冇獨立地點，用御賜工具做返嗰種初階/進階工作時 5% 機會額外夾埋材料；**白晝之珠**（原文神秘洞窟打怪掉落）→ 過渡用官宅貢獻兌換（同 S05b 御賜工具模式一致），神秘洞窟場景延後見 §4；**寶石配方**（材料組合對照表原文喺攻略未逐格搬字）→ 自訂每種寶石 = 對應初階材料×5 + 進階材料×3 + 白晝之珠×1；**進階大宗師合成術**輸出簡化為 5 件收藏向「虛擬寶物」（唔做完整隨機武防詞條生成），成功率公式【自訂】= 0.15 + 0.01×進階技能等級
  - 延後掛鈎：白晝之珠正式來源（神秘洞窟場景）→ 見 §4；場景開唔開放由城主法令決定 → S08 法令做完先接（而家常開）
  - 驗收：`tests/run_master.gd`（新，67 項）+ `sh tools/run_tests.sh` 全 PASS（ALL OK）
- 驗收：`tests/run_craft.gd`/`run_tiandi.gd` 擴充 + `tests/run_master.gd`（新）

### S06 任務（spec 06）
- [x] **S06a 官令補齊**：訂製軍備、官員護衛（護送 NPC）、朝廷求才（登用 1 文官）、流落官員（野外救人）
  - 完成：`data/office.json` 官令 3→7 條（新 `custom_arms`/`recruit`/`escort`/`rescue`）；`sim_office.gd` 加 4 個 kind 分支（`buy`/`recruit`/`escort`/`rescue`）+ `_office_tick()`（護衛/救援 NPC 死咗即自動失敗，唔退行動力）；`sim_recruit.gd` 加 `_spawn_office_npc`/`_think_office_npc`（借用同伴 `gen` kind 嘅過圖/HP/「倒下」機制，HP 到 0 觸發現有 `_kill_player` 嘅 `down` 分支，唔會真死）+ `_think_companion` 頂部分流。UI 零改動：官宅面板/官令清單本身數據驅動（`context_actions.gd order_dialog`/`office_dialog` 逐條 loop `data.office["orders"]`），`order_text()` 加 4 個 kind 顯示（護衛/救援仲加埋 NPC HP/狀態一句）。測試：`tests/run_title.gd` 加 4 個 `t_order_*` 函數（32→130 項）。
  - 偏離：**訂製軍備**冇驗證武器係咪真係喺武器店買（同 `letter`/`arms` 一致嘅簡化：淨係查背包有冇指定 item，交收即扣）；指定武器揀 10002（鬼頭刀，武器店有賣，非新手起始裝備，避免同起始柳葉刀 10001 撞）。**官員護衛/流落官員**嘅「打怪區」= `field_1`（潁川郊外，`DEFAULT_ZONE`）；NPC = `gen` kind 單位（唔係真同伴，`ch.recruit.comp` 唔會指到佢），escort 生成即跟主公、rescue 企定喺 `field_1` (52,5)~(96,22) 隨機一格等玩家埋身 3 格內先開始跟隨；NPC 冇打怪能力（純被動，可以被怪打），死咗 = 進入現有「倒下」狀態（唔會真消失喺存檔中途，`_office_tick` 見到 `down` 即刻拆走官令 + `_remove_ent`）。**官員護衛俸祿 ×1**＝ `RulesTitle.salary(titles, titleRank)` 一次性加金（唔係「額外月俸」，即時發放）。**朝廷求才**唔消耗/踢走登用緊嘅文官同伴，淨係檢查「而家有冇文官型 (`type=="wen"`) 同伴跟緊」。
  - 驗收：`tests/run_title.gd`（130 項）+ `sh tools/run_tests.sh` 全 PASS
- [x] **S06b 歷史任務其餘 5 條**：孫堅匿璽/張公公謀害何進/黃蓋/曹阿瞞/討伐張角；需要洛陽/零陵等地圖【已決：借用邊境城池做法，跟 chenliu/xiaopei/changsha 一致，唔起完整新州】
  - 完成：地圖前置（洛陽城+皇城井底+程府民房、下邳城+何府、零陵城，接路 陳留郊外↔洛陽/小沛↔下邳/長沙↔零陵，`WORLD_H` 512→640）已喺前一 commit 做埋；本步落 `data/quests.json` 五條 `hist_sunjian_seal`/`hist_zhanggong`/`hist_huanggai`/`hist_caoamang`/`hist_zhangjiao`（歷史任務由 6→11 條）+ `data/quest_npcs.json` 13 個新 NPC（孫文臺/程普/張角/南華小童/南華老仙/張公公/何府守衛/何進/于吉/黃蓋/曹阿嵩/曹阿瞞）+ `data/monsters.json` 6 隻新怪（1087 木乃伊/1088 殭屍＝皇城井底野怪掉玉璽錦囊；1089 程普/1090 何進/1091 黃蓋/1092 張角＝任務專用 PK boss，仿 Step16 胡玉/于毒/丁原做法：`cmd_quest_battle` 召喚、冇重生冇一般掉落）；items.json 加 13 件任務雜物（56490~56502，cat 44）
  - 偏離：**孫堅匿璽**簡化去除雙重結局（原文攻略：接受孫策賞賜=名聲50 完；拒絕=文臺委託函→PK程普=軍刀+政治經驗30）——冇分支選項機制，統一行 PK 程普路線（同其他歷史任務「fight 收尾」慣例一致）；**張公公謀害何進**guide 原文「發生地點」寫錯（複製咗上一條嘅「汝南城內、丁刺史府」），改跟流程文字用返「下邳城/何府」；**討伐張角**guide 原文仲要求「採藥等級10+」——`RulesQuest.pre` 冇採藥呢類工作技能門檻（淨支持 str/agi/int/spi/pol/cha 六屬性），淨保留 武功20+/魅力10+/政治10+；南華老仙攻略「太平天文書或太平地理書二選一」簡化做固定畀太平天文書（56027）
  - 新地圖 NPC 座標行得性由 `run_maps.gd` 驗證（張角/黃蓋/曹阿嵩座標一開始揀咗牆身格，改用地圖內部通道格後 PASS）
  - 驗收：`tests/run_hist.gd`（12 條歷史任務）+ `run_monsters.gd`（CUSTOM_DROPS 白名單 +6、總數 86→92）+ `run_maps.gd`（NPC 行得性）；`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [x] **S06c 團體任務 16 項**：要「所屬義勇軍」→ 依賴 S08；呢步先做任務資料 + 非義勇軍版可接嘅（紫虛上人等），其餘掛鈎 S08
  - 完成：`data/quests.json` 新增 17 條 `type:group`（16 條 `pre.militia=true` 義勇軍限定：商會長經濟交流/居民除害猛獸王/衛茲資助軍備/礦工工頭/朝廷除害·滅鼠·滅賊/林員外喜宴/勇闖賊寨/鬼域迷陣/岩山瘴林/義勇士兵增兵/亂數迷宮/斬殺惡頭/初階御賜工具/工匠工頭；+ `group_zixu` 紫虛上人非義勇軍版）；`rules/quest.gd` `pre_ok` 加 `pre.militia` 檢查（`ch.militia.founded`）；`data/quest_npcs.json` 加 18 個 NPC（5 城/野外 + 7 個 questOnly boss 目標）；`data/monsters.json` 加 7 隻任務 boss 1093~1099（`cmd_quest_battle` 召喚、無一般掉落，仿 Step16 胡玉/于毒做法）；`data/items.json` 加 2 件任務雜物 56503 商會令牌 / 56504 白玉飾品（cat 44，唔賣得）；`tests/run_group.gd`（89 項，接入 `run_tests.sh`）；`run_monsters.gd` CUSTOM_DROPS 白名單 +7、總數 92→99
  - 掛鈎：義勇軍成立/militia 旗由 S08e `set`，任務實際運作/每月重複/功績評估 → S08f（見 §4）；`group_imperial_tool` 嘅「初階御賜工具」就係 S05b 延後嘅工具正式來源，但仍要 militia，待 S08f 先玩到
  - 偏離：spec 06 §6「16 項」實際列咗 17 項目標（朝廷除害/滅鼠/滅賊分開算），照攻略 sy3_4 全部 17 條實裝；居民除害 Part1/2 任務合併為一條；鬼域迷陣/亂數迷宮嘅「每月 16~21 日 / 10~15 日 NPC 現身」日窗口、以及紫虛上人「每日 1 次」重複機制，暫未做（NPC 常駐，日窗口 → S08f 做法令/日程時一齊接）
  - 驗收：`tests/run_group.gd`（89 項）+ `run_monsters.gd`（白名單 99）+ `run_maps.gd`（NPC 行得性）；`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [x] **S06d 其他職絕招任務鏈**：各職一~三招（15 條）+ 四~六招（排後，涉及多城）；義士二/三招要晉陽/河內/桂陽【待決：地點】
  - 完成：`data/quests.json` 新增 15 條 `type:ultimate`（仕女 虎嘯龍吟/金環裂地/鏡花水月、道士 虛無飄渺/如幻似真/神遊太虛、巫女 殘燈映紅/膽顫心驚/鬼哭神號、辯士 天道循環/吐火羅語/三分天下、美女 笑撥弦步/松竹聽雨/飛花點翠），giver = 各職許昌導師（黃師姐/玄真道人/巫姬婆/蔡師傅/夢韶華），pre 職業 + minLevel(20/30~33/42~45) + `questDone` 招數鏈；`data/ultimates.json` 15 招 `quest` 欄由空填返對應任務 id；`data/quest_npcs.json` 加 6 個 questOnly 戰鬥觸發 NPC（透光石柱/惡狼團頭目/雙風黑殺手/怪人張得/怪人紅菁/狼懿頭目，借汝南洞窟 5/8 層 + 荊州/長沙）；`data/monsters.json` 加 5 隻絕招 boss 1100~1104（骷髏王/張得/狼懿/紅菁/雙風黑殺手，`cmd_quest_battle` 召喚、無一般掉落）；`tests/run_ult.gd`（125 項，接入 `run_tests.sh`）；`run_monsters.gd` CUSTOM_DROPS 白名單 +5、總數 99→104
  - 用現成 58001~58055 原版任務道具 + 25098/25100~25124 原料（item 層早已由原版表導入，唔使新增 item）；招數探集/戰鬥流程跟攻略 sy3_6_1~3，中途 NPC（陳靈/黃大/文成/紫臣/道雲…）簡化併入導師對話（同義士三招 Step 10 慣例一致）
  - 偏離：【待決：地點】——義士二/三招原文晉陽/河內/桂陽（+ 濮陽/譙城/洛陽橋/武陵/零陵等）全屬豫荊以外，**唔新開地圖**，一律搬去現有豫荊地圖（潁川郊外/許昌/汝南洞窟/荊州/長沙）做法同 Step 10 義士三招一致（見 §4）；採集道具沿用原版 quest item 但部分冇對應怪物掉落（同義士力拔山河千年礦石一樣），暫靠合成/市場（遊戲性掉落掛鉤留後續）；四~六招（涉及四季戒/七星石多城）照樣排後
  - 驗收：`tests/run_ult.gd`（125 項）+ `run_monsters.gd`（白名單 104）+ `run_quest.gd` schema；`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [x] **S06e 專長任務**：天文/地理認證 1~4 級（接 S01c）；國戰專長 → S10
  - 完成：`data/quests.json` 新增 8 條 `type:expert`（一級 `expert_tianwen_1`/`expert_dili_1` 甘德：天文交《甘石星經》56045（喬玄）、地理打「地理圖守護者」得四張地理圖 56066~56069；二級 `expert_tianwen_2`/`expert_dili_2` 南華老仙收彩虹鑽石 25011；三四級 `expert_tianwen_3/4` 左慈收水/風屬性石 32001~32030 各 10 粒 + 生之石 32306、`expert_dili_3/4` 于吉收火/地屬性石 + 生之石）；`rules/quest.gd` 加 `pre.classAny`/`pre.expert`/`pre.expertAny`/`pre.hasItemAny`、`reward.expert {skill,level}` 認證（`RulesExpert.certify` 直接升到指定級、封頂職業上限）、stage `getItems` 一次派多件、schema 驗證；`data/quest_npcs.json` +5 NPC（甘德長沙/南華老仙洛陽水池/喬玄·地理圖守護者汝南洞窟三層/左慈襄陽）；`data/monsters.json` +boss 1105 地理圖守護者；`tests/run_expert.gd`（79 項，接入 `run_tests.sh`）；`run_monsters.gd` 白名單 104→105
  - 偏離/【待決：地點】：原作襄平（左慈）/北平（于吉）/廬江（南華老仙）/江夏山洞（甘德一級洞）/小沛八卦台 全屬豫荊以外 → **唔新開地圖**，搬去現有豫荊地圖（長沙/洛陽/汝南洞窟/襄陽），做法同 S06d/Step 10 一致（見 §4）；于吉沿用長沙城現有 NPC；「祈雨救蒼生」任務未實裝，一級前置淨用 `hist_zhangjiao` 完成 + 太平天文書/地理書（hasItemAny，兩者任一）；左慈渾天儀任務（狐狸皮×5 → 渾天儀 26029）留後續批次（見 §4），渾天儀來源仍掛 S11
  - 驗收：`tests/run_expert.gd`（79 項）+ `run_monsters.gd`（白名單 105）+ `run_quest.gd`/`run_maps.gd` schema/NPC 行得性；`sh tools/run_tests.sh` 全 PASS（ALL OK）
- [ ] 結婚 → 放 S09（對象 = 武將）
- UI：記事分類頁（新手/官令/歷史/團體/絕招/戰役/專長）
- 驗收：`tests/run_quest.gd`/`run_hist.gd` 擴充

### S07 座騎戰騎（spec 07）
- [x] **S07a 座騎 UI 補齊**：改名輸入框、繁衍頁（借種馬/胎教 5 揀 1 跑馬燈/懶人/接生/積點分配/待領小馬）、馬戰頁（買兵器/師傅學特技/HUD 特技掣）
  - **邏輯部分早已完成**（唔喺呢個 relay）：改名/繁衍/馬戰 rules+sim 屬 Step 17a/17b（`rules/mount.gd`/`mount_battle.gd`、`sim/sim_mount.gd`、`data/mounts.json`/`mount_weapons.json`），`tests/run_mount.gd` 217 項已覆蓋（改名 trim 8 字、種馬借用/胎教下注/懶人/接生/積點分配/待領小馬、馬戰兵器/特技 9 招/騎乘出手）。leg 5 只「核實 spec vs 代碼」→ 無新邏輯缺口。
  - **偏離**：S07a 喺 PLAN 原文係 UI 工作；本 relay 只做邏輯層，UI（改名輸入框/繁衍頁/馬戰頁/HUD 特技掣）延後，記入 CLAUDE.md「已知 UI 欠債」。
  - 驗收：`tests/run_mount.gd` 217 項（PASS）
- [x] **S07b 戰騎 sim 整合**：獲得途徑【待決，攻略：捕獲/任務/商店？】、最多 3 隻、出戰跟隨 + 自動攻擊、吸 exp 升級、戰鬥特技出手、死亡忠誠 −1/走佬、寄馬廄
  - 完成：新繼承層 `sim/sim_war_beast.gd`（夾喺 sim_mount 同 sim 之間）：`ch.warBeasts`（最多 `maxOwned`=3）+ `beastSeq`；出戰戰騎 = kind `beast` 實體（`owner`/`uid`），跟主人跨圖（`_route_to_map`）、幫主人打/護主/自行搵附近怪（`_think_beast`）；`rules/war_beast.gd` 加 `stats_for`（四維→HP/MP/攻/防/術攻防/命中/迴避/SP/攻速；passive 特技加成）、`exp_share`、`pick_skill`（血少優先補血，否則揀數值最高嘅主動傷害招）；`data/war_beasts.json` 加 `stats`/`beastExpShare`/各品種 `price`。指令：`cmd_beast_adopt/deploy/rename/point/train/friend_train/sell` + `beast_view`；主人（或同伴/戰騎）殺怪 → 出戰戰騎吸 `base_exp × beastExpShare`（`sim_combat._kill_mob` 經 `_beast_on_mob_kill` hook）；死亡 → `RulesWarBeast.on_death` 忠誠 −1 + 送返馬廄，忠誠 0 = 走佬消失。
  - **偏離／【待決：獲得途徑】處理**：原版捕獲/任務/商店【待決】→ 推薦方針「馬廄『戰騎馴養』買幼獸（按品種價）+ 每隻出戰」先做；原版捕獲、NPC 拍賣場（隨機上架）留 S07d；怪物掉落唔做（避免改生成檔）。戰鬥特技 buff/debuff 效果【自訂簡化，同馬戰特技做法】：只映射 atk→「強力」/def→「護甲」狀態，其餘 stat（spellAtk/lifesteal/mpRegen）**leg 6 已接**（見 S07c）。PK（戰騎打戰騎）單機冇對手，唔做。只做邏輯，戰騎面板 + 掣未有（UI 欠債）。
  - 驗收：`tests/run_war_beast.gd` 100→145 項；`sh tools/run_tests.sh` ALL OK（mount 217、war_beast 145、hud 4195、uitest 129、導入器 --check 全過）
- [x] **S07c 友好特技效果接系統**：導航/天眼/撿寶（接 S04a）/幸運護身還魂（接 S03c）/金剛守護/聖體（×2 回復，接 S01a）/背負/神奇（錢莊）/玄妙（驛站）等
  - 完成：`rules/war_beast.gd` 加 `active_effects`/`has_effect`（friendSkills learned flag → effect id 集，跨品種學都算）+ `bag_cap_mult`/`regen_mult`；`data/war_beasts.json` 加 `friendEffects`（`autoLootRange`/`bagCapacityPct`/`regenMult`）。sim hook（`sim_core`）：`_friend_effect_active`/`_friend_regen_mult`/`_bag_cap`，由 `sim_war_beast` 按出戰戰騎覆寫。
  - 接落去嘅系統：**撿寶**（`_beast_auto_loot` 喺 `_beast_tick` 自動執主人附近掉落物，受負重上限限制）接 S04a；**幸運/護身/還魂**（`sim_combat._kill_player` 三個死亡道具效果，友好技生效就唔消耗道具）接 S03c；**聖體**（`sim.gd._safe_regen_tick` 回復 ×2）接 S01a；**金剛/守護**（`_apply_friend_passives` 常駐 armor1/mirror1）接 spec 02 §7 狀態；**背負**（`_bag_cap` ×1.5，`sim_combat.cmd_pick` 用）；**神奇**（`sim_econ` 存/攞倉庫免訂閱天地商行）【待決：錢莊介面 → 單機化 = 天地商行倉庫】；**玄妙**（`sim_station` 唔喺驛站都用得到，車費由所在地圖起計）；**導航/天眼**（read-model `beast_view.effects`，等 UI 用）。
  - **同時清 S07b 遺留**：戰鬥特技 buff/debuff 其餘 stat 下游 — beast 自身 buff `spellAtk`（加 mpNuke 傷害）/`lifesteal`（傷害回血）/`mpRegen`（脫戰回魔加成）存 `e.beastBuff`；debuff 對目標存 `t.beastDebuff`，`def`（`_beast_target_def` 降敵物防）/`atk`（`sim_ai` 怪打人降攻）有下游效果；`RulesCombat.debuffed` 純函數。
  - **偏離／【自訂簡化】**：金剛/守護 = 常駐狀態（唔係施放一次）；神奇【待決：錢莊】→ 免訂閱用天地商行倉庫；導航/天眼只出 read-model flag（UI 延後）；debuff 嘅 spellDef/hit/evade 對物理怪冇下游（記 PLAN §4）；聖靈/遁地/奇門/脫出/召喚/神行/回城/火焰/飛影/狂力/開光/忠誠/巨力/穩重/地行/神獸/嗅血/野性/獅魂/王者等其餘友好技效果留後續（記 PLAN §4）。
  - 驗收：`tests/run_war_beast.gd` 145→185 項；`sh tools/run_tests.sh` ALL OK
- [x] **S07d 戰騎面板 + NPC 拍賣場**（馬/戰騎隨機上架）；武將特技 52「馴馬」（處理抽特技打亂問題）
  - 完成（NPC 拍賣場，spec 07 §9）：`sim/sim_war_beast.gd` 加 `auction_view` + `cmd_auction_buy`；`state["auction"] = {day,seq,lots}`（舊存檔自動建）；每 game 日 `_auction_daily` 換貨（`sim.gd` `_daily_hook` 叫），當日貨由**獨立 `SimRng`（`900001 + day*7919`）**驅動 → **唔佔主 rng 流**，不影響戰鬥/掉落決定性。貨 = 隨機座騎（幼/成年、公/母）+ 隨機戰騎（1~15 級，NPC 標等級用 `RulesWarBeast.exp_total`）；價 = 底價 × [0.8, 1.5]。買馬/戰騎都有容量（5 匹 / 3 隻）同金錢檢查，落馬廄；已有出戰戰騎 → 新嗰隻寄馬廄。 `data/war_beasts.json` + `auction` 設定。
  - 完成（武將特技 52「馴馬」+ 抽特技打亂處理）：`general_skills.json` 52 → `impl:true`，`eff: {mountIntimacyMul: 2.0}`；`RulesMount.daily` 加 `intimacy_mul` 參數（只放大正成長）；`sim_mount._mount_intimacy_mult` 由同伴特技畀值。**打亂處理**：`RulesGeneral.skill_for` 加 `draw_pool`/`pin` 參數，抽技池改由 `general_skills.json cfg.drawPool` **明確釘死**（wu 12 / wen 11，唔再跟 `impl` flag 浮動）→ 日後開新特技唔會改動其他武將抽到嘅特技；新特技經 `cfg.pin` 指派（馬超/馬岱/公孫瓚/馬騰 = 馴馬）。`GameData` 加 `gen_draw_pool`/`gen_skill_pin`。
  - **偏離／【自訂簡化】**：戰騎面板（馴養/出戰/訓練/友好/賣掣）屬 UI → 延後，但 `beast_view` read-model 早已備（S07b）；拍賣場寄喺**馬廄**（唔另起設施/改地圖）【自訂】；「玩家疲勞放牧都會執到」【自訂簡化】併入放牧 loot，唔另做；拍賣只做「NPC 上架→玩家買」，玩家賣出沿用 `cmd_beast_sell`/`cmd_mount_abandon`（唔另做寄賣）。
  - 驗收：`tests/run_war_beast.gd` 185→207（拍賣生成/決定性/買馬戰騎/容量/金錢/存檔 roundtrip/舊存檔）+ `tests/run_general.gd` 127→138（固定池/pin/馴馬 eff + sim 層親密度 ×2）+ `tests/run_mount.gd` 217→219（`intimacy_mul` 只放大正成長）；`sh tools/run_tests.sh` ALL OK。
- 驗收：`tests/run_mount.gd`/`run_war_beast.gd` 擴充（**UI 驗收 `--uitest` 繁衍/馬戰/戰騎延後**，本 relay 只做邏輯層）

### S08 名聲 / 義勇軍（spec 08）— 最大，拆細
- [x] **S08a 義舉證明 + 城池進貢**：朝廷官員（許昌）四類 20 項物品；進貢 = 城好感
  - 完成：`data/office.json` +`merit`（許昌朝廷官 `imperialOffice:donate_xc` + 四類 20 項：為民除害 5 / 機密情報 5 / 古董軍備 5 / 特殊收藏品 5，逐項 `reqRank` 照攻略 sy2_8_3 頭銜表 + 固定 `fame`【自訂】）+`tribute`（`favorCap:100`、`unitsPerFavor/unitsPerFame:100`）；新 `rules/merit.gd`（`item_def`/`block`/`fame_of`/`favor_gain`/`tribute_fame`/`favor_cap` 純函數）；`sim/sim_office.gd` +`merit_list`/`cmd_merit_turnin`/`city_favor`/`city_favor_view`/`cmd_city_tribute`（`_facility_city_id` 用設施 `map` 對 world city）；`ch.cityFavor = {cityId: n}`（舊存檔自動 0）；測試 `tests/run_title.gd` 130→149（義舉資料/規則/繳交）+ 新 `tests/run_militia.gd` 24 項（進貢/好感/封頂/存檔 roundtrip/舊存檔/決定性）
  - 【自訂】名聲值：攻略只列物品/頭銜需求，冇名聲數字 → 按階梯訂 5~120（見 office.json）。進貢好感 = 捐獻單位×0.01（spec 句「物資價值×0.01」以捐獻單位做價值），名聲同率（unitsPerFame=100）；進貢唔扣行動力（跟 spec）。城池好感下游效果（居民/NPC/登用/任務）留 S08b/S09。
  - 偏離：朝廷官員唔另起 NPC/設施 → 沿用許昌官宅 (`donate_xc` 已有 `office:true`)。城池好感只有 `world.json cities` 嘅 3 城（許昌/襄陽/新野）；襄陽冇捐獻處暫時進貢唔到。
- [x] **S08b 城池屬性 + 官宅內政 6 種**：`world.json cities[].attrs`（8 項 0~100）→ 天災/市場/商店/防禦連動；內政工作 + 專長 exp（清 S01c 延後）+ 武將政治協助（接 S09）
  - 完成：`world.json` +`cities[].attrs`（8 項，`fangzai` 初值 = 舊 `defense` 保兼容；其餘 = 50）+`cityAttrs`（`default/per/order/names/prodCats/shopGoods/guardAttr/crimeAttr`）；新 `rules/city.gd`（`init_attrs`/`attr_of`/`prod_mult`/`disaster_mitigation`/`shop_extra_items`/`guard_warn_ticks`/`crime_mult`/`attr_gain` 純函數）；城池屬性真值存 `state.cityAttrs`（官宅內政會改，存檔 roundtrip + 舊存檔 `_ensure_city_attrs` 補初值）；`rules/market.gd`（`daily` +可選 `attr_cfg` → 開墾/商業/畜牧/礦產 影響 prod；`supply_mods` 防災改用 `attrs.fangzai`，冇 attrs fallback 舊 `defense`）；`sim.gd`（`_market_daily` 傳合併 attrs 嘅 city；`_city_guard_check` 防禦 → 衛兵間隔）；`sim_core.gd`（`city_attrs`/`city_attrs_set`/`_city_with_attrs` 讀寫 + `add_bots` 治安 → 犯案率）；`sim_econ.gd`（`shop_sells`：鑄造 ≥ min → 商店多賣 `shopGoods`）；`data/office.json` +`domestic`（6 工：墾荒種地/商業開發/照顧牲畜/探索礦能/增強防禦/技術開發，`baseGain:2`/`expertExp:3`/`minTitleRank:1`）；`sim_office.gd` +`domestic_def`/`domestic_block`/`domestic_view`/`cmd_domestic`（官宅做，扣行動力 = 官令價，城池 attr +`RulesExpert.domestic_mult(專長lv)`、專長 exp，封頂 100）；`sim_core.gd` +`_domestic_assist_bonus` hook（0.0，S09c override）；測試 `tests/run_militia.gd` 24→73（資料/規則/內政執行/專長增量/4 連動/存檔 roundtrip/舊存檔/決定性）
  - 【自訂】屬性初值全 50（`fangzai` = 舊 defense 50/45/30）→ 開局零行為改變；連動 shape：prod `1+(attr−50)×0.006`、防禦/治安 `1.5−attr/100`、鑄造門檻 60 多 4 件貨（10037/10044/11002/11044）。需有官身（頭銜 ≥1 階）【原 sy2_8_8「需有身份」】。內政扣行動力 = `_office_ap_cost`（武將協助 S09c 可減）。
  - 偏離：`sy2_8_8` 商業/礦產官令名採用「商業開發/探索礦能」（非 spec §3 表嘅「商業開業/探索礦產」）。防禦 attr 下游（城牆/攻城）未有系統 → 記 §4 留 S10；治安/防災 attr 只可由義勇軍工作/救災提升（S08f/S08c）。
- [x] **S08c 救災**：公佈欄設施、救災官令、救災物品 7 種、救災區 N 次工作、覆命（名聲 +10/政治 exp/專長）
  - 完成：`data/world.json` 天災 7 種各加 `reliefItem`（蝗蟲 26022 農藥／瘟疫 26023 補藥／旱災 26024 水桶／颶風 26025 榔頭／洪水 26026 青泥／暴風雪 26027 鏟子／地震 26028 地動儀，全用 items.json 原有檔）；`data/office.json` +`relief`（`minTitleRank:0`/`spCost:10`/`fame:10`/`polExp:20`/`expert:jiuzai`/`expertExp:12`/`workPerSize` 大 30 中 20 細 10【自訂】）；`data/facilities.json` +3 城門 `bulletin` 公佈欄（許昌 37,49／新野 33,45／襄陽 39,57）+3 腹地 `relief` 救災區（許昌→`field_1` 104,10／新野→`bowang` 62,10／襄陽→`longzhong` 38,10）；`data/shops.json` 3 間工具店 +7 種救災物品。`rules/disaster.gd` +`relief_item_of`/`relief_items`/`relief_need`/`relief_weaken`（天災 supply factor 由 `baseSupply` 向 1.0 靠，令市場影響遞減）；`roll_day` +`baseSupply`（原值備份）。`sim_office.gd` +`relief_cfg`/`_active_disaster`/`bulletin_near`/`relief_near`/`bulletin_view`/`relief_block`/`relief_view`/`cmd_office_relief`/`cmd_relief_work`/`_relief_reward`，`order_text`/`cmd_office_turnin` 加 relief 專屬流程。`sim_econ.gd` `_shop_shutdown_reason` 豁免救災物品（天災期間照買得到）。清 S01c 延後：`RulesExpert.relief_mult` 已備但今次 spec 未用（見偏離）。測試 `tests/run_militia.gd` 73→131（資料/規則/公佈欄/流程/停進貨豁免/存檔 roundtrip/舊存檔/決定性）。
  - 【自訂】次數 小 10／中 20／大 30；名聲 +10【原】、政治 exp 20、救災專長 exp 12；行動力 −10【原】喺**接令時**扣（同其他官令一致）；每次工作扣 SP 10 + 用 1 份對應物品。救災官令共用 `ch.office.order`（每日 1 條），動態綁 `{city, disaster, need, done}`，唔入 `office.orders` 表。
  - 偏離：原作單一「腹地東北」救災區 → 【待決→推薦方針】每城各一個腹地救災區（許昌/新野/襄陽），唔新開地圖。spec §6「多人救災加快（武將同伴助攻）」未接 → §4 留 S09c。`RulesExpert.relief_mult` 未有下游（spec §6 只寫「增加救災專長」，冇寫倍率效果）→ §4 記 S08f/S09 需要時接。
- [x] **S08d 名額競爭**【待決：簡化方案】
  - 完成（spec 08 §2 / 攻略 sy2_8_3）：`data/office.json` +`competition`（`enabled`/`minRank:1`/`competitors:3`/`npcLo:0.85`/`npcHi:1.05`/`defenderBonus:0`）；`rules/title.gd` +`comp_cfg`/`comp_score`（= 名聲 + defenderBonus）/`npc_score`（該階名聲需求 × [npcLo,npcHi] 隨機）/`defend_ok`（≥ 全部挑戰者最高分）純函數；`sim/sim_office.gd` +`competition_cfg`/`title_competing`/`_title_contest_daily`/`_title_contest`/`title_contest_view`。每月初一（`sim.gd _daily_hook` 喺 `_salary_daily` 之後叫）對有 `ch.titleCompete` 嘅頭銜做守位考驗：3 NPC 挑戰者分數用**獨立 SimRng**（`800001 + day*3181 + rank*101`，唔佔主 rng 流），玩家 ≥ 全部 → 守位成功，否則 `titleRank -= 1`（跌返上一階）+ 發 `title_contest` 事件/訊息。`cmd_claim_title` 成功後設 `ch.titleCompete = true` 入競爭系統。
  - **偏離／【待決→推薦方針】**：原版「玩家之間每月競爭」→ 單機化 = 3 個 NPC 挑戰者模擬，競爭方式由「武將 PK（弱化版）」**再簡化為「比名望」**（spec 講「武將 PK」，但單機冇其他玩家；用名聲分數比併最簡單可測、唔郁戰鬥系統）。只對經官宅朝廷討取得嚟嘅頭銜生效（`titleCompete` 旗標）；舊存檔／直接設 `titleRank` 唔競爭（保兼容）。守位失敗跌一階而唔清空（spec【自訂】「跌返上一階」）；名聲唔下降（spec §1）。
  - 驗收：`tests/run_militia.gd` 131→158（資料/規則邊界/討取入系統/必贏必輸守位/月中唔考驗/舊存檔兼容/存檔 roundtrip/決定性）；`sh tools/run_tests.sh` ALL OK。
- [x] **S08e 義勇軍成立**：條件 4 項（擁護 NPC 數【自訂】、20 萬、定居非新手城 → 要「定居」功能）；品階/帶兵量公式（`titles.json soldiers`）
  - 完成（spec 08 §4~§5 / 攻略 sy2_8_2、sy2_9_19）：`tools/gen_titles.py` 由 `docs/guide/sy2_9_19.txt` 解析 60 階「增加兵量」寫入 `titles.json` 每行 `soldiers`（1~20 階 +200/階、21~40 +250/階、41~50 +400/階、51~60 固定 28000；`--check` 加公式核對）＋重跑生成器。`data/office.json` +`militia`（`minTitleRank:6`/`minFame:3000`/`supporterNeed:10`/`supporterLv:5`/`supporterFavor:50`/`fund:200000`/`minLv:5`/`capRank:51`/`capSoldiers:28000`/`newbieCities:[xuchang,xiangyang,xinye]`/`grades` 一品 8000~八品 1000）。新 `rules/militia.gd`（`cfg`/`grade_soldiers`/`grade_name`/`title_soldiers`/`max_soldiers`/`is_newbie`/`settle_block`/`invite_block`/`name_block`/`found_block` 純函數）。`sim/sim_office.gd` +`militia_cfg`/`_militia_of`/`city_at`/`_settle_cities`/`settle_view`/`cmd_settle`/`home_city`/`cmd_militia_invite`/`cmd_militia_found`/`militia_view`。`ch.homeCity` = 定居城池（新增，pre 條件之一）；`ch.militia = {founded,name,password,city,grade,supporters,foundedDay}`（成立後 `founded:true`，自動清 S06c `rules/quest.gd` `pre.militia` 前置）。定居用現有 `maps.json kind:city` 城池（10 個，唔新開地圖），要企喺目標城池入面先定居得。測試 `tests/run_militia.gd` 158→232（資料/帶兵量例題/成立 4 條件/定居流程/遊說擁護者/成立流程/`pre.militia` 掛鈎/存檔 roundtrip/舊存檔/決定性）。
  - 【自訂】擁護者門檻 = 10 人 + 居民好感 ≥50（居民冇名聲機制，改用好感；spec §4 註明「隨想簡化: 10 個都得」）；擁護者以快照存 `ch.militia.supporters`（居民走咗/死咗都算）。名號唯一單機冇從驗證 → 只驗非空 + 長度 ≤12。定居唔另收費。新手城 = 許昌/襄陽/新野（spec【原 許昌襄陽洛陽 → 換新野】）。
  - 偏離：原版「25 人擁護 + 每人名聲 100」→ 單機化 10 人 + 好感 50【自訂】。原版成立喺【團】→【起義】面板（UI 延後）→ sim 層 = `cmd_militia_found`。定居唔新開地圖／唔加設施，直接用現有城池座標（spec 12 慣例：其他數據寫座標，GameData 載入轉全域）。
  - 驗收：`tests/run_militia.gd` 158→232；`sh tools/run_tests.sh` ALL OK（尾行 `ALL OK`，uitest 無 flake）。
- [x] **S08f 營地 + 義勇軍工作 22 項 + 評定會議**：`data/camp.json`、監督建設、功績表；團體任務接軌（清 S06c 延後）
  - 完成（spec 08 §7~§8 / 攻略 sy2_8_5、sy2_8_6、sy2_8_8）：`data/camp.json` 10 設施（初始級/基本材料/設施 store 上限表/規模→工作指派份數 50→100/規模→階級人數上限/4 級典農靈台、5 級司農）+ 22 項工作（內政 10、軍事 3、軍備 9）+ 評定指派 3 類（捐獻/監督/商情）+ 績效→功績對照表 14 段【原】。新 `rules/camp.gd`（`upgrade_cost` = 基本×目標級數、`supervise_points` = 0.5 + 政治×0.01 + 木匠 lv×0.02 + 身份加成、`work_cap`/`grade_limit`/`facility_cap`/`positions_at`）；新 `rules/militia_work.gd`（22 工作定義、有/無城池過濾、指派類別、`merit_delta`、`performance_gain`）。`sim/sim_office.gd` +`camp_view`/`cmd_camp_upgrade`/`cmd_camp_supervise`/`militia_work_view`/`cmd_militia_work`/`eval_view`/`cmd_eval_assign`/`cmd_eval_meeting`/`_eval_daily`/`_on_militia_quest_done`/`_militia_quest_reset`；`sim.gd` `_daily_hook` 加每月初一結算 + 重複任務清零。團體任務接軌：`data/quests.json` 16 條義勇軍 group 任務 +`repeat:monthly`（`group_zixu` daily）、`data/quest_npcs.json` `shenjing_lao`/`luopo_lao` +`dayWindow`（16~21 / 10~15 日）、`rules/quest.gd` `npc_visible`/`npc_shown` 加 `day` 參數 + `day_in_window`、完成 group 任務 → 義勇軍績效 +30。
  - 偏離【自訂】/【待決→推薦方針】：原作「杉竹 / 白石礦石」items.json 冇 → 用現有最接近資源（杉竹→箭竹 25054、白石礦石→石頭 25001）。營地指令唔要求實體座標，用「根據地城池」代表（`city_at(e) == m.city`），唔另加地圖設施。單機玩家固定頭目身份（`m.role="banner"`）；「有城池」= `m.hasCity` 旗（佔城系統 S10 前 false → 淨得監督/商情）。監督完成度目標 100【自訂】。軍備/捐獻轉換率、每工作績效值皆【自訂】（spec 只寫影響方向）。徵兵/軍馬為 store 加減，兵種/戰場留 S10。商情情報值 0~100 下游（睇商店/武將情報 85/80 門檻）留 S09/S10。
  - 驗收：新 `tests/run_camp.gd` 132 項（資料/純函數/升級監督/22 工作/專長/評定會議/月初結算/團體任務績效/每月每日重複/日窗口/存檔 roundtrip+舊存檔/決定性）；`sh tools/run_tests.sh` 全 PASS（尾行 `ALL OK`）。
- [x] **S08g 民心 + 法令**（要有城池先啟動 → 佔城系統 S10 未有）：先做資料 + 規則 + 測試。`world.json` +`cityMorale`（初始 100/cap/`taxDrop` 高稅 −4/`famePerMorale`/`monthlyGainCap`/`popLossRate`/`recruitFloor`）+`cityLaw`（行動力 100/每月 1 次/6 條法令）；新 `rules/civic.gd`（民心 clamp/tax_drop/morale_gain/prod_mult/pop_after/recruit_mult + 法令 default/change_block/ap_cost）；`sim_core` `state["cityGov"]`+`state["cityPop"]` + `city_gov_active`/`city_gov_init`/`city_morale`/`law_allows`/`city_pop`/`city_id_at`/`civic_fame_gain`；`sim_office` `_morale_daily`（每月初一評比：高稅 −4 + 人口流失 + 月度增益歸零）/`city_gov_view`/`cmd_city_tax`/`cmd_city_law`；連動：`RulesMarket` prod × 民心/100（`sim.gd _market_daily`）、動態人口入市場、徵兵 ×`recruit_mult`、救災/捐贈官令 +民心（每 10 名聲 +0.1，上限 +10/月）、`crafts` 法令 → 大宗師閘、`guard` 法令 → 城門衛兵閘、`cityDrop` 法令 → 新 `cmd_drop_item`；新 `tests/run_civic.gd` 87 項
- UI：官宅面板分頁（頭銜/官令/內政/救災/義舉）、義勇軍面板、營地面板、公佈欄、城池民心/法令面板
- 驗收：`tests/run_title.gd` 擴充 + `tests/run_militia.gd`（新）+ `tests/run_civic.gd`（新）

### S09 登用武將 / NPC / LLM（spec 09）
- [x] **S09a 居民化**：`data/residents.json`（性格/日程/role），bot → 居民；每城 12~20 人
  - 完成：新 `data/residents.json`（cfg 人數/性格 5 維/理念/日程 12 時辰 + 5 role 權重 + 10 城 homeZone + 姓氏/名字池）；新 `rules/resident.gd`（`role_def`/`role_total`/`pick_role`/`personality`/`city_count`/`activity_at`/`home_zone`/`make_name` 純函數）；`GameData` +`residents`；`sim_core.gd` +`add_residents()`（每張 kind:city 地圖生 12~20 人，大城多）/+`resident_inn_pos()`/`_spawn_actor` +`spawn_range`；`BotSys.init_resident`（派 role/性格/理念/善惡/homeCity/homeZone/mem）+ `think` 用 `ch.homeZone`（居民行自己城最近野區，低血返自己城客棧）；`view_ents` +`resident`/`role`；`sim.resident_view()` read-model（role/性格/理念/當前時辰活動）；`ui/main.gd` 開場改 `add_residents()`；新 `tests/run_residents.gd` 83 項接入 `run_tests.sh`；`sh tools/run_tests.sh` **ALL OK**。
  - 偏離【自訂】/【待決→推薦方針】：人數公式 = `round(pop/popPerResident=30)` 夾 12~20（許昌 800→20、襄陽 700→20、新野 450→15、邊城 350→12），攻略只寫「每城 12~20，大城多」冇公式。居民善惡 = `align:"good"`（spec「正 300+ 檔」用 role 欄表示，唔硬改 karma 免影響 S03a）。日程 12 時辰（子..亥）→ sleep/work/eat/home；**S09a 只做資料 + read-model，日程驅動行動留 S09b**（§4）。legacy `add_bots(n)` 保留（測試用，行為不變，唔設 resident flag）。homeZone 由 portal BFS 揀最近 field（xuchang→field_1 等）；洛陽/長沙/小沛/下邳/零陵冇客棧 → 低血唔撤退。
- [x] **S09b 傳聞擴散 + 忠誠事件**：跨城延遲 1~3 日；殺善 NPC → 義理武將忠誠 −15 等
  - 完成：新 `rules/rumor.gd`（`cfg`/`cap`/`mem_cap`/`rumor_kind_of`（kindMap：murder 負→killer / 正→bounty）/`rumor_key`/`make_rumor`/`delay`/`delay_min|max`/`reaches` 純函數）；`rules/npc_memory.gd` +`rumors` 欄 + `ensure`/`add_rumor`（同 key 覆蓋、超 cap 擠最舊）/`has_rumor`/`rumor_of`/`rumor_count`/`rumor_keys`；`data/residents.json` cfg +`rumor`（cap 16/memCap 8/minWeight 3/kindMap/delayMin 1/delayMax 3）。`sim_core.gd`：`state` +`rumors`/`rumorSeq`；`_witness_nearby` 顯著事件 → `_seed_rumor`（起源城即日揭示；其餘城用**獨立 SimRng**（`910000+seq*7919`）抽 1~3 日延遲，唔佔主 rng）；`_rumor_daily(day)` 每日反思批次（已揭示城持續注入居民記憶表、到期城揭示 + emit `rumor_spread`）；`rumor_view(city)`/`known_rumors(id)` read-model；`sim.gd _daily_hook` +`_rumor_daily`、`load_string` +`_ensure_rumors`。`sim_recruit.gd` 覆寫 `_kill_bot`：玩家**先行出手**謀殺善 NPC（非紅名/非自衛）→ 義理念同伴忠誠 −15（`generals.json` cfg.loyalty +`badNpcKill:-15`/`badNpcKillIdeo:["義理"]`，經 `tools/gen_generals.py` 生成）；忠誠 0~100/<30 子時走/=0 即走 沿用現有；新 `tests/run_rumor.gd` 54 項接入 `run_tests.sh`；`sh tools/run_tests.sh` **ALL OK**（尾行 `ALL OK`、uitest 129、hud 4195，未見 flake）。
  - 偏離【自訂】/【待決→推薦方針】：spec 只寫「延遲 1~3 game 日」冇具體機制 → 單機化 = 城級傳聞池（`state["rumors"]`）+ 起源城即日揭示 + 其餘 9 城各自抽 1~3 日延遲，每日反思批次注入該城全部居民記憶表（唔逐個 NPC 兩兩交換 —— 用城級池做等價可觀察效果，測試證 A 城殺人魔傳到 B 城）。目擊者本身即時記入記憶表；`kindMap` 只認 murder（負=殺人魔 killer、正=除害 bounty），greet/die 唔傳。忠誠 −15 只計「玩家先行出手」（自衛反殺/殺紅名/其他理念唔扣），並照 Step 15「忠義」特技忠誠跌減半。日程驅動行動、role work 下游仍留後續（§4）。
- [x] **S09c 其餘特技**（主動/生產；國戰類 → S10）+ 內政協助
  - **S09c-b 主動特技 21/22/32/38（leg 18，完）**：`general_skills.json` 21/22/32/38 `impl:true`/`eff`（21 `{active:burrow,cd:0}` 無限遁地、32 `{active:taunt,tauntRange:6,cd:600}` 挑釁、38 `{active:heal,healPct:0.3,cd:1200}` 急救、22 `{classSkillCdMul:0.5,classSkillCostMul:0.5}`）＋ pin（左慈/于吉→21、張郃/魏延/顏良→32、華佗→38）；`rules/general.gd` +`active_kind`/`active_cd`/`active_block`/`heal_amount`/`taunt_range`/`class_skill_mul` 純函數；`sim_recruit.gd` +`cmd_companion_skill(id,kind)`（burrow/taunt/heal）＋ `_comp_burrow`/`_nearest_city_map`/`_city_anchor`/`_comp_taunt`/`_comp_heal` + 覆寫 `_companion_class_skill_mul`；`sim_core.gd` +`_companion_class_skill_mul` 空 hook；`sim_skill.gd` 潛行/透視冷卻 + 超渡消耗 × hook（22）；`tests/run_general.gd` 173→207 項（新 G 群組）；`sh tools/run_tests.sh` **ALL OK**。
  - **S09c-a 完成**（leg 17）：內政/生產/經濟被動特技（39~43、45~51）＋ 內政協助（見下）。
  - 偏離【自訂】/【待決→推薦方針】：攻略只舉 4 個特技例，70 項清單/效果皆【自訂】。**21 無限遁地** 單機化 = 主公+同伴即時傳送去最近 `kind:city` 地圖（map 圖 BFS 最近、地圖中心最近行得格），唔使車費、冇冷卻（「無限」）；用 `cmd_companion_skill(pid,"burrow")`。**32 挑釁** = 同伴同圖 tauntRange 格內可打怪 `mob.state=chase`/`target=同伴`。**38 急救** = 同伴喺 auraRange 內即回主公上限 HP×healPct（滿血唔使）。**22 職業特技** 採【自訂】proximity 被動（同伴同圖 auraRange 內 → 主公職業特技冷卻/消耗乘數 ×0.5），唔另開 `cmd_companion_skill` 種類（同政才/辯才 always-near 一致）；主動技冷卻存 `c["gen"]["activeCd"]`（同伴實體 dict 內，舊存檔 `.get` 兼容）。新特技經 pin 指派（唔入 drawPool）。`44 鑑定`、國戰類 23~37/53~70 → §4/S10。
  - **S09c-a 進度（leg 17，已完）**：內政/生產/經濟被動特技（39~43、45~51）＋ 內政協助（見下）。
  - 完成（S09c-a）：`general_skills.json` +`cfg.assist`（政治 = round(智力×0.5)、加成 = 政治/200 + `domesticAssist`、封頂 1.0）＋ 15 項特技 `impl:true`/`eff`（39~42 內政 `domesticAssist:0.2`、43 商才 `tradeBuyMul:0.95`/`tradeSellMul:1.05`、45~48 生產 `workSkill`+`workExpAdd:0.5`、49~51 `craftSkill`+`craftRateAdd:0.1`）＋ 13 個 pin（諸葛亮/荀攸/張昭/魯肅/田豐/劉曄/于禁/曹洪/韓當/虞翻/顧雍/張紘/樂進）；`rules/general.gd` +`pol_of`/`assist_bonus`/`work_exp_mult`/`craft_rate_add`/`trade_mul`；`sim_core.gd` +`_companion_pol_bonus`/`_work_exp_mult`/`_craft_rate_add`/`_companion_trade_mul` 空 hook；`sim_recruit.gd` 覆寫（由 `ch.recruit.comp` 反向搵同伴，唔限距離）＋ `_comp_of_ch`/`_comp_pol_of_ch` 等；`sim_econ.gd`：`_work_gain` ×`_work_exp_mult`、`cmd_craft` +`_craft_rate_add`、`cmd_buy`/`cmd_sell`/`cmd_storage_sell` ×`_companion_trade_mul`；`sim_office.gd`：官宅內政 +`_domestic_assist_bonus`、營地內政同 +、營地監督政治 +`_companion_pol_bonus`；`tests/run_general.gd` 127→164 項（A 資料 21→33 impl + F 群組 4 個新測試）；`sh tools/run_tests.sh` **ALL OK**。
  - 偏離【自訂】/【待決→推薦方針】（S09c-a）：攻略只舉 4 個特技例，70 項清單同效果皆【自訂】。**武將政治** generals 表冇 → 用智力換算（政治 = round(智力×0.5)，`assist.polPerInt`）。**內政協助** spec 只寫「武將屬性(政治)加入官宅工作/營地監督完成度」→ 同伴政治 always-on（`ch.recruit.comp` 有同伴即計，唔限距離，同政才/辯才一致）；39~42 內政技能一律做泛用 `domesticAssist` 加成（唔逐個 job 對應 —— 城池屬性冇「屯田/治水」job，屯田/治水原本語意係營地糧產/水災，用同一加成代表）。**新特技經 pin 指派**（唔入 drawPool，依 S07d 凍結慣例免得打亂其他武將抽技）。`44 鑑定` 冇鑑定系統 → §4。
- [x] **S09d LLM 層**（原 Step 20）：OpenRouter/JSON schema/白名單；每日反思 + 記憶摘要；Tier1 武將對話；無 key/失敗/預算完 → 模板後備
  - **完成（leg 19）**：新 `data/llm.json`（`endpoint`/`model`/`models`/`temperature`/`maxTokens`/`actions` 7 動作白名單/`tiers` 1=llm・2=mixed 0.15・3=template/`cooldownTicks`/`budget` perDay 40・reflectPerDay 8/`reflect` intervalDays/maxChars/`ideologyStyle` 5 理念/system+reflect prompt/`responseFormat` json_schema）；新 `rules/llm.gd`（`cfg`/`actions`/`has_action`/`tier_mode`/`tier_chance`/`tier_uses_llm`/`cooldown_ticks`/`cooldown_ok`/`roll_day`/`per_day`/`reflect_per_day`/`budget_ok`/`reflect_interval`/`reflect_due`/`prompt_messages`/`request_body`/`build_request`/`build_reflect_request`/`auth_headers`/`parse_response`（剝 code fence、非白名單→ignore、**扔掉所有數值欄**)/`parse_summary`/`effect_of`（唯一數值來源：greet +1，其餘 0)/`affinity_delta`/`template_summary`/`goal_of` 純函數）；新 `sim/npc_brain_llm.gd`（同 `NpcBrain.decide(ctx,pick_idx)` 介面 + `decide_with` 用 LLM 文字、解析唔到 fallback）；新 `sim/llm_client.gd`（`user://llm.cfg` 存 key/model、唔入存檔；`transport` 可注入做 mock；`http_transport(http)` 供 UI 接）；`rules/npc_memory.gd` +`summary`/`goal`/`summaryDay` + `set_summary`/`summary`/`goal`；`sim_core.gd` +LLM 層（`_ensure_llm`/`llm_enabled`/`llm_model`/`cmd_llm_config`/`_llm_ctx`/`_llm_offer`/`_llm_talk`/`cmd_llm_reply`/`cmd_llm_summary`/`llm_view`/`_llm_reflect_daily`；預算/冷卻存 `state.llm`，pending 只喺 instance）；`sim.gd` `_daily_hook` +`_llm_reflect_daily`、`load_string` +`_ensure_llm`；`sim_recruit.cmd_general_talk` +Tier1 LLM 分支、`sim_char._npc_react` +Tier2 偶發 LLM；`game_data.gd` +`llm`；新 `tests/run_llm.gd` **113 項**接入 `run_tests.sh`；`sh tools/run_tests.sh` **ALL OK**。
  - 驗收（spec）：mock 全動作 ✓；無 key 照玩 ✓；LLM 唔改數值（惡意數值欄全被 `parse_response` 丟棄，好感只按 `RulesLlm.effect_of` +1，善惡/錢/血不變）✓；唔碰網絡（mock transport）✓。
  - 偏離／【待決→推薦方針】：sim **唔經網絡**，只發 `llm_request` 事件（規則層砌好 `url`/`headers`(冇 Authorization)/`body`），客戶端送完 call `cmd_llm_reply`/`cmd_llm_summary` 回填；pending 唔入存檔（重載 = 請求當冇，模板後備照玩）。key 只由 `LlmClient` 存本機、sim 只存 `enabled`/`model`（非機密）。Tier1 武將 + Tier2 居民偶發（政策 15%）先接；Tier3 純模板。`acceptQuest` 只出 `llm_action` 標記（未有玩家→NPC 請求系統，下游留後續）；反思摘要/目標只寫 `mem.summary`/`mem.goal`（read-model，未驅動行為）。真 HTTPRequest 接線 + 設定頁/對話顯示 = UI 欠債。
  - 驗收：`tests/run_llm.gd` 113 項（資料/解析丟數值/效果/Tier/預算/冷卻/brain/摘要/請求形狀/client mock/sim 設定/Tier1 對話/回填唔准改數值/每日反思/預算/存檔/舊存檔/決定性）；`sh tools/run_tests.sh` **ALL OK**。
- [x] **S09e 結婚**（spec 06 §9 / 09 §6）：御賜函、喜餅、分餅、禮堂、婚戒召喚、配偶頁、離婚
  - **完成（leg 20）**：新 `data/marry.json`（好感鎖 90/召喚 50 SP/離婚 50 萬兩/婚戒 23030/男 51627 女 51628 御賜函/4 價位喜餅對照 `buy→open→contents`/結婚村 4 NPC id）；新 `rules/marry.gd`（`cfg`/`affinity_lock`/`summon_sp`/`divorce_gold`/`ring_item`/`letter_for`/`gender_of`/`has_letter`/`has_ring`/`cakes`/`cake_by_tier`/`cake_by_buy`/`open_result`/`contents`/`propose_block`/`book_block`/`hold_block`/`divorce_block`/`summon_block` 純函數）；新 `sim/sim_marry.gd`（`cmd_marry_propose`/`buy_cake`/`open_cake`/`share_cake`/`book`/`hold`/`summon`/`message`/`divorce` + `marry_view` read-model + `_spread_festive`/`_spawn_spouse`/`_spouse_ent` + 覆寫 `cmd_companion_dismiss` 擋免職配偶；繼承鏈 `sim_office` 改 extends `sim_marry`）；`data/quests.json` +2 條 `type:marry`（`marry_letter_m`/`marry_letter_f`，giver = 朝廷官員，`pre.gender` 男/女 + minLevel 10）；`data/quest_npcs.json` +4 NPC（禮餅商/開餅盒師傅/朝廷官員/斷情絕愛郎，許昌結婚村）；`rules/quest.gd` `pre_ok` +`pre.gender`；`sim_core` state +`marry`、`game_data` +`marry`；`sim_recruit._recruit_daily` 配偶唔期滿/低忠誠唔走；`sim.gd load_string` +`_ensure_marry`；`game_data` 物品效果 +type 19 → 回復 SP（喜餅點心）；新 `tests/run_marry.gd` 127 項。
  - 偏離／【待決→推薦方針】：喜餅價位用 `items.json` 原有 1000/2000/3000/5000（攻略寫 1000/3000/5000/10000，改為數據驅動）；「同伴好感」用登用同伴忠誠值（0~100，武將冇獨立好感表）；結婚村 NPC 落許昌城（20,33~21,34 全域 152,33~153,34，貼現有城池做法，唔新開地圖）；分餅 = 用開餅 → 4 種點心（各回 HP/MP/SP，use_item 已通）入袋 + 全城居民好感 +10 + 婚慶氛圍 1 日；婚禮需先預約（主婚人 = 朝廷官員 NPC）；婚戒無限召喚扣 50 SP（實體唔見可由武將表重生）；離婚斷情絕愛郎扣 50 萬兩 + 回收婚戒 + 配偶實體離場。`cmd_acceptQuest`/喜帖/彩球喜糖/強迫離婚（刪角）唔做（無下游/單機無刪角）；婚禮面板 + 配偶頁 UI 留欠債。
  - 驗收：`tests/run_marry.gd` 127 項（資料/道具/純函數/求婚/喜餅/分餅/婚禮/召喚/叮嚀離婚/配偶唔期滿/讀取/存檔 roundtrip/舊存檔/決定性），接入 `run_tests.sh`；`sh tools/run_tests.sh` **ALL OK**（尾行 `ALL OK`，marry 127 / hud 4195 / uitest 126 / autotest + 4 導入器 --check 全過；首即過，未見 uitest flake）。

### UI 補完 Step（U01~U15，2026-09-26 定；PLAN §3 邏輯全剔後嘅收尾工作，S10 國戰前插隊做）
> 排序依據：**玩家實際使用頻率**（戰鬥/同伴類 → 經濟 → 官方行政類 → 一次性設定/劇情類 → 低頻顯示類）。
> 風格依據：**三國群英傳M + 三國演義 Online** 原作 UI（`ui/panels/ui_theme.gd` 墨啡底金邊 + 現有 `mount_panel.gd` 等已定風格，跟版）。
> 規則：**一個 UI 系統 = 一個 session**，每份跟 `GamePanel` 慣例（讀 `sim.*_view()` read-model、`main._send()` 發意圖、`sig()` 判斷 refresh），做完要 `--uitest` 過 + 剔呢度個格 + 更新 CLAUDE.md「已知 UI 欠債」刪走已做嗰行。
- [x] **U01 戰騎面板**：`beast_view` read-model 已備 → 新 `war_beast_panel.gd`（馴養買獸/出戰跟隨/訓練/友好效果顯示/賣出，仿 `mount_panel.gd` 頁面結構）完（頁 0 出戰狀態+加點+戰鬥/友好特技練+賣出，頁 1 馬廄列表+出戰收回+馴養買新+NPC拍賣場戰騎部分；`main.gd` +7 個 `beast_*`/`auction_buy` 意圖派送、`mobile_hud.gd`/`more_panel.gd` 入口；`sh tools/run_tests.sh` ALL OK，hud 4195/ui_smoke 129 過）
- [x] **U02 座騎補完**：`mount_panel.gd` 加改名輸入框、繁衍頁（借種馬/胎教 5 揀 1/積點分配/待領小馬）、馬戰頁（買兵器/學特技/HUD 特技掣）（commit 6a24af4）
- [x] **U03 同伴主動特技掣**：`recruit_panel.gd` 加遁地/挑釁/急救掣（`companion_skill` 意圖 → `cmd_companion_skill(id,kind)`），按冷卻剩餘 disable + 顯示秒數；22 職業特技冷卻/消耗加成用文字顯示（`classSkillMul`）。`sim_recruit.gd companion_view()` 加 `activeKind/activeCdLeft/activeCdTotal/classSkillMul` 欄；`main.gd` 加 `companion_skill` 派送。`sh tools/run_tests.sh` ALL OK。
- [x] **U04 NPC 拍賣場**：`mount_panel.gd` 馬廄頁加 `_build_auction`（座騎部分，仿 `war_beast_panel.gd` 已有嘅戰騎部分，`kind=="mount"` 過濾）；sim 早已支援兩種 kind，唔使改 `sim_war_beast.gd`；`sig()` 加 `_aview()` 令每日換貨即時反映；`sh` hud/uitest/war_beast 三個 leg PASS
- [x] **U05 官宅面板：頭銜/官令/義舉/進貢**：新 `office_panel.gd`（4 頁：頭銜討取+俸祿、官令接/交/放棄、義舉證明繳交+進貢物資、名額競爭顯示），全接現有 sim read-model/cmd（`merit_list`/`cmd_merit_turnin`/`city_favor_view`/`cmd_city_tribute`/`title_contest_view`/`order_text`/`order_block`）；`main.gd` 加 `merit_turnin`/`city_tribute` 意圖派送，`mobile_hud.gd`/`more_panel.gd` 入口；hud/title leg PASS（uitest 掉落 2 個 fail 為現有 flaky test，stash 前後都會偶發，同呢個改動無關）
- [x] **U06 官宅面板：內政 + 城池屬性**：`office_panel.gd` 加第 5 頁「內政」（城池 8 項屬性顯示 + 6 種內政工作，扣行動力/專長經驗/封頂 100），全接現有 `domestic_view`/`cmd_domestic`；`main.gd` 加 `domestic` 意圖派送；hud/civic/uitest leg PASS
- [x] **U07 救災**：`office_panel.gd` 加第 6 頁「救災」（公佈欄各城天災+對應物品、領救災官令/救災工作/交令放棄），全接現有 `bulletin_view`/`relief_view`/`cmd_office_relief`/`cmd_relief_work`；公佈欄/救災區設施本身用通用 fac 圖示（`facilities.json` bulletin/relief 旗）已顯示，唔使額外畫；hud/title/uitest leg PASS
- [x] **U08 義勇軍面板**：新 `militia_panel.gd`（頁 0 定居揀城池、頁 1 義勇軍成立條件/擁護者/已成立顯示名號根據地階級帶兵量成員），全接現有 `settle_view`/`militia_view`/`cmd_settle`/`cmd_militia_found`；遊說擁護者掛喺長按居民 menu（`main._open_npc_attack` 加「遊說（義勇軍）」選項 → `cmd_militia_invite`，紅名殺人魔冇呢個選項）；`main.gd` 加 `settle`/`militia_invite`/`militia_found` 意圖派送；`mobile_hud.gd` 註冊 `militia` 面板 + `militia_panel()`；「更多」面板加入口；hud/militia/uitest leg PASS
- [x] **U09 營地面板**：新 `camp_panel.gd`（頁 0 設施升級/監督建設、頁 1 22 項工作分系顯示、頁 2 評定會議指派 + 召開、頁 3 倉庫/商情/訓練度），全接現有 `camp_view`/`militia_work_view`/`eval_view`/`cmd_camp_upgrade`/`cmd_camp_supervise`/`cmd_militia_work`/`cmd_eval_assign`/`cmd_eval_meeting`；`main.gd` 加 `camp_upgrade`/`camp_supervise`/`militia_work`/`eval_assign`/`eval_meeting` 意圖派送；`mobile_hud.gd` 註冊 `camp` 面板 + `camp_panel()`；「更多」面板加入口；hud/camp/uitest leg PASS
- [ ] **U10 民心/法令面板**：`office_panel.gd` 加城池民心/稅率/法令頁（`city_gov_view`/`cmd_city_tax`/`cmd_city_law`）+ 丟物品掣（`cmd_drop_item`）
- [ ] **U11 LLM 設定 + 對話**：設定頁（key/模型，寫 `LlmClient`）+ NPC 對話顯示 LLM 回覆 + 真 `HTTPRequest` 接線（`llm_client.gd http_transport` 已備）
- [ ] **U12 結婚面板**：新 `marry_panel.gd`（求婚/喜餅/分餅/婚禮預約主婚/配偶頁/叮嚀/離婚，`marry_view` 系）+ 結婚村 4 NPC 圖示
- [ ] **U13 導航/天眼 + 其餘友好技**：小地圖顯示（`beast_view.effects` 導航/天眼 flag）
- [ ] **U14 建角面板正式化**：`create_panel.gd` 由 debug 版換做正式（三國群英傳M 風格揀職業/性別/初值分配）
- [ ] **U15 記事分類頁**：`quest_panel.gd` 分類（新手/官令/歷史/團體/絕招/戰役/場景/專長）+ 傳聞 UI（`rumor_view`/`known_rumors`，`rumor_panel.gd` 已有底可能只需擴充）
- 每 session 完成後喺呢度剔格 + 喺對應 CLAUDE.md「已知 UI 欠債」行刪走已做部分；`sh tools/run_tests.sh` 要保持 ALL OK（`--uitest` 煙霧測試）

### S10 國戰（spec 10）— 開工前 D-3 必須定案【待決】
- [ ] S10a 帶兵量 + 兵種資料 + 戰棋純規則（交兵/對剋/士氣）
- [ ] S10b 討伐程遠志原型（戰場 scene + 部隊 UI）
- [ ] S10c 城池攻防 + 民心/法令啟動（清 S08g）
- [ ] S10d 其餘歷史戰役（三公/長阪坡/赤壁/潼關）
- [ ] S10e 世界勢力模擬 + 宣戰節奏
- 驗收：`tests/run_war.gd`（新）

### S11 資料對照（spec 11）
- [ ] `material_ids.json`、箭矢定義（如 S02c 未做）、商城道具單機化定案（福神抽/虛寶池）、`recruitinfo.txt` → 說明頁 UI、warbtl 對照（S10 用）
- [ ] 全攻略覆核：§10 113 頁逐頁勾
- 驗收：各導入器 `--check`

### S12 地圖世界（spec 12）
- [ ] 收集 S04~S10 期間加嘅地圖做總驗收；B4 其餘州郡【待決】
- 驗收：`tests/run_maps.gd` 全過

### 收尾
- [ ] 換素材 + 打磨（建角面板已喺 S01b 做）；真機測試；存檔向後兼容

---

## §4 延後掛鈎表（跨 spec 依賴；後面 Step 開工時要清）

| 來源 | 內容 | 喺邊步接 |
|---|---|---|
| S01c | 內政專長效果 | **S08b（已接：`RulesExpert.domestic_mult` × 官宅內政增量）** |
| S01c | 救災專長效果 | **S08c（救災已實裝）；S08f 已接：義勇軍「防災」工作增量 × `relief_mult`** |
| S01c | 訓練/警戒/偵查/統御/補給 | **S08f 已接訓練 `xunlian`/治安 `jingjie`（`militia_mult`）；偵查/統御/補給 → S10** |
| S01c | 專長任務升級 | **S06e（已接）** |
| S06e | 專長任務地點：原作襄平（左慈）/北平（于吉）/廬江（南華老仙）/江夏山洞（甘德一級洞）/小沛八卦台 全屬豫荊以外【待決→已用推薦方針】——唔新開地圖，搬現有豫荊地圖（長沙/洛陽/汝南洞窟/襄陽），同 S06d 做法；出豫荊新地圖留返地圖批次 | 後續地圖批次（spec 12 B4） |
| S06e | 左慈渾天儀任務（sy3_9_2：狐狸皮×5 → 許昌兄妹 → 渾天儀 26029）；未做，認證 1~4 級已唔靠佢；狐狸皮 25109 cat 34 掉落途徑要接怪物 | 後續批次（同渾天儀商城道具單機化一齊，§4 S01c 渾天儀來源） |
| S06e | 國戰專長（宴會/情報/風速/風向/天變/偵查/補給/統御）＋屬性石 100% 兌換 NPC（采福/玄冥/赤女/若峰）| S10 |
| S06e | UI 記事分類頁未分「專長」；認證任務無新 UI（沿用現有任務對話/記事），UI 欠債 | 後續專 UI Step |
| S01d | 三轉任務（七彩項鍊） | S04d |
| S02c | 各職絕招任務鏈 | **S06d（已接）** |
| S06d | 絕招任務採集道具掉落途徑：原版 quest item（極惡令/百年狐膽/鐵礦石/昆蟲藥粉/滅獸印記/千年礦石…）部分冇對應怪物掉落（同義士力拔山河千年礦石），暫靠合成/市場【待決→推薦方針】 | 後續掉落/地圖批次 |
| S06d | 義士 + 其他職二/三招地點：原文嘅晉陽/河內/桂陽/濮陽/譙城/洛陽橋/武陵/零陵 全屬豫荊以外【待決→已用推薦方針】——唔新開地圖，一律搬去現有豫荊地圖（潁川郊外/許昌/汝南洞窟/荊州/長沙），做法同 Step 10 義士三招；出豫荊新地圖留返地圖批次 | 後續地圖批次（spec 12 B4） |
| S02c-仕女 | 開鎖效果（任務寶箱/門實體；sim `cmd_use_skill`/`cmd_skill_pick` + unlock 面板已通） | S04 寶箱實體 / S06 任務寶箱 |
| S02c-辯士 | 弩箭消耗來源：商店賣箭 / 木匠製箭（`RulesAmmo` 耗箭邏輯已通，只欠補箭途徑） | S05 |
| S02c-美女 | 恢復術一~七級來源：任務/戰役掉寶（`spells.json huifu1~7` + items 30697+ 已定義可用，只欠掉落途徑） | S04 |
| S03a | 叫衛兵 `guard_alert` 事件 + NPC 目擊記錄（`ch criminal/murder/witness`，`_kill_bot` 已發） → 城門衛兵拒入殺人魔 + 罪犯拒官令 + 天譴 | **S03b（已接）** |
| S03b | 城門「拒入城」採用「城內服務拒絶 + 定期 guard_warn」而非硬閂城門（連續地圖 + 死亡返客棧先天衝突；見樣 ·3 完成註）——**S08g 已接 `guard` 城池法令**（`_city_guard_check` 冇僱護衛就唔警告；未佔城 = 照舊）。spec 08 法令 7「善惡 ≥1001 非本勢力入城」單機玩家 = 定居者豁免，留佔城/勢力系統 | S10c（`dangerEntry` 下游） |
| S05b | 工具正式來源（團體任務） | **S06c（任務已實裝）+ S08f（義勇軍 monthly 可重接）** |
| S06c | 義勇軍限定團體任務 | **S08f（已接：monthly 重複、日窗口、完成 → 績效）** |
| S07c | 撿寶/幸運護身還魂/聖體 | 要 S04a/S03c/S01a 先（**已接**：撿寶自動執 `_drop_items` 產出、幸運/護身/還魂 friendly 代替死亡道具、聖體 `_safe_regen_tick` ×2） |
| S03c | 死亡道具正式來源：三件（65016 幸運符/65029 護身符/65030 還魂丹）淨返票先入藥膳師庫存（價 500/800/1500）；代 11 商城道具定案時再改價/改來源（`data/shops.json` herbalist + `data/items.json`） | **S11（已接過渡：藥膳師庫存）** |
| S04a | 「背包滿」負重上限：本事步先用 `world.json dropped.capBagWeight=1000`（items.json weight×件數）【待決→用推薦方針】；真正負重系統（上限公式/稱號加成/搬運）S05 城際貿易做時確定 + 重用 `RulesShop.bag_weight/bag_fits` | S05 |
| S08a | 義舉證明 20 項物品來源途徑未接（61501~61510 任務物品 / 61037~61046 收藏品，現時都冇怪物掉落/商店）；邏輯層（繳交/頭銜門檻）已通，考驗用 `RulesShop.add_item` 落包 | 後續掉落/商店批次（同 S06 任務雜物一齊考慮） |
| S08a | 城池好感下游效果未接（`ch.cityFavor` 已存 + `city_favor_view` read-model）；影響居民/NPC 打招呼、登用好感、任務解鎖等 | S08b/S09 |
| S08a | 襄陽冇捐獻處（只有許昌官宅/新野縣衙），暫時進貢唔到；要加襄陽捐獻處 | 後續設施批次（S08e 定居/設施一齊考慮） |
| S08e | 義勇軍面板 UI（定居/遊說/成立/成員/階級/帶兵量）：`settle_view`/`militia_view`/`cmd_settle`/`cmd_militia_invite`/`cmd_militia_found` read-model + 意圖已備但無面板/掣 | 後續專 UI Step |
| S08e | 義勇軍階級管理/權限設定/俸祿設定/名號暗號實際用途（除咗存低）未接 | **S08f（評定指派已接）；階級管理/權限/俸祿設定 → 後續** |
| S08e | 頭目/擁護者帶兵量只係 read-model（`militia_view.soldiers`），未有兵種/戰場系統 | S10（帶兵量 + 兵種 + 戰棋） |
| S08e | 定居城池限 `maps.json kind:city` 現有 10 城；各城未必有官宅/設施（如宛城/長沙），要城池設施批次先補 | 後續設施批次 |
| S08b | 城池「防禦」屬性下游（城牆/守城/攻城）未有系統，只出 read-model；要 S10 城池攻防接 | S10 |
| S08b | 城池「治安」「防災」屬性提升途徑（官宅內政唔包）：**S08f 義勇軍工作「治安」「防災」已接（`RulesCity.attr_gain` + `jingjie`/`jiuzai` 專長）**；**S08c 救災實裝 = 直接減弱生效中天災 effect（非提升防災 attr）** | **已接** |
| S08c | 襄陽冇官宅（同 S08a 捐獻處問題）→ 襄陽救災官令暫時冇得領；救災區（longzhong）已備 | 後續設施批次（S08e 定居/設施一齊考慮） |
| S08c | 「多人救災加快（武將同伴助攻）」未接（單人做 N 次）；同伴協助 hook（`sim_recruit` `_domestic_assist_bonus` 等）S09c 已備，但救災次數未按同伴加成 | 後續批次（如要做） |
| S08d | 名額競爭 UI：`title_contest_view` read-model 已備（競爭狀態 + 上次結果）；官宅面板未有顯示 | 後續專 UI Step（官宅面板分頁） |
| S08d | NPC 挑戰者有分數冇 NPC 實體/名號；原版「武將 PK（弱化版）」再簡化成「比名望」 | 後續（若要真 PK/有名有姓先做） |
| S01c | 救災專長倍率 `RulesExpert.relief_mult` 未有下游（spec §6 只寫「增加救災專長」，冇定義倍率效果）| **S08f 已接：義勇軍「防災」工作增量 × `relief_mult`** |
| S08f | 營地面板 UI（設施升級/監督/22 工作/評定會議/倉庫/商情/訓練）：`camp_view`/`militia_work_view`/`eval_view`/`cmd_camp_upgrade`/`cmd_camp_supervise`/`cmd_militia_work`/`cmd_eval_assign`/`cmd_eval_meeting` read-model + 意圖已備但無面板/掣 | 後續專 UI Step（營地面板） |
| S08f | 徵兵/軍馬/軍糧/藥品只係義勇軍 store 加減（`camp.stores`），未有兵種/戰場/實際食用；營地規模進階功能（召喚部將回營、材料庫轉入轉出、兵營武將情報）未接 | S10（帶兵量 + 兵種 + 戰棋）/ S09（武將情報） |
| S08f | 商情情報值（`camp.trade` 0~100）未有下游（原版：85 睇商店 / 80 睇武將情報）| S09/S10 |
| S08f | 「杉竹 / 白石礦石」items.json 冇 → 用箭竹 25054 / 石頭 25001 代替（營地升級材料）| 後續道具批次（如要忠於原作名） |
| S08b | 內政武將政治協助（同伴/部將加成）：**leg 17 已接**（`_domestic_assist_bonus` 由 `sim_recruit` 覆寫：同伴政治 + 內政特技 39~42；營地監督 +`_companion_pol_bonus`），部將加成要等 S10 | S09c 已接 |
| S09b | 傳聞只記「murder」類型；其餘可傳事件（任務/財富/善舉）留待有需要再加 `kindMap` | 後續批次 |
| S09a | 居民日程（各時辰 sleep/work/eat/home）只做資料 + `resident_view` read-model，未驅動實際行動（居民仍行現有野區戰鬥 AI，只改用自己城 homeZone） | S09c/S09d 或後續 |
| S09a | role 嘅 `work` 種類（field/shop/gate/stable/office）未有下游工作點/功能（商販買賣、衛兵攔路、馬夫等） | S09c 或設施批次 |
| S09a | 洛陽/長沙/小沛/下邳/零陵冇客棧/市場/設施；居民低血唔撤退、冇商店互動 | 後續設施批次（同 S08 各城設施） |
| S09b | 傳聞只出 read-model（`rumor_view`/`known_rumors` + `rumor_spread` 事件），未有 UI 顯示 NPC 已知傳聞/惡名傳播；`npc_brain` 未讀傳聞改對話 | 後續專 UI Step / S09d（LLM 對話讀傳聞） |
| S09b | LLM 每日「反思摘要」（`mem.summary`）未做 —— S09b 只做規則版每日傳聞擴散批次 | S09d（LLM 層） |
| S08g | 民心/法令邏輯做完；城池佔領（`state["cityGov"]` 啟動入口 `city_gov_init`）要接城池勢力/攻城 | S10c |
| S08g | 法令下游未有系統嘅先存落 gov：`caveShops` 山洞商店（現冇山洞商店）、`cityPk` 城內 PK（原作未開放）、`dangerEntry` 善惡 ≥1001 非本勢力入城（單機玩家 = 定居者豁免） | S10（佔城/勢力）或後續場景批次 |
| S01c | 渾天儀來源（商城道具單機化定案，`sim.gd WEATHER_ITEM 26029` 已資料有、冇商店賣） | S11 |
| S09c | 國戰類特技/寶物（23~31 火攻/水攻/…、33~37 威壓/…、53~70 統率/…） | S10 |
| S09c | 主動特技 21 無限遁地/22 職業特技/32 挑釁/38 急救 —— **leg 18 S09c-b 已實作**（`cmd_companion_skill` + `_companion_class_skill_mul`；UI 欠債：無掣）| **已接**（UI → 後續專 UI Step） |
| S09c | 22「職業特技」採 proximity 被動（同伴同圖 `auraRange` 內 → 主公職業特技冷卻/消耗 ×0.5），非主動指令；攻略只寫「使用職業特技」冇機制 | 已定（如要真主動再議） |
| S09c | 主動特技 UI：`cmd_companion_skill(pid,kind)`（遁地/挑釁/急救）read-model/意圖已備但無同伴面板掣；`eff.active` 資料齊 | 後續專 UI Step |
| S09c | 44 鑑定（items.json 冇未鑑定狀態／鑑定系統） | 後續（要道具設計）或 S11 |
| S05c | 白晝之珠正式來源（神秘洞窟打怪掉落，v1 後期新場景）；過渡用官宅貢獻兌換（`cmd_master_redeem_baizhu`） | 後續批次（同 通天關/黑山寨 等一齊考慮） |
| S05c | 大宗師合成場景開唔開放由城主法令決定 → **已接** `crafts` 法令（`cmd_master_gem`/`cmd_master_treasure` 閘）；未佔城 = 照舊常開 | S08g 已接 |
| S07b | 戰騎獲得途徑【待決→推薦方針】原版捕獲/任務/商店；而家用馬廄「戰騎馴養」買幼獸 + 每隻出戰；原版捕獲機制未做 | S07d **已加 NPC 拍賣場隨機上架** / 後續捕獲批次 |
| S07b | 戰騎戰鬥特技 buff/debuff 部分 stat：**leg 6 已接** spellAtk/lifesteal/mpRegen（beastBuff 下游）+ 降敵 def/atk（beastDebuff 下游）；debuff 嘅 spellDef/hit/evade 對物理怪冇下游效果 | 後續（有需要先） |
| S07c | 友好技導航/天眼只出 read-model flag（`beast_view.effects`），小地圖/顯示 NPC 嘅 UI 延後 | 後續專 UI Step |
| S07c | 神奇【待決：錢莊介面】→ 單機化 = 免訂閱用天地商行倉庫（存/攞）；原版錢莊（存款/提款）未做 | 後續（有需要先） |
| S07c | 金剛/守護【自訂簡化】= 出戰期間常駐 armor1/mirror1（唔係施放一次） | 後續（有需要先） |
| S07c | 其餘友好技效果未接：聖靈/遁地/奇門/脫出/召喚/神行/回城/火焰/飛影/狂力/開光/忠誠/巨力/穩重/地行/神獸/嗅血/野性/獅魂/王者（多數係道具/UI 功能） | 後續批次 / 專 UI Step |
| S07b | 戰騎 UI 面板 + 出戰/訓練/友好/賣掣未有（`beast_view` read-model 已備，`effects` 欄亦備） | 後續專 UI Step |
| S07d | NPC 拍賣場【自訂】寄喺馬廄（唔另起設施/改地圖）；`auction_view`/`cmd_auction_buy` read-model 已備 | 後續專 UI Step（拍賣掣）/ 如要專屬拍賣場設施再議 |
| S07d | 拍賣只做「NPC 上架 → 玩家買」；玩家寄賣/交易沿用 `cmd_beast_sell`/`cmd_mount_abandon`（唔另做寄賣/競價） | 後續（有需要先） |
| S07d | spec 07 §9「玩家疲勞放牧都會執到」【自訂簡化】併入放牧 loot，唔另做拍賣相關拾取 | 後續批次 |
| S07d | 抽技打亂處理【已做】：抽技池由 `general_skills.json cfg.drawPool` 釘死 + `cfg.pin` 指派新特技；將來 toggle `impl` 唔再改動其他武將隨機抽技 | 已完成（機制） |
| S09d | LLM 真 HTTPRequest 接線 + 設定頁（key/模型）+ NPC 對話顯示 + `llm_request`/`llm_action` 事件處理：邏輯層 sim 已發 event + `LlmClient`（`user://llm.cfg` + `http_transport(http)`）已備 | 後續專 UI Step |
| S09d | `acceptQuest` 只出 `llm_action` 事件標記（未有玩家→NPC 請求/委託派發系統）；`hint`/`rumor`/`refuse` 亦只係對話標記 | 後續（要請求/委託系統先）或 S10 |
| S09d | 反思 `mem.summary`/`mem.goal` 只寫入 + read-model（`llm_view`/`NpcMemory.summary`），未驅動 NPC 行為/選項 | 後續批次（NPC 行為擴充） |
| S09d | LLM pending 請求唔入存檔（重載 = 請求當冇，模板後備照玩）；`state.llm.cd` 冷卻表已存檔 | 已定（単機重載安全） |
| S09e | 婚禮面板/配偶頁 UI：`marry_view` read-model + `cmd_marry_propose`/`buy_cake`/`open_cake`/`share_cake`/`book`/`hold`/`summon`/`message`/`divorce` 意圖已備但無面板/掣；結婚村 4 NPC 亦冇圖示 | 後續專 UI Step |
| S09e | 喜餅價位沿用 `items.json` 原有 1000/2000/3000/5000（攻略寫 1000/3000/5000/10000）——數據驅動 | 已定（如要忠於原作價位再改 items.json） |
| S09e | 結婚對象「好感 ≥90」用登用同伴忠誠值（武將冇獨立好感表）；原作「送禮」門檻未另設（同伴補品/寶物指令已有） | 已定（如要武將好感表再議） |
| S09e | 喜帖/婚禮拋彩球灑喜糖（拾特殊寶物）/刪角強迫離婚 未做（單機冇其他玩家/刪角） | 後續（如要彩球活動再議） |
| S09e | `game_data` 物品效果 +type 19 → 回復 SP（喜餅點心 29106~29115 等 食物藥水/藥丸散會變可用）| 已接（cmd_use_item 自動支援） |
| 2026-09-25 討論 | 多存檔 + 共享世界隊友（方向 2.5，見下）| S02c 做完後開新 Step |

---

### 多存檔 + 共享世界隊友（2026-09-25 定方向，未開工）

**需求**：本機三個 save slot，各揀職業。世界時鐘共享（三個角色見到同一「現在」），但**離線唔行**（冇 offline tick）。可以喺房入面見隊友、揀佢一齊出隊，戰鬥入面隊友 = AI 控制（唔係真人操控第二隻），可以落簡單指令、可以叫佢返屋企（踢出隊）。

**排除方案**（討論過，唔採用）：
- 各自獨立時間線 → 冇「共享世界」感，太簡單唔夠好玩
- 真·持續世界（離線都繼續行）→ 要做 offline-catchup 邏輯（天災/NPC/市場），工程量大好多，同「離線唔行」嘅需求都唔夾
- 兩個角色同時真人操控同一場戰鬥 → 推翻 A2 架構「一個 player_ch()」假設，改動面太大

**技術要點**（落實時展開做細步）：
1. `world_clock` 抽出做獨立共享檔案（脫離個別 save，唔再綁喺 `sim_core.gd` 個別 state），登入邊個 save 都讀同一份、寫返同一份
2. Save slot 選單 + 建角揀職業 UI（三個 slot，主 menu 顯示角色名/職業/時鐘/等級 metadata）
3. 房 UI：讀第二/三個 save 嘅 snapshot 顯示隊友「喺度」；揀邊個入隊（讀一次快照，唔即時 sync）
4. `sim_ai.gd` 加 ally-AI 分支（攞怪物 AI 邏輯改），戰鬥入面聽簡單指令（跟打/守/用邊隻術法），UI 似登用武將個 command 介面
5. 「叫佢返屋企」= 踢出隊，佢個 save 繼續閒置（唔行動、唔耗時間）
6. 存檔向後兼容：舊 save 冇 world_clock 概念，要定遷移規則

**未定**：隊友喺戰鬥入面攞邊套 stats/skills（讀佢 save 嗰刻嘅定型？定即時讀？）；隊友經驗/成長會唔會受組隊戰鬥影響（如果會，牽涉寫返去佢個 save，要諗清楚時機同存檔鎖）

---

## §5 風險與規則（不變）
- 每步可跑可驗證；未過驗收唔開下一步；公式全部【自訂】放 rules + data
- 攻略業務邏輯全部要保留（spec 11 §10 對照表）
- 素材規則：assets_placeholder 唔入 git
- 測試用 mock，唔碰網絡
- 豫荊以外地點（晉陽/河內/桂陽/洛陽…）：每次遇到先問用家 新開地圖 定 搬去豫荊【自訂】
