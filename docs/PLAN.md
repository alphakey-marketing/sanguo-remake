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
| 02 戰鬥 | 🟡 | 🟡 | 近戰、術法、相剋、狀態、寶石、義士三招 + 融合、防具/武器 3 槽/耐久、組隊經驗分配（按傷害 70%/平分 30%）、狀態 icon 列、術法快捷列 3 本切換 UI、**仕女（特技開鎖 + 三招絕招）**、**道士（特技超渡 + 三招絕招 + 同伴倒下機制）**、**巫女（特技潛行 + 行車 QTE + 三招絕招 + 潛行避仇恨）** | 其餘 2 職（辯士竊聽+弩箭消耗/美女透視 + 各職三招絕招）、多絕招 HUD 已通 |
| 03 善惡死亡 | 🟡 | ✅ | 七階、死亡掉物品/跌經驗、價格加成 | 攻擊居民/紅名 NPC（而家 `cmd_attack` 只准打 mob）、反擊 +100、天譴、幸運符/護身符/還魂丹、殺人魔拒入城、罪犯拒官令 |
| 04 怪物地圖 | 🟡 | ✅ | 46 怪 + 掉落導入、重生、逃跑/群攻、boss 每日、夜怪、汝南洞 10 層、張牛角戰役 | 地面掉落物（`dropped` 實體）、術法怪/boss 技能、特殊場景 7 個（`scenes.json`）、其餘 5 場戰役實體 |
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
- [ ] **S02c-辯士**：竊聽特技（居民對話竊聽情報）+ 導師；佢三招絕招；**弩箭消耗**（箭矢 cat 49 已有 items，要消耗邏輯 + 商店賣箭/木匠製箭 = S05）
- [ ] **S02c-美女**：透視特技（睇 NPC/怪隱藏資訊）+ 導師；佢三招絕招（美女仲有葉/針術 + 恢復術，照術書表）

### S03 善惡死亡（spec 03）
- [ ] **S03a 可攻擊 NPC**：`cmd_attack` 開放居民/紅名 NPC（安全區照禁）；居民反擊/逃跑/叫衛兵；殺善一次過 −1000、紅殺紅 +300、反擊成功 +100
  - UI：長按 NPC 出「攻擊」（二次確認）；紅名顯示
- [ ] **S03b 天譴 + 城門**：殺居民（非自衛）→ 雷劈 50% HP + 傳送客棧 + 公告；殺人魔城門衛兵拒入 + 警告；罪犯以下唔接官令
- [ ] **S03c 死亡道具**：幸運符（唔跌物品）/護身符（經驗減半）/還魂丹（天譴無效）；來源【待決，同 spec 11 商城道具定案】；死亡流程 6 步順序照 §4.3
  - UI：背包道具說明、死亡結算彈窗（跌咗乜/扣幾多）
- 驗收：`tests/run_karma.gd`（新）

### S04 怪物地圖（spec 04）
- [ ] **S04a 地面掉落物**：`dropped` 實體（300 tick 消失）、撳地拾取、背包滿處理；存檔 roundtrip
  - UI：地上物品圖示 + 拾取掣
- [ ] **S04b 術法怪 / boss 技能列表**：遠程術攻擊 + 吟唱線索；boss 技能表資料化
- [ ] **S04c 其餘 5 場戰役實裝**：褚飛燕 → 李大目 → 張白騎 → 黃龍 → 十常侍（每場 monster + 多層 map + 掉寶齊）；戰役狀態入記事/大地圖
  - UI：記事「戰役」頁（今日窗口/進度）、大地圖標示
- [ ] **S04d 特殊場景框架 + 首批**：`data/scenes.json`（schema 照 §4）、game 日曆開門、公告；首批【待決揀邊個】（建議：桃花渡 → 七彩奪寶陣（接 S01d 三轉））
- 驗收：`tests/run_monsters.gd`/`run_battle.gd` 擴充 + `tests/run_scene.gd`（新）

### S05 生產經濟（spec 05）
- [ ] **S05a 小缺口**：初階產出 1~2 件；4 類商店補齊（工具/藥房/食物/雜貨）；天災大/中規模停進貨 `shutdownDays`；城際價差（地圖面板顯示各城市價）
- [ ] **S05b 特製/白金/御賜工具**：3 等工具耐久/成功率；來源 = 任務獎勵（團體任務 S06c 前先用官宅兌換過渡）
- [ ] **S05c 大宗師合成術**：條件 100/20、新初階/進階材料（產出地【待決：豫荊外城池點處理 — 建議改指定豫荊地點【自訂】】）、白晝之珠、5 合成寶石、進階大宗師（`data/master_recipes.json`）
  - UI：工房「大宗師」頁
- 驗收：`tests/run_craft.gd`/`run_tiandi.gd` 擴充 + `tests/run_master.gd`（新）

### S06 任務（spec 06）
- [ ] **S06a 官令補齊**：訂製軍備、官員護衛（護送 NPC）、朝廷求才（登用 1 文官）、流落官員（野外救人）
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
| S05b | 工具正式來源（團體任務） | S06c/S08f |
| S06c | 義勇軍限定團體任務 | S08f |
| S07c | 撿寶/幸運護身還魂/聖體 | 要 S04a/S03c/S01a 先 |
| S08g | 民心/法令要有城池 | S10c |
| S01c | 渾天儀來源（商城道具單機化定案，`sim.gd WEATHER_ITEM 26029` 已資料有、冇商店賣） | S11 |
| S09c | 國戰類特技/寶物 | S10 |
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
