# Spec 09 — 登用武將 NPC + LLM：應有 UI + 邏輯對照

> 用途：你逐項睇（應有咩 UI / 邏輯），去試，比 feedback。✅=已實作　🟡=部分　❌=未做。對應攻略 sy2_6_1~6（登用）、sy2_7_*（結婚）、sy2_8_5、sy3_5。
> 現況權威 = spec 09 + PLAN S09 + code。已做細步：S09a 居民化 / S09b 傳聞擴散 / S09c 特技 / S09d LLM 層 / S09e 結婚。
> 全部 UI 都係 `ui/panels/` 正式 Control（經「更多」選單 / 觸控 menu 開），唔係 debug 版。

## ⏸️ 進度暫停點（2026-09-29）

- **將軍令**：實作自始符合「後備憑證」——條件全合唔扣令；唔合但持令先扣（成功登用先扣）；考驗失敗唔扣。**唔使改 code**。
- **調查每日鎖**：非每日鎖 bug——成功登用後 15 日長鎖（`recruitLockUntil`）+「有同伴跟」先 lock；每日調查翌日解鎖（已加 `t_survey_daily_unlock` 回歸測試，`run_general` 88 scenarios fail 0）。
- **待用家**：同伴戰鬥指令：已 confirm 4 order + skillMode 正確（2026-09-29），唔補。傳聞大表 UI 有冇需要？結婚村 NPC 圖示（非阻塞）。

---

## 1. 居民 NPC（bot → 居民化，S09a）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 每城生 12~20 居民 | 進城睇到多個「居民」樣 (路人 NPC) | `add_residents()` 每城 `round(pop/30)` 夾 12~20，大城多 | ✅ 資料 + 生成 + `resident_view()` read-model |
| 居民有性格 5 維 | 對話/行為反映外向/友善/精明/勇猛/穩重 | `personality()` 5 維 0~1 | 🟡 已生成但**未驅動行為**（純 read-model，留 S09c/d） |
| 居民有理念 + 善惡(正) | — | `align:"good"` + 五理念 | ✅ |
| 居民有 role 5 種 | 商販/衛兵/村民/馬夫/朝廷官員，影響功能 | `pick_role()` 權重；`role` 欄 | 🟡 資料齊；**工作/對白腳本未分流**（`work` 欄未驅動） |
| 居民有日程（時辰活動） | 唔同時辰居民唔同位置 | `activity_at()` 12 時辰 → sleep/work/eat/home | 🟡 **只驅動「留城 / 出野區」**（`inTownActivities`）；逐 zone 工作點未細分 |
| 居民記憶表 + 好感 | 傾偈反應隨好感變 | `NpcMemory`（affinity/events/rumors/summary） | ✅ |
| 居民「滿意度/名聲」社交層 | — | spec §4 名聲層 | 🟡 傳聞已做；「名聲輸出」未整合（見 §2） |

⚠️ **手測**：每個新手城（許昌/襄陽/新野）居民數量 12~20、種類（村民多→官員少）、行去野區練功、血低返城客棧、時辰轉換時居民出城/返城。

---

## 2. 傳聞擴散 + 忠誠事件（S09b）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 目擊事件 → 居民記憶 | 事件無即時畫面，睇 NPC 後續對白 | `_witness_nearby()` + `NpcMemory.witness` | ✅ |
| 顯著事件 → 傳聞（殺善=−殺人魔 / 殺紅名=除害） | — | `rumor_kind_of()`（kindMap murder）+ `make_rumor` | ✅ |
| 同城即日揭示 / 跨城延遲 1~3 game 日 | 喺 B 城居民傾偈時提及 / 情報冊 | `_seed_rumor()` + `_rumor_daily()` + 城級池 + 獨立 SimRng | ✅ 邏輯；**UI 無「傳聞大表」**（只有竊聽情報冊 `rumor_panel`，睇返 ch.rumors） |
| 忠誠事件：玩家謀殺善 NPC → 義理念同伴忠誠 −15 | 同伴面板忠誠顯示跌 / 公告 | `_kill_bot` override（玩家先行出手計；自衛/紅名/其他理念唔扣） | ✅ |
| 忠誠 <30 子時走 / =0 即走 | 同伴列消失 + 公告 | `loyalty_verdict()` + `_recruit_daily` / `_loyalty_change` | ✅ |

⚠️ **手測**：A 城連續謀殺善居民 → 義理念同伴忠誠跌；殺紅名 / 自衛反殺唔扣；B 城居民隔日先提到你「出名」。忠誠 0 即走、<30 子時走。**冇 panel 直接顯示「全城傳聞名單」** — 有需要請反映。

---

## 3. 登用流程（武將 PK / 文官問答）

### 3.1 條件檢查
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 理念相合 5×3 + 出仕人人得 | 「調查」候選只顯示啱理念 | `ideology_ok()`（`IDEO_OK`） | ✅ |
| 唔可以登用高自己 10 級 | 候選剔走等級差太遠 | `level_ok()` gap=10 | ✅ |
| 頭銜限制（50 級以上 + 5 階） | 候選剔走頭銜唔夠 | `title_ok()` | ✅ |
| 將軍令無視條件、用完即消 | 候選顯示【持令】；用咗消失 | `pass_kind()` + `_consume_pass()` + `_has_order()`（背包+收集冊） | ✅ |
| 御賜金牌無視一切 + 唔受時辰 | 候選顯示【金牌】 | `_has_medal()` + `_pass_need()` + `candidates(free)` | ✅ |

### 3.2 流程（recruit_panel.gd）
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 「調查」每日 1 次 + 成功月封鎖 | **登用面板**「調查武將/調查文官」掣 | `cmd_recruit_survey()` + `survey_block()`（滾動 lock U16） | ✅ UI 有掣、有封鎖原因顯示 |
| 揀候選（武將/文官分池） | 候選列表（★Tier1/戰等/理念/持令/金牌/特技） | `candidates()` + `_order_cands()` | ✅ |
| 武將 = PK 擂台（HP=戰等×20，打到 0 制服） | 擂台怪喺身邊；面板顯示「擂台 PK 緊」；返去打/認輸 | `_arena_start/_arena_end` + `arena_def` + `damage` override | ✅ |
| 擂台輸 / 走甩 = 調查用咗 | 面板返「擂台輸咗，走人」 | `_recruit_tick()` + `_arena_end(false)` | ✅ |
| 文官 = 三國問答 10 題答啱 8 | 面板逐題顯示 A/B/C/D | `_quiz_start/_emit_quiz/recruit_quiz_view` + `quiz_pass` | ✅ |
| 錯多過 2 題即失敗 | — | `cmd_recruit_answer()`（`wrong > n-pass` 即 fail） | ✅ |
| 登用生效 30 game 日，到期子時離開 | 同伴面板「剩 N 日」 | `until_day()` = serveDays + `_recruit_daily` | ✅ |
| 玩家未定理念 → 只登得出仕 | 調查未定理念提示 | `ideology_ok("", ...)` | ✅ |

⚠️ **手測**：新手 `未定理念` 調查得唔得；武將 PK 打贏/輸/走甩；文官答啱 8/10；將軍令/金牌候選排頭 + 用後消失；成功登用月內調查封鎖、其餘日子正常。

---

## 4. 同伴（登用期內，recruit_panel 同伴頁）

### 4.1 戰鬥指令
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 主動攻擊 | 同伴面板「● 主動攻擊」 | `cmd_companion_order("active")` + `_hunt_target` | ✅ |
| 協助攻擊 | 「● 協助攻擊」 | `order=="assist"` → 打主公隻怪 / 幫手 | ✅ |
| 停止攻擊 | 「● 停止攻擊」 | `order=="stop"` | ✅ |
| 遠距跟隨 | 「● 遠距跟隨」 | `order=="follow"` `farFollow` | ✅ |
| 絕招/術法攻擊 | 「招式」開關（唔用/用絕招·術法） | `cmd_companion_skill_mode` + `_comp_skill`＋`skill_pick` | ✅ ⚠️ **偏離 spec（6 指令 vs 實作 4 order + 1 skillMode 開關）**：spec 原文「絕招/術法」獨立 2 指令，實作合併做 skillMode on/off + 自動揀絕招/術法。手測確認夾唔夾 3.3 用感 |
| 武將 AI（規則版） | 自動打怪/跟隨 | `_think_companion` + `_attacker_of` | ✅ |
| 武將用品（藥膳師） | 同伴面板「送補品」 | `cmd_companion_gift` + `tonics`（`30015` 等）| ✅ |

### 4.2 寶物（2 格）
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 贈與寶物，放咗攞唔返 | 同伴面板寶物格 + 贈與掣 | `cmd_companion_treasure` + `treasure_put` | ✅ |
| 同類高數值取代低（低消失） | 贈後提示「取代咗/消失」 | `treasure_put` return res | ✅ |
| 寶物加成（速度/兵量/物攻…） | 同伴面板顯示兵量/武材/軍略 + 屬性 | `treasure_bonus` + `_eff_attr`/`_jewel_bonus` | ✅ |
| 登用完跟武將走 | — | 同伴實體移除，寶物隨之 | ✅ |

### 4.3 內政協助 + 被動特技（S09c）
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 武將政治 | 冇直接 UI（數值 effect 睇官宅/營地完成度） | `pol_of` = round(智力×0.5) | ✅ |
| 內政協助加成（官宅內政/營地監督） | 官宅/營地面板完成度顯示 | `assist_bonus` + `_domestic_assist_bonus` + `_companion_pol_bonus` | ✅ |
| 生產專精 45~48（工作經驗倍率） | 人流面板下方無獨立顯示 | `work_exp_mult` + `_work_exp_mult`（`sim_econ._work_gain` 接） | ✅ |
| 進階專精 49~51（成功率加成） | — | `craft_rate_add` + `_craft_rate_add`（`cmd_craft` 接） | ✅ |
| 商才 43（買賣價） | — | `trade_mul` + `_companion_trade_mul`（buy/sell 接） | ✅ |
| 22 職業特技（proximity：冷卻/消耗 ×0.5） | 同伴面板「職業特技（同伴隨行加成）」 | `class_skill_mul` + `_companion_class_skill_mul`（潛行/透視/超渡接） | ✅ |

### 4.4 主動特技 21/32/38
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 21 無限遁地（主公+同伴傳送最近城池） | 同伴面板「遁地」掣 | `cmd_companion_skill("burrow")` + `_comp_burrow` + `_nearest_city_map` | ✅ |
| 32 挑釁（tauntRange 怪仇恨轉同伴） | 「挑釁」掣 | `_comp_taunt`（`tauntRange`） | ✅ |
| 38 急救（auraRange 內回主公 HP×30%） | 「急救」掣 | `_comp_heal` + `heal_amount` | ✅ |
| 冷卻顯示 / 禁用 | 掣顯示「（冷卻 Ns）」+ disabled | `active_block` + `activeCd` | ✅ |

⚠️ **手測**：同伴（左慈/于吉→遁地、張郃/魏延/顏良→挑釁、華佗→急救）三大主動技全部落指令有冇反應 + 冷卻；22 職業特技冷卻/消耗 ×0.5（潛行/透視/超渡）有冇反映；官宅/營地/買賣/生產加成數值。

---

## 5. LLM 整合（S09d）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 動作白名單 7 個 | 對話 log | `RulesLlm.actions`（greet/warn/ignore/acceptQuest/hint/rumor/refuse） | ✅ |
| LLM 只揀動作+句，唔改數值 | — | `parse_response`（剝數值欄）+ `effect_of` 唯一數值來源 | ✅（測試斷言） |
| 每日反思 → 記憶摘要/目標 | 冇 UI 睇 mem.summary/goal | `_llm_reflect_daily` + `RulesLlm.template_summary`/`goal_of` + `cmd_llm_summary` | ✅ 邏輯；**read-model 未驅動行為（目標冇用）** |
| Tier 政策（1 必 LLM / 2 mixed / 3 模板） | — | `tier_mode/tier_uses_llm`（Tier2 = 15% 被動偶發） | ✅ |
| 無 key / 失敗 / 預算完 → 模板後備 | 離線照玩 | `_llm_offer` + `NpcBrainLlm.decide` fallback | ✅ |
| LLM 設定（key/model/啟用）｜**U11** | **LLM 設定面板（更多→LLM 設定/對話）頁 0** key/model placeholder + 儲存/啟用 | `LlmClient`（user://llm.cfg）+ `cmd_llm_config` | ✅ |
| 用量顯示 / 錯誤 | LLM 設定面板頁 0「今日用量」「上次錯誤」 | `llm_view`（used/budget/lastError） | ✅ |
| 對話記錄 | LLM 面板頁 1 倒序顯示 | `main.llm_log`（npc_say + llm） | ✅ |
| 真 HTTPRequest 接線 | — | `main._on_llm_request`（加 key header + HTTPRequest POST + 回填） | ✅ |

⚠️ **手測**：LLM 面板頁 0 填 key/model → 啟用 → 城內同 Tier1 武將 / 居民傾偈 → 頁 1 睇對話；冇 key 照玩（模板句）；`llm_action`（acceptQuest/hint）有冇觸發後續（見「已知問題」）。Tier2（居民）因 15% 機率 + cooldown 1200 tick，**要傾好多鑊先見**。

---

## 6. 結婚（S09e，marriage_panel.gd）

| 步驟 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 御賜函任務（男女各一） | herequest_panel（quests.json `marry_letter_m/f`） | `letter_for` + `quest_pre.gender` | ✅ |
| 求婚（好感鎖 90 = 同伴忠誠） | 結婚面板頁 0「步驟 1：向同伴求婚」 | `cmd_marry_propose` + `propose_block` | ✅ |
| 喜餅 4 價位（買→開→分） | 頁 0「步驟 2」買/開×/分×掣 | `buy_cake/open_cake/share_cake` + `contents`（點心回 HP/MP/SP） | ✅ |
| 分餅 → 點心入袋 + 全城居民好感 +10 + 婚慶 1 日 | 頁 0「婚慶氛圍」 | `_spread_festive` + `world.marry.festive` | ✅ |
| 預約禮堂 + 主婚人（朝廷官員） | 頁 0「步驟 3：預約禮堂」 | `cmd_marry_book` + `book_block` | ✅ |
| 婚禮 | 頁 0「步驟 4：舉行婚禮」 | `cmd_marry_hold` | ✅ |
| 婚戒無限召喚伴侶（耗 50 SP） | 配偶頁「召喚配偶到身邊（−50 SP）」 | `cmd_marry_summon` + `_spawn_spouse` | ✅ |
| 配偶頁（屬性欄） | 頁 1 配偶資料/生日/理念/結婚年數 | `marry_view` spouse | ✅ |
| 叮嚀留言（本地存） | 配偶頁留言盒 + 儲存 | `cmd_marry_message` + `message_max_len` | ✅ |
| 離婚（斷情絕愛郎 50 萬兩 + 回收戒指） | 配偶頁「離婚」 | `cmd_marry_divorce` + `divorce_block` | ✅ |
| 配偶唔會登用期滿 / 低忠誠離開 / 唔可免職 | — | `_recruit_daily` skip married + `marry_hold` until=0 + `cmd_companion_dismiss` override | ✅ |

⚠️ **手測**：御賜函任務 → 求婚（好感 90）→ 買/開/分餅 → 預約 → 婚禮 → 拎婚戒 → 配偶頁 → 召喚 → 留言 → 離婚。**結婚村 4 NPC 冇專屬圖示**（落許昌城內，以一般 NPC 顯示）— 非阻塞，可反映。

---

## 你嘅 feedback 重點（Spec 09）
1. 居民數量/種類/日程/出城練功/血低返城掂唔掂；性格/role 未分流行為係咪可接受
2. 登用流程（調查→候選→PK/問答）順唔順；將軍令/金牌排頭 + 用後消失
3. **戰鬥指令**：4 order + skillMode 開關 = 用家 2026-09-29 confirm 正確設計（非偏離）
4. 同伴 3 大主動技（遁地/挑釁/急救）+ 22 職業特技加成 + 內政/買賣/生產加成
5. 忠誠增減（殺善居民 −15 / 送禮 + / 期滿 / 低忠誠走）公告有冇
6. LLM：設定頁易用；冇 key 離線照玩；Tier2 居民 15% 機率傾好多鑊先見 — 機率啱唔啱
7. 結婚全套流程 + 配偶頁；結婚村 NPC 圖示缺失

## 手測 feedback 跟進（2026 驗證）

### 1. 調查「一日過去後仍不能重新調查」
**結論：唔係每日鎖 bug，正常運作。** 有 2 個唔同嘅封鎖，容易混淆：
- **每日鎖** `surveyDay`：`cmd_recruit_survey` 寫 `rec.surveyDay = day`，第二日 `survey_block` 檢查 `surveyDay == day` 就唔同值 → 解鎖。呢段冇 bug。
- **登用後 15 日鎖** `recruitLockUntil`：`_recruit_success` 寫 `day + recruitLockDays(15)`。成功登用後（唔理你係咪仲有同伴），連續 15 個 game 日 `survey_block` 會話「登用鎖緊，N 日後先可以再調查」。
- 另：**有同伴跟緊你** 都唔可以再調查（`cmd_recruit_survey`：`comp != 0` → 「已經有人才跟緊你」）。

⚠️ 判斷：唔係 bug，但有三點值得 review：
1. `recruitLockDays=15` = `serveDays=15` — 即同伴服役完嗰日先解鎖，設計上自洽，但 spec 原文「成功嗰個月封鎖」係一個月（≈30 日），實作減半到 15 日（U16 決定）。啱唔啱用家期待？
2. 玩家未成功登用過，淨係調查（fail）之後，第二日一定解到（fail 唔設 recruitLockUntil）。若你遇到「fail 之後都鎖」，嗰個先係真 bug —— 請提供重現步驟。
3. 訊息「登用鎖緊 N 日」同「今日已經調查過」係唔同原因；面板有冇令玩家分唔清楚？

### 2. 將軍令有無正確作用？
**結論：實作符合用家設計語義 —— 將軍令係「後備憑證」，正常登用唔扣。**
- ✅ **bypass**：`_pass_need`：條件全部合（`RulesRecruit.check` 空）＋時辰啱→回 `""`；唔合→先 `pass_kind`（將軍令/金牌）決定憑證。
- ✅ **正常合唔扣**：`_pass_need` 回 `""` → `cmd_recruit_pick` `pn==""` → `rec.erase("pass")` → `_recruit_success` 嘅 `_consume_pass` 拎 `ps.is_empty()` → return，**唔扣令**。
- ✅ **唔合先用令**：理念/等級唔合但持令 → `_pass_need` 回 `"order"` → `cmd_recruit_pick` 寫 `rec.pass` → 成功登用 `_consume_pass` → `_order_consume`（背包先，冇就收集冊）扣令。
- ✅ **考驗失敗唔扣**：`_recruit_fail` 只 `erase(pass)`，令牌保留（【自訂】）。
- ⚠️ **語意對照攻略**：攻略原文「將軍令用完即消」係咪「必消」/「期滿消」唔清楚；**用家澄清** = 「理念等睇埋都合就唔使扣，得理念/等級唔合先靠令牌→扣」。實作正好係咁。
- 🟡 **測試缺口（已補）**：`run_general.gd` 原有 cover「唔合＋持令→出現候選/成功扣令」同「失敗唔扣」；今次新加 `t_survey_daily_unlock`（每日鎖翌日解鎖回歸）+ 註明「條件夠→唔使用令（pass 空）」語意。牆「條件合→普通登用唔扣」未有獨立 assert，靠 `_pass_need` 回 `""` 路徑隱性保障。

### 3.（跟進）調查「未成功就鎖第二日」
**用家答：唔肯定，要再試 → 已加自動回歸測試確認。** 新 `t_survey_daily_unlock` 驗證：掘完→當日受阻；行一日→唔再「今日已經調查過」→可再掘。隨 RNG 望「每日鎖正常」。長鎖 = 登用成功嘅 15 日 `recruitLockUntil`（用家選「15 日 OK 維持」）。若仍遇「未成功都鎖」，先驗證係咪撞咗 15 日鎖 / 有同伴，再報重現步驟。

## 已知自動測試問題（相關）
- **`tests/run_llm.gd`（113 項）**：邏輯/請求形狀/client mock 全假；**冇 UI 面板測試** — LLM 設定頁（key 顯示/隱藏、用量顯示）靠手測。
- **`tests/run_marry.gd`（127 項）**：邏輯全假；**冇 marriage_panel UI 測試** — 求婚/分餅/離婚按鈕流程靠手測。
- **`tests/run_recruit.gd` 唔存在**：登用流程（擂台/問答/候選/將軍令）冇專屬自動測試檔，靠 `run_general.gd`（常規 draft）間接 + 手測。
- **傳聞 `run_rumor.gd`（54 項）**：驗證跨城延遲 + 忠誠事件；但「居民對白提及傳聞」冇測試（UI 觀察位）。
- **LLM 真實請求**：測試用 mock，**唔碰網絡**；真 HTTPRequest 路徑（`_on_llm_request`）冇自動覆蓋 — OpenRouter 實際連線 + JSON schema 回應靠手測，出錯會喺 LLM 面板「上次錯誤」顯示。
- **Tier2 居民 15% + cooldown 1200 tick**：自動測試直接砌 `_llm_talk`；真實玩家要傾好多鑊先觸發 → 手測易誤報「LLM 冇反應」。
- **「每日反思摘要」**：`cmd_llm_summary` 只寫 `mem.summary/goal`，**未驅動任何行為**（目標未接）→ 自動測試唔會出錯，但功能上係半製成品。