# Sanguo Remake — 新 session 接手簡報

私人本地原型：自家代碼重做三國演義 Online 普通玩法（即時制打怪練功），**目標平台 = 手機單機**，NPC 由 LLM(API) 驅動。只本機跑，唔連任何真實伺服器。

## 先讀（按序）
1. `docs/DESIGN.md` — 整體設計 v2（手機、豫荊、LLM NPC 架構、市場模擬、待決事項）
2. `docs/PLAN.md` — 路線圖 v4（現況速覽、Phase A~F 每步驗收）
3. `docs/spec/01~11` — **完整系統邏輯規格**（角色/戰鬥/善惡/怪物/生產/任務/座騎/名聲/登用/國戰/資料對照）；改機制前先睇
4. `docs/普通玩法_系統摘要.md` — 玩法規格（【原】= 官方攻略；【自訂】= 自己設計）
5. `docs/guide/` — 攻略原文 113 頁；`README.md` — 結構同跑法

## 現況 (2026-09-23)
- **全部喺 `client/` (Godot 4.7, GDScript)**：`rules/`(純函數)、`sim/`(單機世界模擬，狀態可存檔、種子 RNG)、`ui/`(畫面/輸入)、`tests/`
- 測試：`sh tools/run_tests.sh` → rules 對拍 387 向量 + quest 94 + spell 618 + jewel/ult 118 + sim 160 + world 121 + monsters 802 + maps 526 + equip 57 + craft 75 + tiandi 68 + hud 版面 2715 + `--autotest` 端到端 + `--uitest` 觸控煙霧 37 + 掉落導入核對 `tools/import_drops.py --check` + 配方核對 `tools/import_recipes.py --check`，全 PASS
- 功能：角色/升級/即時戰鬥/怪 AI+重生+掉落/死亡處分/10 個 bot/客棧+武器店/術法系統(Step 9)/寶石+絕招+融合(Step 10：寶石欄 2 格、屬性石 40+輔助石、元素術需特殊石、義士三招絕招任務鏈、打鐵鋪 QTE 融合)/裝備(Step 11.6：5 部位防具+武器 3 槽+耐久，`rules/equip.gd` + `data/equip.json`，裝備 = 背包參照)/防具店/進階生產(Step 12：初階技能等級 1~100、5 進階技能 + `data/recipes.json` 2318 配方、許昌廚房/藥房/工房、武器耐久、自己修理 + 打鐵鋪修理服務、工具店)/天地商行自動化+捐獻(Step 13：`rules/tiandi.gd`，負重滿自動存/賣材料、自動買賣工具、小屋休息、背包「腳伕」頁；捐贈官令 `data/donation.json` → 名聲+魅力經驗；行動力 `ch.ap` 簡版)；手機 UI（三國群英傳M 風格）: `ui/touch/`(HudLayout 版面/搖桿/互動掣) + `ui/panels/`(背包/商店/角色/對話/記事，正式 Control 面板，玩家自己揀自己確認)；建角面板仍係舊 debug 版
- **地圖世界 B2（spec 12）**：B1 之外加汝南道/昆陽/宛城道/博望坡/新野城（新野 = 第二個新手城：客棧/武器店/防具店/兩條任務）；大地圖天下頁撳節點「自動前往」= `sim.cmd_goto_map`；多客棧（`shops.json inns`），死亡返最近客棧
- **地圖世界 B1（spec 12）**：`data/maps.json`（legend/地圖/傳送點/地標/天下節點）+ `data/maps/*.txt`（ASCII 人手地圖，一字一格）拼落 512×512 全域格仔，地圖之間隔 ≥20 格；其他數據寫 `map` + 地圖內座標，GameData 載入轉全域。A* 尋路、踩門口過圖、居民跨圖路由；UI 預渲染地圖貼圖 + 小地圖 + 地圖面板。改地圖直接改 txt（`tools/map_draft.py` 只係起稿，再跑會覆蓋；`--b2` 只起 B2 五張）；新 txt 要喺 export include_filter 範圍（`data/maps/*.txt`）
- `client/data/`：classes.json(六職，只啟用義士)、monsters.json(34 怪+spawn，area = 地圖內座標；掉落由 `tools/import_drops.py` 從原版 npc_drops.csv 生成，唔好手改)、items.json(6068 件)、recipes.json(由 `tools/import_recipes.py` 生成，唔好手改)、work.json、shops.json、maps.json、donation.json(捐獻轉換表【原】)；`data_src/general_npc.csv`(未接入)
- `legacy/server/`：舊 Node+ws server，只作參考（23 項 TS 測試仍過；`tools/export_vectors.ts` 由佢導出向量）
- **下一步**：跟 `docs/PLAN.md` §2 第一個未剔 Step（v5 順序：13.5 登用 v1 → 14 頭銜 …）；§1 有各 spec 核實現況
- 攻略原文 113 頁：`docs/guide/*.txt`；連結表 `docs/guide_links.tsv`

## 已定決策
- 手機單機（橫屏觸控，Android 先）；範圍 豫州+荊州，新手城 許昌/襄陽/新野
- 義士先行；戰鬥即時制，sim 權威，client 只發意圖
- NPC = LLM(API)：**LLM 只揀動作/生成話語，唔直接改數值**；分 Tier；一定要有規則/模板後備（離線可玩）；測試用 mock，唔碰網絡
- 公式全部【自訂】，放 `client/rules/` + 測試，數值放 `client/data/`；rules 保持純函數 + 數據驅動
- **架構 A2**（已完成遷移）：sim/規則/存檔全部喺 Godot(GDScript)；UI 只發 `sim.cmd_*` 意圖、聽 `event_emitted`、讀 `view_ents()`/`player_ch()`；sim 狀態 = 純資料 Dictionary，`save_string()`/`Sim.load_string()`；所有隨機經 `SimRng`（種子），測試要可重現
- **LLM**：OpenRouter（OpenAI 相容），**玩家自填 key**（本機存，唔入存檔/log），模型名可設定；B2 行為（規則主導+搭話即時+每日反思）；R1 記憶（結構化事實+摘要）
- 待決：D-3 戰局形式（見 DESIGN §8）
- 理念測驗/登用 → Step 8；國戰 → Step 10（最後）

## 工具 / 路徑
- Godot: `D:\Download\Sengoku\godot\Godot_v4.7.2-stable_win64_console.exe`；跑全部測試 `sh tools/run_tests.sh`；Godot 踩坑筆記見 `docs/GODOT_NOTES.md`
- 8080 port 被別個程式佔用，唔好殺（舊 server 用 8765，已退役）
- 逆向研究資料（原版表/素材/協議筆記）: `D:\Download\sanguo\`（`docs/INDEX.md`、`extracted/`）；原版客戶端 `D:\Download\Sanguo_Client\`
- 原版無公式（server 權威）、無怪物/人物 sprite（未解）
- Bash heredoc 遇中文+引號會壞，寫檔用 Write 工具
- Windows Python 睇唔到 `/tmp`，暫存用 scratchpad

## 素材規則（重要）
`client/assets_placeholder/` = 佔位素材（placeholder，**唔係原版素材**），唔入 git（已 .gitignore）。引用一律經 `res://assets_placeholder/`。成品前全部換走。角色暫用頭像、怪物色塊。APK / web 匯出包含佢冇問題。

## 工作方式
- 邏輯先、UI 後：規格 → `rules/*.ts` + 測試 → 無畫面模擬 → 最簡 debug UI → 試玩 → 穩定後美化
- 每步要可跑可驗證（`tools/run_tests.sh`）；未過驗收唔開下一步
- 改咗規則 → 加測試；sim 加系統 → 加場景測試 + 確認決定性/存檔 roundtrip 測試仍過
- 回覆用廣東話
