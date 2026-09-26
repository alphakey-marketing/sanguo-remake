# 計劃 v6（2026-09-24 重排：逐份 spec 補完 邏輯 + UI）

整體設計見 `DESIGN.md`。**完整系統邏輯規格** = `docs/spec/01~12`。玩法原文摘錄 = `普通玩法_系統摘要.md`。
舊路線 v5（Step 1~19 軌跡、每步「偏離 spec」記錄、驗收項目數）→ `docs/PLAN_v5_history.md`（唔再改，淨係查）。

> **接手 agent 必讀**
> 1. 路線改為 **由 spec 01 順序做到 spec 12**：每份 spec 一個大 Step（S01~S12），入面拆細步（a/b/c…）。下一步 = §3 第一個未剔 `[ ]`。
> 2. **每細步 = 邏輯 + UI 一齊交**：rules 純函數 + 測試 → sim 指令 + 場景測試 → UI 面板/掣 → `--uitest` 煙霧。冇 UI 唔准剔格（除非該項標明「純後台」）。
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
| 06 任務 | 🟡 | ✅ | 框架、新手 5 條、義士絕招 3 條、官令 3 條、歷史 6+1 條、委託、戰役 | 其餘 4 條官令、團體任務 16 項、其餘 5 條歷史、其他職絕招任務、專長任務、結婚 |
| 07 座騎戰騎 | 🟡 | 🟡 | 17a 座騎全套 + UI；17b 繁衍/馬戰 **sim 有、`main.gd` 有派送、面板未有掣**；18 戰騎純規則 | 繁衍/馬戰/改名 UI；戰騎 sim 整合（獲得/裝備/出戰/友好技效果）+ 面板；NPC 拍賣場；特技「馴馬」 |
| 08 名聲義勇軍 | 🟡 | 🟡 | 名聲、頭銜 60 階、官宅（討取/官令/捐獻/月俸/行動丹） | 義舉證明、城池進貢、名額競爭、官宅內政 6 種 + 城池屬性、救災、義勇軍、帶兵量、營地、團體工作、民心、法令 |
| 09 登用武將 | 🟡 | 🟡 | 居民 bot/記憶/brain、登用 v1+v2、同伴 6 指令、20 passive 特技 | `residents.json` 居民化、傳聞擴散、忠誠事件規則、其餘 50 特技、內政協助、LLM 層（原 Step 20） |
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
  - 延後掛鈎：內政/救災 → S08；訓練/警戒/偵查/統御/補給 → S08/S10；專長任務 → S06；渾天儀來源 → S11（見 §4）
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
- [ ] **S06b 歷史任務其餘 5 條**：孫堅匿璽/張公公謀害何進/黃蓋/曹阿瞞/討伐張角；需要洛陽/零陵等地圖【待決：新開地圖定移去豫荊】
- [ ] **S06c 團體任務 16 項**：要「所屬義勇軍」→ 依賴 S08；呢步先做任務資料 + 非義勇軍版可接嘅（紫虛上人等），其餘掛鈎 S08
- [ ] **S06d 其他職絕招任務鏈**：各職一~三招（15 條）+ 四~六招（排後，涉及多城）；義士二/三招要晉陽/河內/桂陽【待決：地點】
- [ ] **S06e 專長任務**：天文/地理認證 1~4 級（接 S01c）；國戰專長 → S10
- [ ] 結婚 → 放 S09（對象 = 武將）
- UI：記事分類頁（新手/官令/歷史/團體/絕招/戰役/專長）
- 驗收：`tests/run_quest.gd`/`run_hist.gd` 擴充

### S07 座騎戰騎（spec 07）
- [ ] **S07a 座騎 UI 補齊**：改名輸入框、繁衍頁（借種馬/胎教 5 揀 1 跑馬燈/懶人/接生/積點分配/待領小馬）、馬戰頁（買兵器/師傅學特技/HUD 特技掣）
- [ ] **S07b 戰騎 sim 整合**：獲得途徑【待決，攻略：捕獲/任務/商店？】、最多 3 隻、出戰跟隨 + 自動攻擊、吸 exp 升級、戰鬥特技出手、死亡忠誠 −1/走佬、寄馬廄
- [ ] **S07c 友好特技效果接系統**：導航/天眼/撿寶（接 S04a）/幸運護身還魂（接 S03c）/金剛守護/聖體（×2 回復，接 S01a）/背負/神奇（錢莊）/玄妙（驛站）等
- [ ] **S07d 戰騎面板 + NPC 拍賣場**（馬/戰騎隨機上架）；武將特技 52「馴馬」（處理抽特技打亂問題）
- 驗收：`tests/run_mount.gd`/`run_war_beast.gd` 擴充 + `--uitest` 繁衍/馬戰/戰騎

### S08 名聲 / 義勇軍（spec 08）— 最大，拆細
- [ ] **S08a 義舉證明 + 城池進貢**：朝廷官員（許昌）四類 20 項物品；進貢 = 城好感
- [ ] **S08b 城池屬性 + 官宅內政 6 種**：`world.json cities[].attrs`（8 項 0~100）→ 天災/市場/商店/防禦連動；內政工作 + 專長 exp（清 S01c 延後）+ 武將政治協助（接 S09）
- [ ] **S08c 救災**：公佈欄設施、救災官令、救災物品 7 種、救災區 N 次工作、覆命（名聲 +10/政治 exp/專長）
- [ ] **S08d 名額競爭**【待決：簡化方案】
- [ ] **S08e 義勇軍成立**：條件 4 項（擁護 NPC 數【自訂】、20 萬、定居非新手城 → 要「定居」功能）；品階/帶兵量公式（`titles.json soldiers`）
- [ ] **S08f 營地 + 義勇軍工作 22 項 + 評定會議**：`data/camp.json`、監督建設、功績表；團體任務接軌（清 S06c 延後）
- [ ] **S08g 民心 + 法令**（要有城池 → 可能要等 S10 攻城；先做資料 + 規則 + 測試）
- UI：官宅面板分頁（頭銜/官令/內政/救災/義舉）、義勇軍面板、營地面板、公佈欄
- 驗收：`tests/run_title.gd` 擴充 + `tests/run_militia.gd`（新）

### S09 登用武將 / NPC / LLM（spec 09）
- [ ] **S09a 居民化**：`data/residents.json`（性格/日程/role），bot → 居民；每城 12~20 人
- [ ] **S09b 傳聞擴散 + 忠誠事件**：跨城延遲 1~3 日；殺善 NPC → 義理武將忠誠 −15 等
- [ ] **S09c 其餘 50 特技**（主動/生產；國戰類 → S10）+ 內政協助
- [ ] **S09d LLM 層**（原 Step 20）：OpenRouter/JSON schema/白名單；每日反思 + 記憶摘要；設定頁 key + 模型名；Tier1 武將對話；飲水度控制 LLM/模板
  - 驗收：mock 全動作；無 key 照玩；LLM 唔改數值（斷言）；唔碰網絡
- [ ] **S09e 結婚**（spec 06 §9 / 09 §6）：御賜函、喜餅、分餅、禮堂、婚戒召喚、配偶頁、離婚
- 驗收：`tests/run_recruit.gd`/`run_general.gd` 擴充 + `tests/run_llm.gd`（新，mock）

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
| S01c | 內政/救災專長效果 | S08b/S08c |
| S01c | 訓練/警戒/偵查/統御/補給 | S08f/S10 |
| S01c | 專長任務升級 | S06e |
| S01d | 三轉任務（七彩項鍊） | S04d |
| S02c | 各職絕招任務鏈 | S06d |
| S02c-仕女 | 開鎖效果（任務寶箱/門實體；sim `cmd_use_skill`/`cmd_skill_pick` + unlock 面板已通） | S04 寶箱實體 / S06 任務寶箱 |
| S02c-辯士 | 弩箭消耗來源：商店賣箭 / 木匠製箭（`RulesAmmo` 耗箭邏輯已通，只欠補箭途徑） | S05 |
| S02c-美女 | 恢復術一~七級來源：任務/戰役掉寶（`spells.json huifu1~7` + items 30697+ 已定義可用，只欠掉落途徑） | S04 |
| S03a | 叫衛兵 `guard_alert` 事件 + NPC 目擊記錄（`ch criminal/murder/witness`，`_kill_bot` 已發） → 城門衛兵拒入殺人魔 + 罪犯拒官令 + 天譴 | **S03b（已接）** |
| S03b | 城門「拒入城」採用「城內服務拒絶 + 定期 guard_warn」而非硬閂城門（連續地圖 + 死亡返客棧先天衝突；見樣 ·3 完成註）——若日後 spec 08 法令 7「善惡法令容許殺人魔入城」要放寬，接 `world.json bots.guardWarnTicks` / `cmd_rest` / `_city_guard_check` 開關 | S08g |
| S05b | 工具正式來源（團體任務） | S06c/S08f |
| S06c | 義勇軍限定團體任務 | S08f |
| S07c | 撿寶/幸運護身還魂/聖體 | 要 S04a/S03c/S01a 先（**S04a 已接**：`sim.dropped` 實體 + `cmd_pick` 有；撿寶友好技喺 S07c 自動執 `_drop_items` 產出） |
| S03c | 死亡道具正式來源：三件（65016 幸運符/65029 護身符/65030 還魂丹）淨返票先入藥膳師庫存（價 500/800/1500）；代 11 商城道具定案時再改價/改來源（`data/shops.json` herbalist + `data/items.json`） | **S11（已接過渡：藥膳師庫存）** |
| S04a | 「背包滿」負重上限：本事步先用 `world.json dropped.capBagWeight=1000`（items.json weight×件數）【待決→用推薦方針】；真正負重系統（上限公式/稱號加成/搬運）S05 城際貿易做時確定 + 重用 `RulesShop.bag_weight/bag_fits` | S05 |
| S08g | 民心/法令要有城池 | S10c |
| S01c | 渾天儀來源（商城道具單機化定案，`sim.gd WEATHER_ITEM 26029` 已資料有、冇商店賣） | S11 |
| S09c | 國戰類特技/寶物 | S10 |
| S05c | 白晝之珠正式來源（神秘洞窟打怪掉落，v1 後期新場景）；過渡用官宅貢獻兌換（`cmd_master_redeem_baizhu`） | 後續批次（同 通天關/黑山寨 等一齊考慮） |
| S05c | 大宗師合成場景開唔開放由城主法令決定；而家常開 | S08 法令 |
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
