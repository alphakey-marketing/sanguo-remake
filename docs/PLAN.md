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

### 已完成大 Step（S01~S09）—— 已拆出逐份檔案，剔格狀態喺各檔
> 原本呢段 270 行逐細步記錄（S01~S09 全部已剔 `[x]`）太肥大，為咗縮細主 PLAN，**已完成嘅大 Step 已拆去 `docs/plan/` 獨立檔**。規格連結同每步「偏離」「延後掛鈎」「驗收」記錄全部喺相應檔，保持原樣唔郁。

| Step | spec | 狀態 | 逐細步詳情 |
|---|---|---|---|
| S01 角色成長 | `docs/spec/01_角色成長.md` | ✅ 完 | [`docs/plan/S01.md`](plan/S01.md) |
| S02 戰鬥 | `docs/spec/02_戰鬥系統.md` | ✅ 完 | [`docs/plan/S02.md`](plan/S02.md) |
| S03 善惡死亡 | `docs/spec/03_善惡與死亡.md` | ✅ 完 | [`docs/plan/S03.md`](plan/S03.md) |
| S04 怪物地圖 | `docs/spec/04_怪物地圖.md` | ✅ 完 | [`docs/plan/S04.md`](plan/S04.md) |
| S05 生產經濟 | `docs/spec/05_生產經濟.md` | ✅ 完 | [`docs/plan/S05.md`](plan/S05.md) |
| S06 任務 | `docs/spec/06_任務系統.md` | ✅ 完 | [`docs/plan/S06.md`](plan/S06.md) |
| S07 座騎戰騎 | `docs/spec/07_座騎戰騎.md` | ✅ 完 | [`docs/plan/S07.md`](plan/S07.md) |
| S08 名聲 / 義勇軍 | `docs/spec/08_名聲官宅城池.md` + `docs/spec/08_義勇軍.md` | ✅ 完 | [`docs/plan/S08.md`](plan/S08.md) |
| S09 登用武將 / NPC / LLM | `docs/spec/09_登用武將NPC.md` | ✅ 完 | [`docs/plan/S09.md`](plan/S09.md) |

> **進行中／未開（保持喺下面 inline）**：UI 補完 U01~U15 → S10 國戰 → S11 資料對照 → S12 地圖世界 → 收尾。下一步 = 最快嗰個 uncheck `[ ]`（見下方各行）。

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
- [x] **U10 民心/法令面板**：新 `civic_panel.gd`（根據地城池民心/人口/稅率 3 檔/6 條法令開關，全接現有 `militia_view`/`city_gov_view`/`cmd_city_tax`/`cmd_city_law`；未佔城顯示 active false 提示，S10 佔城後解鎖）；`bag_panel.gd` 物品詳情加「丟低 x1」掣（`cmd_drop_item`）；`main.gd` 加 `city_tax`/`city_law`/`drop_item` 意圖派送；`mobile_hud.gd` 註冊 `civic` 面板 + `civic_panel()`；「更多」面板加入口；hud/civic/uitest leg PASS
- [x] **U11 LLM 設定 + 對話**：新 `llm_panel.gd`（頁 0 設定：key/模型 LineEdit 寫入 `LlmClient`（`user://llm.cfg`，唔入 sim 存檔）+ 啟用開關 `cmd_llm_config`、用量/上次錯誤顯示；頁 1 對話：顯示最近 LLM 驅動嘅 NPC 說話 `main.llm_log`），全接現有 `llm_view`；`main.gd` 新增真 `HTTPRequest` 接線 `_on_llm_request()`（收 sim `llm_request` 事件、補返 Authorization key header、發送、回填 `cmd_llm_reply`/`cmd_llm_summary`；冇 key/傳送失敗即刻空字串回覆觸發模板後備）+ `npc_say` 事件 `llm:true` 攞落 `llm_log`；`mobile_hud.gd` 註冊 `llm` 面板 + `llm_panel()`；「更多」面板加入口；hud/llm/uitest/autotest leg PASS
- [x] **U12 結婚面板**：新 `marriage_panel.gd`（頁 0「喜事」求婚/喜餅買開分/預約禮堂/舉行婚禮、頁 1「配偶」配偶資料/召喚/叮嚀留言/離婚），全接現有 `marry_view`/`cmd_marry_propose`/`buy_cake`/`open_cake`/`share_cake`/`book`/`hold`/`summon`/`message`/`divorce`；`main.gd` 加 9 個 `marry_*` 意圖派送；`mobile_hud.gd` 註冊 `marriage` 面板 + `marriage_panel()`；「更多」面板加入口；結婚村 4 NPC 圖示留後（同其他 quest NPC 一齊，通用圖示已顯示，非阻塞）；hud/marry/uitest leg PASS
- [x] **U13 導航/天眼 + 其餘友好技**：小地圖 (`mobile_hud.gd _draw_info`) 讀 `sim.beast_effects_view(id)` 加：導航(`map_city`)喺區名列加最近城池名（新 `sim.nearest_city_view`）、天眼(`show_npc`)幫附近 NPC/同伴加名牌、嗅血(`show_low_hp`)幫低於 30% HP 嘅怪標黃色。另接 5 個純數值/邏輯友好技（`rules/war_beast.gd` +`pain_shield_pct`/`exp_mult`）：忠誠「痛楚屏障」受傷 −30%（`sim_combat.damage()`）、神獸/王者「加成」練功經驗 ×2（`_kill_mob` exp 分配）、聖靈「回滿」死亡代替回半（`_kill_player`）、穩重「免疫」中邪/冰凍定身（`sim_char._move`）、遁地/地行「傳送返城」新 `cmd_beast_teleport`（仿同伴「無限遁地」BFS 最近城池，`war_beast_panel.gd` 加掣）；`sim_core.gd` 加 `_friend_pain_shield_pct`/`_friend_exp_mult` hook（`sim_war_beast.gd` 覆寫）
  - 偏離（留返後續，冇合適掛鈎位）：脫出(`maze_escape`)/召喚(`summon_friend`)/神行(`haste_scroll`)/回城(`return_scroll`，同遁地合併咗)/火焰(`light`)/飛影/狂力/開光(agi/str/int_spi +3)/野性(`atk_speed_buff`)/奇門(`stealth_noncombat`)——單機冇連續移動速度系統、冇 fog-of-war/黑夜視野系統、冇屬性後天加成掛鈎位，做落去會等於新開一個子系統，記入 §4 留返有相關系統先接
  - 驗收：`run_war_beast.gd` 207 項全過（冇改動、純加新 hook）、`run_hud.gd` 4195/`run_sim.gd` 161/`run_char.gd` 80 全過；`--uitest` 129 項得返 2 個現有 flaky（掉落拾取，同呢個改動無關，之前 session 已記錄）
- [ ] **U14 建角面板正式化**：`create_panel.gd` 由 debug 版換做正式（三國群英傳M 風格揀職業/性別/初值分配）
- [x] **U15 記事「指引」頁**：`quest_panel.gd` 加第 5 個 tab「指引」（`_guide_section`）：靜態讀 `data/quests.json`（跳過 `hidden`）+ `data/quest_npcs.json` + `data/maps.json`，按 `TYPE_ORDER`（新手/職業特技/絕招/歷史/專長/義勇軍/結婚）列晒全部任務，每條顯示「接任務：NPC名（城池）」+ 條件（`_pre_summary`：等級/職業/義勇軍/性別/職業之一/屬性門檻）+ `preHint`；狀態（☆未接／●進行中／✓完成）由 `sim.view_quests()` 對返 id 標記；純查詢，唔碰 sim/存檔。傳聞 UI 留後（獨立 §4 項目，唔屬呢個 tab 範圍）
  - **規則（記入呢度，日後補任務要跟）**：以後喺 `data/quests.json` 新增任務，要確保 `giver` 喺 `quest_npcs.json` 有對應 NPC（`map` 欄要填）、非通用條件寫清楚 `preHint`；`type` 如果係新分類要加入 `quest_panel.gd` 嘅 `TYPE_LABEL`/`TYPE_ORDER`，等「指引」頁自動列到，唔使另開 UI
  - 驗收：`run_hud.gd` 4195/0 fail PASS；`--uitest` 待跑（同 U13 一樣預期得返舊有 2 個 flaky）
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
