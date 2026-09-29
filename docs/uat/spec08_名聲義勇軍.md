# Spec 08 — 名聲 / 官宅 / 城池 / 義勇軍：應有 UI + 邏輯對照

> 用途：你逐項睇（應有咩 UI / 邏輯），去試，比 feedback。✅=已實作　🟡=部分　❌=未做。
> 對應攻略 sy2_8_1~8_8、8_12、8_14、sy2_9_19。
> 現況權威 = 兩份 spec（`08_名聲官宅城池.md` + `08_義勇軍.md`）+ PLAN S08/S08g + code。
> 本檔把兩份 spec 合埋一份輸出。**S08a~S08g 全部邏輯已實裝，UI 面板 U05/U06/U08/U09/U10 已做**。

## ⏸️ 進度暫停點（2026-09-29）

- **已做**：頭銜60階/官宅（討取/官令/捐獻/月俸/行動丹）、義舉+進貢、城池屬性+內政、救災、義勇軍成立/定居/帶兵量、民心+法令、營地10設施/22工作/評定。
- **待改**（待用家）：
  - 襄陽冇捐獻處/官宅 → 進貢/救災領令唔到
  - 城池好感下游效果未接；義勇軍階級管理/俸祿設定冇 UI
  - 營地 Lv4/5 職位（召喚部將/材料轉入/兵營情報）未接功能
  - 軍備製作（兵工房 10 類）未實裝
- **待 S10c**：民心/法令要佔城先啟動（測試靠塞 `hasCity:true`）。

---

## A. 名聲類別 ／ 進入
| 途徑 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| A1 名聲判定 | 角色/官宅面板顯示名聲值 | `ch.fame`；只升唔降（防止惡意鎖死） | ✅ `office_panel` 頁 0 顯示名聲 |
| A2 義舉證明繳交 | 官宅「義舉/進貢」頁列持有嘅義舉證明物品 + 繳交掣；**限許昌朝廷官員** | `RulesMerit.block` 頭銜門檻（機密/古董/收藏三類有 `reqRank`）+ `item_def`/`fame_of`；四類 20 項 `office.json merit`；繳完 `fame +` | ✅ `office_panel` 頁 2（`merit_list`/`cmd_merit_turnin`）。⚠️ 有頭銜需求嘅道具，連唔達標都照列「要 X 頭銜」灰掣 |
| A3 城池進貢 | 官宅「義舉/進貢」頁顯示各城好感 + 背包可捐物資「進貢」掣 | `RulesMerit.favor_gain`（單位×0.01）/`tribute_fame`/`favor_cap`(100)；唔扣行動力；`ch.cityFavor` | ✅ 頁 2（`city_favor_view`/`cmd_city_tribute`）🚩 **襄陽冇捐獻處，進貢唔到** |
| A4 城池好感下游 | 好感影響居民打招呼/登用/任務解鎖 | spec 話好感有用處 | 🟡 `ch.cityFavor` 已存 + read-model 有，**下游效果未有**（PLAN §4 S08a 已記） |

## B. 頭銜 60 階 ／ 官宅
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| B1 討取頭銜 | 官宅「頭銜」頁列下級頭銜（名聲/金需求）+ 討取掣（唔夠灰掣） | `RulesTitle.claim_check`（名聲≥ + 金≥，可跳階）；`cmd_claim_title` 扣金、設 `titleRank`、`titleCompete=true` | ✅ `office_panel` 頁 0（顯示下 8 階 + 討取） |
| B2 俸祿 | 每月初一自動，玩家睇到「領 X 金」訊息 | `_salary_daily` 月初派 `salary`（`titles.json`） | ✅ 訊息 |
| B3 行動力上限 | 角色面板顯示上限 = 100+2×頭銜階 | `RulesTitle.ap_max`（`titles.json ap` 欄；表中 102~220） | ✅ |
| B4 官令 | 官宅「頭銜」頁 → 「官令」頁：接令/交令/放棄 | 每日 1 條、扣行動力 `_office_ap_cost`（default 10）、頭銜解鎖 | ✅ `office_panel` 頁 1 |
| B5 行動丹 | 官宅換行動丹（貢獻兌換） | `cmd_office_pill`（`office.pillCost`） | ✅（無獨立掣，留後續確認兌換入口 UI） |
| B6 名額競爭 | 官宅「名額競爭」頁顯示守位狀態 + 上次結果 | `comp_score`/`npc_score`（獨立 SimRng）；月初 `_title_contest_daily`：3 NPC 挑戰者，輸 → `titleRank−1`；只對朝廷討取得嚟（`titleCompete`） | ✅ `office_panel` 頁 3（`title_contest_view`）。🚩 **手測：討取頭銜後睇頁 3 有冇顯示「每月初一評比」** |

## C. 城池屬性 8 項 ／ 官宅內政 6 種
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| C1 城池屬性顯示 | 官宅「內政」頁顯示所在城 8 項屬性（開墾/商業/畜牧/礦產/鑄造/防禦/防災/治安 0~100） | `RulesCity.init_attrs`/`attr_of`；真值 `state.cityAttrs`（存檔） | ✅ `office_panel` 頁 4（`domestic_view`） |
| C2 內政 6 種 | 官宅「內政」頁 6 種工作掣（每次扣行動力 + 專長 exp + 城池屬性提升，封頂 100） | `cmd_domestic`（`domestic_cfg` baseGain 2 / expertExp 3 / minTitleRank 1）；需官身；有專長倍率 | ✅ 頁 4。🚩 **手測：內政喺官宅做，屬性+1，專長 exp 增，痴 action** |
| C3 屬性連動 | 防災→天災減弱；開墾/商業/畜牧/礦產→市場 prod；鑄造→商店多貨；防禦→衛兵間隔；治安→犯案率 | `prod_mult`/`disaster_mitigation`/`shop_extra_items`/`guard_warn_ticks`/`crime_mult` | ✅（連動已掛 market/guard/bots）。🟡 防禦 attr 下游（城牆/攻城）冇系統，留 S10 |

## D. 救災
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| D1 公佈欄 | 官宅「救災」頁頂睇各城天災報告（名稱/規模/救災物品） | `bulletin_view` | ✅ `office_panel` 頁 5 |
| D2 領救災官令 | 官宅功曹 → 「領救災官令」掣（扣行動力 10） | `relief_block`/`cmd_office_relief`（動態綁 `{city,disaster,need,done}`） | ✅ 頁 5 |
| D3 救災物品 | 工具店買對應物品（農藥/補藥/水桶/榔頭/青泥/鏟子/地動儀）；天災期間照買到 | `_relief_item`；`sim_econ _shop_shutdown_reason` 豁免救災物品 | ✅ shops 3 間工具店 + 7 物品 |
| D4 救災區做 N 次 | 去救災區，反覆做救災動作（每次扣 SP + 用 1 份物品；小10/中20/大30） | `cmd_relief_work` + `relief_weaken`（天災強度遞減） | ✅ `office_panel` 頁 5「救災（去救災區）」掣 |
| D5 覆命獎勵 | 返接令官宅覆命：名聲+10 / 政治 exp / 救災專長 exp / 行動力−10（接令時扣） | `cmd_office_turnin` 專屬 relief 流程 + `_relief_reward` | ✅ `office_panel` 頁 5「交令」 |
| D6 民心增益 | 救災/捐贈官令 → 城池民心 + | `civic_fame_gain`（每 10 名聲 +0.1，上限 +10/月） | ✅（需佔城先見效，見 F） |
| D7 多人救災加快 | 武將同伴助攻 | spec 提 | 🟡 `_domestic_assist_bonus` 已接（S09c），救災工作次數增速未確認；相應 facility 無同伴 UI |

## E. 義勇軍成立 ／ 定居 ／ 帶兵量
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| E1 定居 | 義勇軍面板「定居」頁：揀城池定居（要企喺城池入面）；新手城標示 | `cmd_settle`（`settle_block`）；`ch.homeCity`；用現有 10 城池 | ✅ `militia_panel` 頁 0 |
| E2 定居城池選擇 | 顯示所有可定居城池 + 新手城（許昌/襄陽/新野）flag | `_settle_cities`；`is_newbie` | ✅ 頁 0 |
| E3 義勇軍成立條件 | 義勇軍面板「義勇軍」頁列 5 條件（頭銜南中郎將/名聲3000/擁護者10/經費20萬/定居非新手城）✔✘ | `found_block`；`cmd_militia_found`（扣 20 萬、`m.founded=true`、名號非空≤12、暗號） | ✅ `militia_panel` 頁 1 |
| E4 遊說擁護者 | 長按居民 menu →「遊說（義勇軍）」；居民 Lv≥5 + 好感≥50 | `cmd_militia_invite`（快照 `supporters`）；`invite_block` | ✅（長按居民掣）。🚩 紅名殺人魔冇呢個選項 |
| E5 帶兵量 | 義勇軍面板顯示帶兵量上限 | `max_soldiers` = 7000 + 品階(8000~1000) + 頭銜(`titles.json soldiers`)；51 階起固定 28000；未入會/<5級=0 | ✅ `militia_panel` 頁 1 |
| E6 成員/階級 | 已成立後顯示名號/根據地/階級/成員 list | `m.grade=1`（一品）；成員 = supporters | ✅ 頁 1。🟡 **階級管理/權限/俸祿設定冇 UI**（sim 存 `grade`/`role`，後續） |

## F. 民心 + 法令（城池佔領後啟動）
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| F1 民心顯示 | 民心/法令面板顯示民心/100 + 人口 | `city_gov_view`；`state["cityGov"]`/`cityPop` | ✅ `civic_panel`。🚩 **未佔城 = active false = 顯示但全部唔可改**（S10 佔城先解鎖） |
| F2 稅率 3 檔 | 民心/法令面板低/正常/高 3 掣 | `cmd_city_tax`；`tax_drop` 高稅 −4/月 | ✅ `civic_panel`（未佔城 disabled） |
| F3 月度評比 | 每月初一 → 高稅民心−4、人口流失、本月官令增益歸零 | `_morale_daily`/`pop_after`/`morale_gain` | ✅ |
| F4 民心連動 | 市場 prod ×民心/100；徵兵 ×`recruit_mult`（地板0.3） | `RulesMarket` prod ×`RulesCivic.prod_mult`；`cmd_militia_work` 徵兵 ×`RulesCivic.recruit_mult` | ✅ 已接 |
| F5 6 條法令 | 民心/法令面板 6 法令開關（每壓一次行動力100，每月1次） | `cmd_city_law`/`change_block`/`ap_cost`；`crafts`→大宗師閘、`guard`→衛兵、`cityDrop`→丟物品 | ✅ `civic_panel`（未佔城 disabled）。🟡 **山洞商店/PK/善惡入城 3 法令下游未有系統，先存 gov**（留 S10） |
| F6 城池佔領 | 要有城池先啟動民心/法令 | `city_gov_init` | ❌ **佔城系統未做，掛 S10c**。全部照舊零行為改變 |

## G. 營地 10 設施 ／ 22 工作 ／ 評定會議
| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| G1 營地設施列表 | 營地面板「設施」頁：10 設施（營地/金庫/糧倉/宿舍/兵營/物品庫/資源庫/軍備庫/材料庫/寶庫）+ 級 + 升級掣 | `camp_view`；`upgrade_cost` = 基本×目標級數；`cmd_camp_upgrade` | ✅ `camp_panel` 頁 0。🟡 升到 `maxLevel` 前 show cost，冇顯示完整材料 list |
| G2 監督建設 | 頭目/參軍指定升級 → 成員「監督」赴建設衝完成度（目標100） | `supervise_points`（0.5+政治×0.01+木匠×0.02+身份）；`cmd_camp_supervise` | ✅ 頁 0（「監督」掣） |
| G3 設施功能 | 精度按級提升（規模→工作指派 50~100 / 階級人數上限）；4級典農/靈台、5級司農 | `work_cap`/`grade_limit`/`facility_cap`/`positions_at` | ✅ 🟡 營地 Lv4+/Lv5 職位（召喚部將/材料轉入轉出/兵營情報）**冇接功能**（留 S10/S09） |
| G4 義勇軍工作 22 項 | 營地面板「工作」頁：22 項分內政/軍事/軍備 3 系 + 做掣（每次扣行動力10 + 績效） | `militia_work_view`/`cmd_militia_work`；`is_available`（無城池 → 只監督/商情+軍3+軍備9=14）；有城池才 22 | ✅ `camp_panel` 頁 1 |
| G5 工作效果 | 內政→城池 attr；監督→營地建設；商情→貿易情報值；訓練→camp.train；徵兵→soldiers；軍備/捐→stores（受設施上限封頂） | `_work_apply`/`_store_add`/`_work_mult`（專長倍率） | ✅ |
| G6 評定會議 | 營地面板「評定」頁：指派 3 類工作（捐獻/監督/商情）+ 績效→功績預估 + 召開會議 | `cmd_eval_assign`（≤3 類，指派工作 +20 績效）；`cmd_eval_meeting`（頭目限定，結算→功績+績效歸0+重新指派）；月初自動 `_eval_daily` | ✅ `camp_panel` 頁 2 |
| G7 績效→功績對照 | 顯示「本期績效 X、預估功績 X」 | `merit_delta` 14 段對照表 \[[20,-30]...[901+,100]\] | ✅ 頁 2 |
| G8 倉庫/商情/訓練 | 營地面板「倉庫」頁：庫存 + 商情情報值 + 訓練度 | `camp_view` stores/trade/train | ✅ `camp_panel` 頁 3 |
| G9 軍備製作（兵工房） | 10 類兵裝製作 | spec sy2_8_7 | ❌ **未實裝**（營地軍備僅係 store 加減，無兵工房逐件製作 UI）。留後續/S10 |

---

## 你嘅 feedback 重點（Spec 08）
1. **官宅面板 6 頁**（頭銜/官令/義舉進貢/名額競爭/內政/救災）每頁順唔順、有冇資料錯位
2. **討取頭銜 + 名額競爭**：討取後頁 3 有冇顯示「每月初一評比」；跨過月初睇會唔會見到守位成功/失敗訊息
3. **內政**：各內政喺官宅做，屬性+1 / 專長 exp / 扣行動力；屬性封頂 100
4. **救災全流程**：公佈欄睇天災 → 買物品 → 救災區做 N 次 → 覆命（名聲+10/政治 exp/專長 exp）
5. **義舉/進貢**：持有義舉證明道具先顯示到繳交；進貢好感唔會超過 100；**襄陽進貢唔到**（冇捐獻處）
6. **義勇軍成立**：定居（新手城唔計）→ 長按居民遊說 10 人 → 起義成立（名號/暗號）→ 睇帶兵量
7. **營地**：設施升級 → 監督 → 22 工作做 → 評定指派/會議（功績 +/−）
8. **民心/法令**：現時未有城池，應該全部「未佔領」提示；有冇意外改到嘢
9. **行動力**：官令/內政/救災/義勇軍工作都扣行動力，每月回 20

## 已知自動測試問題（相關）
- **S08g 民心/法令 / 城池佔領**：`state["cityGov"]` 啟動入口 `city_gov_init` 掛 S10c——**測試都係靠直接塞 `hasCity:true` + `city_gov_init` 造模擬**；人手測試唔會見到啟動（正常）。
- `tests/run_militia.gd`（義舉/進貢/內政/救災/義勇軍成立/帶兵量）、`tests/run_camp.gd`（營地/22 工作/評定）、`tests/run_title.gd`（頭銜/名額競爭）、`tests/run_civic.gd`（民心/法令）——邏輯 PASS；若 feedback 反映 UI──過 sim 層先係 bug。
- 名額競爭用**獨立 SimRng**（`800001+day*3181+rank*101`），唔耗主 rng 流，測試可重現；同主世界 RNG 結果唔互相影響。
- 救災官令共用 `ch.office.order`，**唔入 `office.orders` 表**，動態綁城池/天災——若玩家同時有普通官令 + 救災官令會撞位（設計應唔會同時，但手測留意）。
- 「襄陽冇官宅/冇捐獻處」→ 襄陽救災官令暫時領唔到（`data/facilities.json` 只有許昌/新野官宅）。已知限制。