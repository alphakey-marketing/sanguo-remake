# Spec 09 — NPC / 登用 / 武將同伴

> 對應攻略: sy1_1_2(理念)、sy2_6_1~6(登用全頁)、sy2_7_*(結婚)、sy2_8_5(制度)、sy3_5(歷史任務→將軍令)
> 原始資料: `D:\Download\sanguo\extracted\text\general_npc.csv`(1261 武將: 名/武力/智力/9 技能)、`general_skills.csv`、`Npc_table.tsv`(hp/mp/atk)、`recruitinfo.txt`(官方新手說明)
> 現有實作: `sim/npc_brain.gd`(規則版決策)、`rules/npc_memory.gd`、`bot_sys.gd`(居民)、Step 6 未做 LLM
> **現狀 (2026-09-26, S09d)**: 居民化（S09a）+ 傳聞擴散／忠誠事件（S09b）+ 被動特技（S09c-a）+ 主動特技（S09c-b）+ LLM 層（S09d）完成 —— `general_skills.json` `impl:true`：39~43、45~51 被動（內政協助 `domesticAssist` / 商才 `tradeBuyMul·tradeSellMul` / 生產 `workExpAdd` / 進階 `craftRateAdd`）+ `cfg.assist`（政治 = round(智力×0.5)）；21 無限遁地 / 32 挑釁 / 38 急救（`eff.active` + 冷卻 `eff.cd`）+ 22 職業特技（`classSkillCdMul`/`classSkillCostMul` proximity 被動）。`rules/general.gd` `pol_of`/`assist_bonus`/`work_exp_mult`/`craft_rate_add`/`trade_mul` + `active_kind`/`active_cd`/`active_block`/`heal_amount`/`taunt_range`/`class_skill_mul`。`sim_core` 空 hook（`_companion_pol_bonus`/`_work_exp_mult`/`_craft_rate_add`/`_companion_trade_mul`/`_companion_class_skill_mul`）由 `sim_recruit` 覆寫；官宅內政／營地內政／營地監督／工作經驗／進階成功率／買賣價／潛行·透視·超渡冷卻消耗全部接同伴特技；`sim_recruit.cmd_companion_skill(id,kind)`（burrow/taunt/heal）。測試 `tests/run_residents.gd`、`tests/run_rumor.gd`、`tests/run_general.gd`（+F/G 群組）。尚欠：鑑定 44（無系統）、國戰類 23~37/53~70（S10）。LLM 層（S09d）已接：新 `rules/llm.gd`（動作白名單/OpenRouter 請求/回應解析剝數值/`effect_of` 唯一數值來源/反思摘要純函數）+ `sim/npc_brain_llm.gd`（同 `NpcBrain.decide` 介面）+ `sim/llm_client.gd`（`user://llm.cfg` 存 key、mock transport、`http_transport`）+ `data/llm.json`；sim_core `cmd_llm_config`/`cmd_llm_reply`/`cmd_llm_summary`/`llm_view`/`_llm_reflect_daily`（每日反思寫 `mem.summary`/`mem.goal`），Tier1 武將（`cmd_general_talk`）+ Tier2 居民偶發先接，無 key/失敗/預算完 → 模板後備；測試 `tests/run_llm.gd`（mock、唔碰網絡）。真 HTTPRequest/設定頁/對話顯示 = UI 欠債；`acceptQuest`/摘要驅動行為留後續。結婚（S09e）完成：`rules/marry.gd` + `sim/sim_marry.gd` + `data/marry.json`（御賜函任務 2 條 + 喜餅/開餅盒/分餅 + 禮堂/主婚人/婚禮 + 婚戒召喚 50 SP + 配偶頁/叮嚀/離婚 50 萬兩）；對象 = 登用武將同伴（好感鎖 90+ = 同伴忠誠）；婚禮面板 + 配偶頁 UI = 欠債。
> 【原】= 攻略明文；【自訂】= 自己設計。

## 1. 居民 NPC（現有 bot → 居民化）

`data/residents.json`（由 bot 升級）：名字/性格/理念/日程（各時辰去邊）/喜好/商店（商販係居民）/好感表/記憶表冚唪唥已有。

> **實裝 (S09a)**：`residents.json` = `cfg`（`minPerCity:12`/`maxPerCity:20`/`popPerResident:30`/`borderPop:350`/`personalityDims` 5 維/`personalityMax:10`/`ideologies` 5 個/`schedule` 12 時辰）+ `roles` 5 種（villager/merchant/guard/stableman/official，`weight`+`work`+`align`）+ `cities`（10 城 → `homeZone`）+ `names`（姓氏/名字池）。`rules/resident.gd` 純函數；`sim.add_residents()` 每城生 12~20 人（`round(pop/30)` 夾 12~20）；`ch` 存 `resident/role/personality/align/homeCity/homeZone`；`resident_view()` read-model。日程暫時只出 read-model，未驅動行動（留 S09c/S09d）。

| 欄位 | 說明 |
|---|---|
| personality（5 維） | 外向/友善/精明/勇猛/穩重 0~1 |
| schedule | 每時辰目標 zone（晨去工作區、午去食飯、晚返屋企） |
| alignment | 居民 = 正（300+ 檔） |
| role | 商販/衛兵/村民/馬夫/朝廷官員…（影響對話腳本同功能） |

- NPC 數量控制：每城 12~20 名（大城多）；目擊/傳聞已實作（`_witness_nearby`，WITNESS_RANGE=8）。

## 2. 武將資料導入（用解咗嘅表）

- `general_npc.csv` → `data/generals.json`；每武將：
  - 名（Big5 已解）、武力值（≈f101_str）、智力值（≈f116_int）、9 個技能 (skill_id:lv)
  - hp/mp/atk 由 `Npc_table.tsv` join（曹操 112/80/133）
  - 理念：由 `recruitinfo` 冇現成 → **第 5 版任務先定**：開幕預設表（冀州=霸權、荊襄=治國/隱遁…）+ 參數可調
  - 等級：武將戰等（攻略 20 級前登用表有：蔡邕 6 / 郭嘉 20 / 劉璋 20…）→ 現有一般武將按武力/智力映射 1~100 級（武力 140 ≈ 張飛 = 80 檔）
  - 友善度/特技（general_skills.csv 對照「武將特技 70 項」）
- 篩選：豫荊相關武將 Tier1（10~20 人：曹操/關羽/張飛/劉備/孫堅/荀彧/郭嘉…）+ 其餘 1261 人全量留表（登用池）。

## 3. 登用系統（【原】sy2_6_1~6）

### 3.1 條件

| 條件 | 規則【原】 |
|---|---|
| 理念相合 | 義理→{義理,霸權,治國}；霸權→{霸權,義理,權謀}；權謀→{權謀,霸權,隱遁}；隱遁→{隱遁,權謀,治國}；治國→{治國,隱遁,義理}；全部人都登用得到「出仕」理念武將（600+） |
| 等級 | 唔可以登用比自己武功高 10 級嘅武將 |
| 頭銜 | 50 級以上人才：玩家頭銜唔可以比人才低 5 階以上 |
| 將軍令 | 有該人才將軍令 = 無視理念/等級/頭銜限制（用完即消【原】） |
| 御賜金牌 | 無視一切 + 可登用城主搜索/子午時武將【原】→ 金牌 = 稀有任務獎勵 |

- 每月最多登用幾多？【原】調查成功嗰個月唔用得調查（即一個月最多 1 位）。

### 3.2 登用流程

1. 調查指令：城內使用（每日 1 次【原】；成功嗰個月封鎖）→ 揀「武將登用」或「文官登用」：顯示候選池（玩家等級 ±10 檔、理念相合、出現喺城內嗰批）
2. **武將 = PK 擂台**【原】：打贏（武將 HP 30% 制？設計：擂台戰 HP = 武將戰等×20，唔會打死——打到 0 算制服；玩家輸 → 武將走人，調查算用咗）
3. **文官 = 三國問答**【原】：10 題（題庫 `data/quiz_generals.json`，答啱 8/10 過關）
4. 登用生效：**30 game 日**【原】；到期子時 0 刻離開；期間：武將 = 同伴（戰鬥 + 內政）

### 3.3 武將同伴（登用期內）

- 戰鬥指令 6 種【原】：主動攻擊（自動搵怪）/協助攻擊（打玩家隻怪）/絕招攻擊/術法攻擊（MP/SP 唔夠自動轉普通攻擊【原】）/停止攻擊/遠距跟隨
- 武將 AI：完全規則版（現有 `_think_mob` 擴充）→ Tier1 武將對白用 LLM（Step 6）
- 武將用品：藥膳師 NPC（許昌市集【原】）買武將補品；玩家 `cmd_use_item` 對準武將就用
- **贈與寶物**（武將寶物 2 格【原】）：速度之石×5種/兵量之石（帶兵 7000）/物攻之石×6/物防之石×3/術攻之石×6/術防之石×3/武材之石×5/軍略之石×5 —— 入咗寶物唔可以攞返，登用完跟武將走【原】！同類別高數值取代低數值（低嘅消失）【原】
- 內政協助：武將屬性（政治）加入官宅工作/營地監督完成度
  - **實裝 (S09c-a)**：政治【自訂】= round(智力×0.5)（generals 表冇政治）；加成 = 政治/200 + 內政特技 `domesticAssist`（39 屯田/40 築城/41 治水/42 開墾 各 +0.2），封頂 1.0；營地監督完成度 = `RulesCamp.supervise_points` 政治改用主公 + 同伴政治。同伴跟住主公即生效（唔限距離，同政才/辯才一致）。
- 帶兵：登用武將喺國戰 = 第四部隊（兵力=武將頭銜帶兵，≤7000）【原】；國戰未完登用時間到 → 打完先走【原】

### 3.4 武將特技

- general_skills.csv（1261 武將 × 9 技能）+ 攻略「70 項特技」：每刻恢復 HP / 發話唔扣飲水度 / 無限遁地 / 使用職業特技… → skill_id 對照表 `data/general_skills.json`；特技效果逐項規則化（大部分 = passive buff，容易做）。
  - **實裝 (S09c-a)**：被動 39~43、45~51（見 §3.3 內政協助 + 下表）。
  - **實裝 (S09c-b)**：主動 21 無限遁地（`eff {active:burrow,cd:0}`，主公+同伴即時返最近城池）、32 挑釁（`{active:taunt,tauntRange:6,cd:600}`，同伴附近怪仇恨轉向同伴）、38 急救（`{active:heal,healPct:0.3,cd:1200}`，同伴 auraRange 內即回主公 HP）；22 職業特技（`{classSkillCdMul:0.5,classSkillCostMul:0.5}`，同伴同圖 auraRange 內 → 主公職業特技冷卻/消耗 ×0.5，proximity 被動）。指令 = `sim_recruit.cmd_companion_skill(id, kind)`（kind = burrow/taunt/heal）；冷卻存同伴實體 `gen.activeCd`。`44 鑑定` 冇鑑定系統、國戰類 23~37/53~70 未做（PLAN §4 / S10）。新特技全部經 `pin` 指派（唔入 `drawPool`，依 S07d 凍結慣例）。

## 4. NPC 好感 / 忠誠（規則層，已實作 + 擴充）

- 好感：−100~+100（`NpcMemory`）；觸發：打招呼 +1、目擊殺怪（善 +3/惡 −5 按殺者善惡反轉，已實作）、任務幫過 +20、送禮 +（禮物價值/100）、打交 −20、結婚 +50
- **忠誠（武將同伴專用）**：0~100；影響：行為（你殺善 NPC → 義理念武將忠誠 −15）、待遇（畀寶物/補品 +）、理念一致度（初始 ±）；忠誠 <30 → 會離開；=0 → 即刻走（公告）
- 傳聞擴散（**S09b 實裝**）：目擊事件 → NPC 記憶（`NpcMemory.witness` + `add_rumor`）→ 每日「反思」批次（`_rumor_daily`：城級傳聞池，同城即日、跨城延遲 1~3 game 日）→ 鄰居之間交換傳聞；A 城殺人魔名聲會傳到 B 城（延遲 1~3 game 日）。**單機化**：用城級池做等價可觀察效果（唔逐個 NPC 兩兩交換）；LLM 摘要留 S09d。
- 忠誠事件（**S09b 實裝**）：玩家先行出手謀殺善 NPC → 義理念同伴忠誠 −15（`generals.json` cfg.loyalty `badNpcKill`/`badNpcKillIdeo`）；自衛反殺/殺紅名/其他理念唔扣；忠誠 0~100、<30 子時走、=0 即刻走 沿用現有。
- NPC 態度層次：好感(微觀) → 善惡(鉅觀) → 名聲(社交) → 理念(結構)：任務可得/買價/衛兵/登用條件各睇對應層

## 5. LLM 整合（Step 6 設計基準，唔變）

> **實裝 (S09d, leg 19)**：`data/llm.json`（endpoint/model/models/temperature/maxTokens/7 動作白名單/tiers 1=llm・2=mixed 15%・3=template/cooldownTicks/budget perDay 40・reflectPerDay 8/reflect/ideologyStyle/responseFormat json_schema）。`rules/llm.gd` 純函數：`prompt_messages`/`request_body`/`build_request`/`build_reflect_request`/`parse_response`（剝 code fence、非白名單→ignore、**扔掉所有數值欄**）/`parse_summary`/`effect_of`（greet 好感 +1，其餘 0 → 數值唯一來源）/`template_summary`/`goal_of`/Tier・冷卻・預算 helper。`sim/npc_brain_llm.gd` 同 `NpcBrain.decide(ctx,pick_idx)` 介面 + `decide_with`。`sim/llm_client.gd` 存 key（`user://llm.cfg`，唔入存檔/log）+ mock transport + `http_transport(http)`。sim_core：發 `llm_request` 事件（規則層砌好 body，冇 key）→ 客戶端回填 `cmd_llm_reply`/`cmd_llm_summary`；`state.llm`（enabled/model/used/cd，唔含 key）；每日反思先寫規則模板摘要，LLM 回覆再覆蓋。

- `npc_brain.gd` 已有 `decide(ctx, pick_idx)` 純函數介面；LLM 版 = 同一介面新實作（`npc_brain_llm.gd`）
- 揀動作白名單：greet/warn/ignore/acceptQuest/hint/rumor/refuse——LLM 只揀 + 生成句子，數值全由規則層改
- 每日反思批次：讀記憶表 → 出摘要（存 `mem.summary`）→ 更新目標；冷卻/預算/token 控制（設定檔）
- Tier1 武將（10~20 人）先接 LLM；居民 Tier2 偶發 + 模板；路人 Tier3 純模板
- 無 key / 失敗 / 預算完 → 模板後備（離線可玩）
- 布倫：`ch.ideology` + NPC 理念 → 對話風格（霸權=威嚴、隱遁=寡言、治國=民生話題）

## 6. 結婚（【原】sy2_7_*；對象 = 武將同伴）

流程（Spec 06 §9）：御賜函任務（男女各一）→ 喜餅（禮餅商 4 價位→開餅盒師傅變成雙雙對對餅等）→ 分送 NPC 親友（每款餅 = 點心組合，回 HP/MP/SP 表數據化）→ 預約禮堂 + 主婚人（朝廷官員 NPC）→ 婚禮 → 男/女婚戒（無限召喚伴侶，耗 50 SP）。
效果：配偶頁籤（屬性欄【原】）；伴侶好感鎖 90+；叮嚀留言（本地存）；離婚（斷情絕愛郎：50 萬兩，戒指回收）。
- **實作 (S09e)**：`data/marry.json`（好感鎖 90/召喚 50 SP/離婚 50 萬兩/婚戒 23030/男 51627 女 51628 御賜函/4 價位喜餅 buy→open→contents/結婚村 4 NPC）；`rules/marry.gd` 純函數（性別御賜函/喜餅對照/內容物/求婚·預約·婚禮·離婚·召喚條件）；`sim/sim_marry.gd` `cmd_marry_propose`/`buy_cake`/`open_cake`/`share_cake`/`book`/`hold`/`summon`/`message`/`divorce` + `marry_view` read-model；`rules/quest.gd` +`pre.gender`；`sim_recruit._recruit_daily` 配偶唔期滿/低忠誠唔走；已婚同伴唔可免職。婚禮面板/配偶頁 UI = 欠債。

## 7. 測試要點
- 理念相合表全 5×3 組合 + 「出仕」全部人
- 登用限制：等級 ±10、頭銜 5 階、將軍令無視、御賜金牌
- 調查：每日 1 次；成功嗰個月封印；PK 擂台輸 = 用咗調查
- 文官問答 8/10 過關；30 日子時離開；用物品；寶物 2 格/同類覆蓋
- 忠誠增減規則；<30 離開
- 武將特技效果（skill_id 對照表）
- 傳聞擴散延遲（種子 RNG）
- LLM mock：白名單外動作拒絕、數值唔准直接改（斷言）