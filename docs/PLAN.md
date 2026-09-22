# 計劃 (v3, 2026-09-21)

整體設計見 `DESIGN.md`（手機單機、豫荊、LLM NPC、市場模擬）。玩法規格見 `普通玩法_系統摘要.md`（【原】=攻略明文；【自訂】=自己設計）。
v3 相對 v2 嘅改動：加入世界模擬層(存檔/時鐘/天災/市場)、bot 升級為 NPC agent、LLM 層、理念/武將提前、國戰保持最後、加手機化檢查點。

## 已定決策
| 項目 | 決定 |
|---|---|
| 平台 | 手機遊戲(Android 先)，橫屏觸控；PC 為開發環境 |
| 形態 | 純單機 |
| 範圍 | 豫州+荊州；新手城 許昌/襄陽/新野 |
| 第一職業 | 義士（近戰，刀/鎚/矛；「融合」放後），資料結構預留六職 |
| 戰鬥 | 即時制；右鍵戰鬥游標→左鍵點怪→自動追擊（手機：點怪自動追擊 + 戰鬥/行走切換掣）；sim 權威，client 只發意圖 |
| 運行架構 | **A2：全部移入 Godot (GDScript)** ✅ 已遷移；Node server 已移 `legacy/server` |
| NPC 智能 | LLM 經 OpenRouter，**玩家自填 key**；單一模型可設定；B2 行為(規則+搭話+每日反思)；R1 記憶；規則層結算、LLM 只揀動作/生成話語；分 Tier；有離線後備 |
| 公式 | 全部【自訂】，放 `client/rules/` + 測試，數值放 `client/data/` |
| 新手練兵場(需 2 人) | 由 NPC/機械人頂替 |
| 國戰 | 最後；形式未定，用歷史戰役做原型 |

## 已完成
### Step 1 骨架 ✅
server(64×64 格、AOI、30 機械人、10Hz)、Godot 客戶端、`world.test.ts` + `--autotest` 端到端 PASS。

### Step 2 角色屬性 + 即時戰鬥 + 怪物 ✅ (2.1~2.6)
- 2.1 `data/classes.json`(六職)、`data/monsters.json`(5 怪+spawn)、`model.ts`、`rules/stats.ts`（屬性/成長/經驗/建角）。手感：脫新手(5 級)需 477 經驗 ≈ 48 隻野狗
- 2.2/2.3 `rules/combat.ts`、`world.ts`（戰鬥、怪 AI、重生、掉落）、`combat.test.ts`
- 2.4 死亡掉背包物品 `rollDeathDrop`；死亡掉經驗按善惡
- 2.5 client HUD / 右鍵戰鬥游標 / 血條 / 傷害數字 / 背包(B)；`--autotest` 覆蓋殺怪+經驗
- 2.6 bots 有角色，自動打怪、血低返客棧休息、聊天(公用)

### Step 3.1 客棧 + 武器店 ✅
`data/shops.json`、`rules/shop.ts`（魅力折扣）；client 鍵 R/1-3/X/H。`npm test` 23 項通過。
已知：30 bot 會搶低級怪；`--autotest` 偶發 timeout（重跑）。

## 下一階段（按序；每步要可跑可驗證：單元測試 + 模擬 + `--autotest`）

### Step 3.0 遷移到 Godot（A2）✅ 2026-09-21
- `rules/` 逐行移植（combat/stats/shop/mathx），由 legacy TS 導出 **201 個測試向量**對拍，全過（js_round 處理 JS/GDScript 四捨五入差異）
- `sim/` 重寫：去 AOI/ws/快照；狀態純資料可存檔；`SimRng`(mulberry32) 種子 RNG → 決定性；`event_emitted` 信號；bot 分離做 `bot_sys.gd`
- `ui/main.gd` 改為內嵌 sim（舊 ws 訊息格式 → `_send` 轉 `sim.cmd_*`）；autotest 加速跑（每幀 20 tick），數秒完成
- 測試：`tools/run_tests.sh` = rules 向量 201 + sim 場景 22（走路/阻擋/殺怪/死亡/客棧商店/決定性/存檔 roundtrip/bot 有殺怪）+ autotest，全 PASS
- 整理：`data/` → `client/data/`（Godot 匯出需要）；`general_npc.csv` → `data_src/`；`server/` → `legacy/server/`
- 順帶修：bot 由 30 減至 10（減輕搶怪）；autotest 唔再偶發 timeout（唔靠實時）

### Step 3.2 L1 收尾 + 手機化檢查點 ✅ 2026-09-21
- 善惡七階顯示 ✅（HUD 已有 `RulesKarma.tier_name`）；殺善惡 NPC 增減【原】→ 併入 Step 5（有 NPC alignment 先做得）
- 手機原型檢查點：觸控層已存在 `ui/touch/`（虛擬搖桿+點怪+自動掛機）；Android export preset 已設（`build/sanguo.apk`）——真機手感未試（需 SDK），`export_presets.cfg` 準備好
- 城內設施骨架 ✅：`data/facilities.json`（練兵場/私塾/寺廟）+ `sim.cmd_facility` + UI 面板 + 鍵 T/P/M：
  - 練兵場【原】2 人對練：扣 15% HP/SP，+10 歷練（cap 100）；升級時每 10 歷練 武/智/敏/靈 +1（`RulesStats.gain_exp` 消耗）
  - 私塾【原】政治+1（扣 20% SP/MP + 5 金）、寺廟【原】魅力+1（扣 20% SP + 8 金），屬性 cap 99
  - 面板顯示描述/成本/歷練進度，點擊使用

### Step 4 世界基建：存檔 + 時鐘 + 天災 + 市場 ✅ 2026-09-21
- **存檔**（4.1）：Godot 冇內建 SQLite → 用 JSON 檔 `user://save/`（`sim/save_sys.gd`，`Sim.load_string` 一致）；自動存檔每 game 日 + 死亡即存；開場自動載入 autosave（`--newgame` 重開）。**偏離 PLAN：SQLite→JSON**（Godot 原生冇 SQLite，引入 GDExtension 過重；JSON 已達「可重現單一檔」目標，NPC 記憶表都喺 state）
- **世界時鐘**（4.2）：`data/world.json` clock.gameMinPerTick=2（1 game 日 = 72 秒真實）；十二時辰×8 刻=96 刻/日 + 四季 30 日/季（`rules/clock.gd`）；夜晚怪（夜狼 Lv3）晴/晚柅自動變換；UI 右上時辰+夜晚示意、夜景淡化
- **天災**（4.3）：`rules/disaster.gd` 7 種（蝗/疫/旱/颶風/洪水/暴風雪/地震）×大中細×季節限制×城内機率；看城池防災度減輕；每日子時擲骰 → 影響市場供給；UI 橫幅提示
- **動態市場**（4.4）：`rules/market.gd` 每城每 cat 價格因子 [0.5,2]+價格彈性自穩定；1000 日模擬器 `client/tools/market_sim.gd` ——有界、玩家出貨跌價、天災後回歸 PASS
- 商店用市場價（4.5）：買入=市場價×魅力折扣，賣出=市場價 50%；UI 顯示
- 測試：`tests/run_world.gd` 82 項（時鐘/夜怪/設施/市場有界/天災反應/存檔 roundtrip）+ market_sim PASS；全套 `run_tests.sh`（rules 201 + sim 37 + world 82 + market + autotest）ALL OK

### 地圖分區：安全區/戰鬥區 + 傳送點 ✅ 2026-09-21
玩測發現商店/市場同打怪區擠埋一齊，冇「城內安全」概念。加：
- `client/data/zones.json`：`town`(safe=true, 0-25)、`field_1`(safe=false, 26-60，原 `Sim.ZONE`) 兩個唔重疊矩形；`monsters.json` spawns 嘅 `zone` 欄位而家真係接住用（之前係死字串未讀取）
- `sim.is_safe(x,y)`：安全區內 `_think_player` 唔出手（追到都唔打，理論上怪唔會入城，做多重保險）
- `cmd_travel(id, point_id)`：傳送點一對一連結（`gate_out`↔`gate_in`），行近即傳送對面，`travel` 事件通知 UI
- UI：傳送點併入 `facilities` 畫法(綠框)，鍵 `G` / 點擊傳送點格仔觸發；`_on_event` 加 `travel` 分支
- 測試：`tests/run_world.gd` 加 `t_zones_travel`（安全區判斷、追怪唔出手、傳送落點、唔近傳送點唔生效）；全套 `run_tests.sh`（rules 201 + sim 37 + world 89 + market + autotest）ALL OK

### Step 5 NPC agent 框架（規則版）← 下一步（未做）
- 4.5 商店改用市場價；魅力折扣保留；`rules/market.ts` + 測試
- 驗收：模擬 1000 日價格有界、天災後價格反應合理；商店買賣走市場價

### Step 5 NPC agent 框架（規則版）
- 5.1 bot 升級為居民：名字、理念、性格、日程、目標、Tier 分級
- 5.2 **記憶表**（結構化：好感、事件、目擊）；目擊判定 + **傳聞擴散**（同城快、跨城慢）
- 5.3 善惡→NPC 反應：買價、任務可得、衛兵態度；死亡掉落規則保留【原】
- 5.4 `brain` 介面 + 規則/模板實作 + mock；行動白名單
- 驗收：殺善 NPC → 目擊者好感下降 → 傳聞到鄰城 → 價格/態度變化（測試可重現）

### Step 6 接 LLM
- 6.1 `brain` 之 LLM 實作（OpenRouter，OpenAI 相容 API）：對話、每日反思、記憶摘要、傳聞措辭；輸出 JSON schema 驗證，非法丟棄重試
- 6.2 每日「反思」批次（B2）+ 記憶事件表/摘要（R1）；成本控制：Tier、每日 token 預算、緩存、冷卻；超額降級為模板
- 6.3 **OpenRouter 接入**：設定頁玩家自填 key（存本機，唔入存檔/log）；模型名放設定檔；HTTPRequest 非同步；冇 key/失敗→模板
- 6.4 首批 Tier1 武將 10~20 人（由 `general_npc.csv` 挑豫荊相關）
- 6.5 對話 UI（手機）：頭像+對話框+預設選項+自由輸入
- 驗收：無網絡/預算用完仍可玩；mock 測試覆蓋全部動作；LLM 唔可直接改數值（測試斷言）

### Step 7 生產與成長 (L2/L3)
- 6 初階工作技能(農耕/狩獵/伐木/釣魚/採藥/採礦)、工具耐久、工作區
- 50 級 4 進階（廚藝/木匠/冶鐵修繕/煉丹）、天地商行
- 二轉(50 級)、專長、寶石屬性相剋、術法（第二職業起）、座騎/戰騎
- 生產品接入市場（Step 4）

### Step 8 理念 + 登用（輕版）+ 武將同伴
- 理念測驗（五理念）→ 可登用武將範圍【原】
- 登用 = 理念相合 + 屬性 + 好感；忠誠模型（行為/待遇/理念一致度）
- 同伴入隊戰鬥（規則 AI）；主要武將對話用 LLM
- 官令/歷史/絕招任務鏈

### Step 9 義勇軍經營
- 名聲→頭銜(60 階)、義勇軍建立條件【原】、營地/設施/內政/民心、帶兵量公式【原】
- 經營模擬化：經費、民心、兵源、天災應對

### Step 10 戰局（原「國戰」）
- 先以**一場歷史戰役**（如討伐程遠志）做原型，試戰棋/半即時，定 D-3
- 規則參考 `sanguo/docs/cs_War_單元_PhaseA9.md`（宣戰、出戰名單、兵種特技指令、撤退）；攻略缺兵種屬性/特技/指令頁，需自訂

### Step 11 換素材
`assets_placeholder` 全換自製/AI；角色 8 方向動畫最花功夫；手機解像度/圖集優化。

## 與 v2 對照
| v2 | v3 |
|---|---|
| Step 3：城池經濟（固定價）+ SQLite + PK 規則 | 拆為 3.2（L1 收尾+手機檢查點）與 Step 4（存檔/時鐘/天災/市場） |
| Step 4：練兵場/私塾/工作技能… | 練兵場等入 3.2；工作技能等移 Step 7（市場之後） |
| Step 5：理念/登用/天災/義勇軍 | 天災→Step 4；理念/登用→Step 8；義勇軍→Step 9 |
| bot 僅供練兵場頂替 | bot 升級為 NPC agent（Step 5） |
| 無 LLM | Step 6 |
| 國戰 Step 6 | Step 10 |

## 風險
- 美術量、數值平衡 > 技術難度
- 攻略無公式，手感靠模擬+測試調；數值全放 `data/` 同 `rules/`
- LLM：成本/延遲/漂移 → Tier、預算、schema、白名單、離線後備；玩家自付 API 費用，需清晰顯示用量
- 遷移：GDScript 行為偏離 TS → 測試向量對拍；手機手感 → 3.2 起早試真機
- 範圍：一職業、一區、豫荊；未過驗收唔開下一步
