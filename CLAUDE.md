# UAT 修正指引（2026-09-29）

> 目的：逐份 spec（01~12）跟住 `docs/uat/specNN_*.md` 累積落嚟嘅用家 feedback / comment，逐一落 code 修正。
> 權威次序：**用家親口 confirm 咗嘅 feedback 最優先** → 其次 spec 檔「擬改清單」/「feedback 重點」→ 最後 subsession 自發審查建議（**未經用家 confirm，要問先用**）。
> 每份 spec 檔都有「應有 UI / 應有邏輯 / 現況(✅🟡❌)」三欄 + feedback 重點 + 已知自動測試問題。改完 → `sh tools/run_tests.sh` 全 PASS 先剔格。

---

## 0. 緊要事（改之前必讀）

- **用家親口 confirm 過嘅 = 得 Spec 01 嘅 F1~F8**。其餘所有「擬改清單」（`docs/PLAN.md` §4 後 T-01~T-11）同各 subsession 自發建議，**全部未經用家確認**——要逐項向用家問（用 `ask_user` 一齊）先用得，唔好自己估。
- 規格權威：`docs/spec/01~12_*.md`。改機制前先睇；spec 同 code 唔同 → 以 spec 為準，除非 spec 標【自訂】而 code 已有測試（咁改 spec 記錄）。
- **生成檔唔好手改**：`monsters.json` 掉落 / `recipes.json` / `generals.json` / `titles.json`（改導入器再跑）。
- 每份 spec 檔本身都係 UAT 記錄：入面「你嘅 feedback 重點」「用家 Feedback」「擬改清單」段 = 逐項跟住改。

---

## 1. 通用修正流程（每份 spec 都用）

1. 開 `docs/uat/specNN_*.md` 讀晒「feedback 重點 / 用家 Feedback / 擬改清單」段。
2. 將每一項 map 去對應 spec 檔（`docs/spec/NN_*.md`）section + 相關 code。
3. **未確認項先問，唔好直接改**：`ask_user` 一次過問晒該 spec 所有「待定/待決」位（見各檔標 🟡/❌/待定）。
4. 用家答 → 落 code 修正。每細步：rules 純函數 + 測試 → sim 指令 + 場景測試 → `run_tests.sh`。
5. 改完 update：`docs/uat/specNN_*.md` 剔格/標狀態、`docs/PLAN.md` §1 現況、`docs/spec/NN_*.md` 頂「現狀」。
6. 所有改動要 `sh tools/run_tests.sh` 全 PASS 先剔格（任何 leg FAIL 都唔可以當完成）。

---

## 2. Spec 01 — 角色成長（用家已 confirm，最優先）

用家親口 feedback（F1~F8，全部確認），記錄喺 `docs/uat/spec01_角色成長.md` §0 + §12。逐項改：

| ID | 改動 | code 位置參考 | 狀態 |
|---|---|---|---|
| F1 | **稱號** → 唔再建角輸入，改為**完成事件獎勵解鎖** | `create_panel` 稱號輸入移除 / `rules/title.gd` 獎勵 mbox + `sim_office`・`sim_quest` 掛鉤 | ✅ 已做（2026-09-29，待用家手測） |
| F2 | **生日** → 唔問玩家（列出：欄位 `birthMonth/birthDay` + 建角 UI + 福日 exp 一齊刪；舊檔遷移清走） | `rules/stats.gd `birthday_exp_mult` / `sim_combat.gd` 福日 / `create_panel` / save 遷移 | ✅ 已做（2026-09-29，待用家手測） |
| F3 | **職業** → 建角加**獨立職業介紹頁**（6 職，copy 附圖文字，預留畫圖位）；**臉譜保留** | `create_panel` 職業頁 → 獨立頁 / `classes.json` 描述 | ✅ 已做（2026-09-29，待用家手測） |
| F4 | **政治** → 私塾（消耗 SP/MP）+ **歷史任務獎「政治經驗值」**（如陳宮任務）；高階任務（如《太平要術》）設定**門檻**（政治/魅力/等級 各 10+） | `sim_office` 官令 pol / `sim_quest` 歷史任務獎勵 / 任務門檻檢查 | ✅ 已做（2026-09-29，待用家手測） |
| F5 | **魅力** → **影響登用文官成功率 + 最低要求**（登用成敗 = 魅力+政治+等級+頭銜+親密度） | `rules/recruit.gd` / `sim_recruit.gd` 成功率公式 | ✅ 已做（2026-09-29，待用家手測） |
| F6 | **二/三轉** → **六職業全部**轉職考試 + 任務（唔止義士） | `rules/class.gd` / `sim_quest` 各職轉職任務 | ✅ 已做（2026-09-29，待用家手測） |
| F7 | **專長** → 加**學習任務** + 測試「成功使用專長」 | `rules/expert.gd` / `sim_quest` / `run_char.gd` | ✅ 已做（2026-09-29，待用家手測） |
| F8 | **練兵場** → 直接加 **EXP**（取代「歷練每10下次升4屬+1」）；新手任務 `newbie_training` 獎勵 `lilian:10` 改做 exp | `sim_core` 練兵場 / `quests.json` newbie_training | ✅ 已做（2026-09-29，待用家手測） |

> 落 code 前須用家 confirm（見 §0）：練兵場「歷練」系統成唔成個取消？新手任務獎 exp 幾多？生日欄位舊檔點遷移？職業介紹頁每職畫圖位 size/格式？

---

## 3. Spec 02 — 戰鬥術法

記錄喺 `docs/uat/spec02_戰鬥術法.md`（feedback 重點 9 條 + 擬改清單 S2-1~S2-14）。subsession 已核實：
- ✅ **已做**（唔使改，淨係要人手驗證）：T-08 武器限定職業（`_weapon_ok` 全面）、T-09 六職絕招對應武器（`cmd_use_ultimate` weaponCat）、T-11 物/術防分開（`def_mult`/`spell_def_mult`）
- 🟡 **要改**（待用家 confirm）：T-04 武器欄顯示「可裝上」、T-06 術法怪吟唱地上紅圈（樣式未定）、T-07 開鎖加隨機寶箱+任務寶箱、T-10 屬性欄顯示所裝寶石
- 🟡 待核實：UAT-009 卸下（疑因未裝備）、UAT-010/011 掉落拾取（用家手測無問題 → 可能誤判）
- ❌ 絕招任務鏈習得 → 留 S06d（而家用 `cmd_debug_learn` 頂住）

---

## 4. Spec 03 — 善惡死亡

記錄喺 `docs/uat/spec03_善惡死亡.md`。重點（subsession 已核實 + 用家回應）：
- **天譴唔傳送**：用家確認 code 現況啱（淨扣 HP 唔傳送）→ **改 spec §3**；順手揪出 `main.gd:569` 日誌文案仍寫「被傳返客棧」→ 誤導要改
- **死亡結算「無顯示」**：正常死亡入「倒地」畫面（淨倒數+掣），扣經驗/跌物/耐久% 內容埋喺日誌第一行 → 改善：倒地畫面都應顯示死亡報
- **攻擊居民長按 menu**：`_handle_long_press` 淨掃 `bot` 居民，武將/怪唔出 menu → 測試指示「長按居民」。若真係長按居民都冇 → 真 bug
- **城捕快無巡邏**：= 已知 UAT-001~003（`rules/guard.gd` float bug + `add_guards` spawn 只限有客棧嘅城）

---

## 5. Spec 04 — 怪物地圖

記錄喺 `docs/uat/spec04_怪物地圖.md`。重點：
- **掉落物拾取** = UAT-010/011（用家手測無問題，懷疑測試舊結構 → 核實再定）
- `gen_battles.py` / `gen_scenes.py` 有 `--check` 但**未接入 `run_tests.sh`** → 建議補
- 6 場戰役 + 桃花渡/七彩奪寶陣 2 場景 = ✅ playable；其餘 5 場景（通天關/黑山寨/安定/雪山/異族禁地）留後續批次

---

## 6. Spec 05 — 生產經濟

記錄喺 `docs/uat/spec05_生產經濟.md`。重點：
- ✅ 6 初階+5 進階+2318 配方、產出 1~2 件、天災停進貨、大宗師
- 🟡 **城際貿易（搬運跨城賣）未做**（S05a 偏離留後續）——待用家 confirm 做唔做
- 🟡 御賜工具 / 白晝之珠 = 過渡兌換（等 S06c 任務 / 神秘洞窟場景）
- 6 運動工作細節待用手測

---

## 7. Spec 06 — 任務系統

記錄喺 `docs/uat/spec06_任務.md`。subsession 核實 + 留低待改：
- 新手游 `newbie_training` 獎勵 `lilian:10` → **改做 exp**（同 F8）
- **任務答題**：答錯其實 code 已 block（有測試 `t_turnin_answer`）——但「答題後 NPC 只喺信息欄，冇對話/彈幕」= 真 gap → 要做對話回饋
- **信息欄道具數量錯**：`RulesQuest.hint()` 淨 fill `%v/%n` for talk_n/repeat，**collect stage 顯示原樣 `%v/%n` 唔填數字** → bug，用背包 count_item 填
- **任務對話冇彈幕**：`_quest_emit` 用 `_msg`，冇 speech bubble → 要加對話氣球/上屏
- **死亡掉野信息欄冇說明**：`_death_report` 有講，但 `_log` 只 log 第一行 → 信息欄 log 完整報告
- **許昌 NPC 太多**：34 fixed + 12~20 居民密集中間 → 散開 / 加大許昌城（改用家 confirm 範圍）

---

## 8. Spec 07 — 座騎戰騎

記錄喺 `docs/uat/spec07_座騎戰騎.md`。重點：
- ✅ 座騎全套（買/騎/改名/飼養/繁衍/馬戰）、戰騎全套、NPC 拍賣場、武將特技「馴馬」
- ✅ 友好技已接：導航/天眼/嗅血（小地圖）、痛楚屏障/加成/聖靈/穩重/遁地地行
- ❌ 留後無效友好技：奇門/火焰/飛影/狂力/開光/召喚/脫出/神行/回城/巨力/野性/獅魂（學到無效果）——待用家confirm係咪而家整
- 馬顏色欄冇單獨 UI、跑馬燈係掣非圖形（待用手測）

---

## 9. Spec 08 — 名聲義勇軍

記錄喺 `docs/uat/spec08_名聲義勇軍.md`（兩份 spec 合併）。重點：
- 🟡 襄陽**冇捐獻處/冇官宅** → 進貢/救災領令唔到
- 🟡 城池好感下游效果未接；義勇軍**階級管理/俸祿設定冇 UI**
- 🟡 營地 **Lv4+/Lv5 職位**（召喚部將/材料轉入/兵營情報）未接功能
- ❌ **軍備製作**（兵工房 10 類）未實裝
- ❌ 民心/法令要**佔城先啟動**（S10c；測試靠直接塞 `hasCity:true`）

---

## 10. Spec 09 — 登用武將 / NPC / LLM

記錄喺 `docs/uat/spec09_登用LLM.md`。重點：
- 🟡 同伴**戰鬥指令 6 → 實作 4 order + skillMode**（偏離 spec）——待用家 confirm 補唔補
- 🟡 居民化：資料幾 ✅，**行為分流未驅動**；「傳聞大表」UI 冇
- ✅ LLM 層（白名單/OpenRouter/反思/Tier/後備）+ U11 設定/對話面板
- 結婚村 4 NPC 圖示缺失（非阻塞，用通用圖示）

---

## 11. Spec 10 — 國戰（【待決】）

記錄喺 `docs/uat/spec10_國戰.md`。**完全未做 ❌**。有 12 個決策點 P1~P12（含 D-3 戰局形式）。開工前用 `ask_user` 一次過問晒 P1~P12 先。

---

## 12. Spec 11 — 資料對照

記錄喺 `docs/uat/spec11_資料對照.md`。重點：
- ✅ items/monsters/generals/recipes/titles 導入器全 `--check` 過
- `material_ids.json` → **實質已完成**（items.json `materials` 已係 `{id,count,name}` 對象），建議剔走 spec §11
- 箭矢 cat 49 全集 38 支，但 `ammo.gd` 只泛用 cat 49 消耗，冇分箭種威力
- 商城道具：**發現 price 衝突** data 600/800/1500 vs PLAN §4「500/800/1500」；渾天儀 26029 有資料冇商店賣
- ❌ recruitinfo 說明頁（資料齊冇 UI）、warbtl 對照（跟 Spec 10）

---

## 13. Spec 12 — 地圖世界

記錄喺 `docs/uat/spec12_地圖世界.md`。重點：
- ✅ 地圖框架（80 map）、A*/過圖/自動尋路、驛站、天災/時辰/日夜
- 🟡 新手城 `homeCity=xuchang` 鎖死，**揀城 UI 未見**（想揀 3 城定鎖死？待用家 confirm）
- 🟡 地標 `ch.landmarks` 已存 id，但**冇頁面儲起再睇** → 可加「典故」頁
- 🟢 HUD 左上角色框縮細、移動模式（搖桿 vs 點擊）切換 —— subsession 自發建議，待用家 confirm
- 世界 23 節點**已全部 open**（無灰節點）；B4 其餘州郡【待決】── 開新州郡圖要先問用家

---

## 14. 已知自動測試問題（跨 spec，一批過改）

基線 `sh tools/run_tests.sh` = **SOME FAILED**（唔係全 PASS）。要修：

| Leg | 問題 | 屬 spec | 狀態 |
|---|---|---|---|
| guard | 城捕快 spawn 14 fail（UAT-001~003）→ `guard.gd` float bug（`patrolShichen` 載入變 `3.0`）+ `add_guards` 只限有客棧城 | 03 | ✅ 已修 (2026-09-29 run_tests ALL OK) |
| down | 復活丹 5 雜貨店判定「冇賣」6 fail（UAT-004/005）→ shop stock float bug + 逾時兜底 HP | 03 | ✅ 已修 (2026-09-29 run_tests ALL OK) |
| ui_smoke | 建角 3（UAT-006~008 stale test，面板已改 2 頁）+ 卸下 1（UAT-009 疑未裝備）+ 掉落 2（UAT-010/011 疑誤判） | 01/02 | ✅ 已修 (2026-09-29 run_tests ALL OK) |

**系統性 root cause**：JSON 整數陣列載入 Godot 變 **float**（`3.0`），令 `Array.has(int)`/`in` 判定錯。已喺 `sim_econ.shop_sells` 用 `float(item)` 繞過，但 `guard.is_patrol_time` 等冇。修正方向：統一 float-safe 比較 helper 或 JSON load 時轉 int。

---

## 15. 完成準則（每份 spec 完）

- [ ] 該 spec 所有**用家已 confirm** 項全部改完
- [ ] 未 confirm 項已 `ask_user` 一次過問晒、有答先做，未答嘅明確標「待用家 confirm」
- [ ] `sh tools/run_tests.sh` 全 PASS（所有 leg，包括導入器 `--check`）
- [ ] `docs/uat/specNN_*.md` 剔格/標狀態
- [ ] `docs/PLAN.md` §1 現況表 + `CLAUDE.md`（project_instructions）「現況」段更新
- [ ] 相關 `docs/spec/NN_*.md` 頂「現狀」更新