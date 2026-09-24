# Sanguo Remake — 新 session 接手簡報

私人本地原型：自家代碼重做三國演義 Online 普通玩法（即時制打怪練功），**目標平台 = 手機單機**，NPC 由 LLM(API) 驅動。只本機跑，唔連任何真實伺服器。

## 先讀（按序）
1. `docs/DESIGN.md` — 整體設計 v2（手機、豫荊、LLM NPC 架構、市場模擬、待決事項）
2. `docs/PLAN.md` — 路線圖 v4（現況速覽、Phase A~F 每步驗收）
3. `docs/spec/01~11` — **完整系統邏輯規格**（角色/戰鬥/善惡/怪物/生產/任務/座騎/名聲/登用/國戰/資料對照）；改機制前先睇
4. `docs/普通玩法_系統摘要.md` — 玩法規格（【原】= 官方攻略；【自訂】= 自己設計）
5. `docs/guide/` — 攻略原文 113 頁；`README.md` — 結構同跑法

## 現況 (2026-09-24)
- **全部喺 `client/` (Godot 4.7, GDScript)**：`rules/`(純函數)、`sim/`(單機世界模擬，狀態可存檔、種子 RNG)、`ui/`(畫面/輸入)、`tests/`
- 測試：`sh tools/run_tests.sh` → rules 對拍 419 向量 + quest 94 + hist 162 + b3 127 + spell 618 + jewel/ult 118 + sim 160 + world 121 + monsters 1166 + maps 1245 + equip 57 + craft 75 + tiandi 68 + recruit 119 + general 118 + title 95 + hud 版面 3055 + `--autotest` 端到端 + `--uitest` 觸控煙霧 72 + 掉落導入核對 `tools/import_drops.py --check` + 配方核對 `tools/import_recipes.py --check` + 武將核對 `tools/gen_generals.py --check` + 頭銜核對 `tools/gen_titles.py --check`，全 PASS
- 功能：角色/升級/即時戰鬥/怪 AI+重生+掉落/死亡處分/10 個 bot/客棧+武器店/術法系統(Step 9)/寶石+絕招+融合(Step 10：寶石欄 2 格、屬性石 40+輔助石、元素術需特殊石、義士三招絕招任務鏈、打鐵鋪 QTE 融合)/裝備(Step 11.6：5 部位防具+武器 3 槽+耐久，`rules/equip.gd` + `data/equip.json`，裝備 = 背包參照)/防具店/進階生產(Step 12：初階技能等級 1~100、5 進階技能 + `data/recipes.json` 2318 配方、許昌廚房/藥房/工房、武器耐久、自己修理 + 打鐵鋪修理服務、工具店)/天地商行自動化+捐獻(Step 13：`rules/tiandi.gd`，負重滿自動存/賣材料、自動買賣工具、小屋休息、背包「腳伕」頁；捐贈官令 `data/donation.json` → 名聲+魅力經驗；行動力 `ch.ap` 簡版)/登用武將 v1(Step 13.5：`rules/recruit.gd` + `sim/sim_recruit.gd`，Tier1 19 人城內按時辰出現、城內「調查」每日 1 次/成功嗰月封鎖、武將擂台 PK/文官三國問答、同伴 kind `gen` 單位 4 指令 + 忠誠 + 30 日到期、登用面板 + HUD 同伴框)/名聲頭銜官宅(Step 14：`rules/title.gd` + `sim/sim_office.gd`，`data/titles.json` 60 階【原】討取可跳階 + 月俸、`data/office.json` 官令 3 條每日 1 次 + 官宅貢獻換行動丹、行動力上限跟頭銜、飲水度 `ch.thirst` + 客棧喝茶、登用頭銜條件；官宅 = 許昌官宅/新野縣衙，兼捐獻處)/登用 v2 + 武將特技(Step 15：`rules/general.gd` + `data/general_skills.json`，將軍令/御賜金牌無視條件、登用成功先消耗；武將寶物 2 格同類高取代低；許昌藥膳師武將補品；同伴 6 指令加絕招/術法、唔夠 MP/SP 轉普攻；70 特技表【自訂】其中 20 項 passive 已實作，Tier1 指定、其餘按 id 固定抽)/歷史任務 + 居民委託(Step 16：豫荊 6 條歷史任務 type `history`、talk/fight `takeItems`、`pre.attr`、NPC `questOnly`/`strictWindow`、傳送門 `gate`(監獄子~丑/丁府鑰匙)、安全區打得任務 boss；武將收集冊 = 許昌老丈 6 石換、`ch.orderBook` 登用照用；`rules/commission.gd` + `sim/sim_comm.gd` + `data/commissions.json` 6 位委託人每日 1 單 打怪/收集/送信/即場修理)/地圖 B3(Step 16.5：隆中 + 草廬、驛站收費快速傳送 `rules/station.gd` + `sim/sim_station.gd`（facilities `station:true`，全部開放，車費 world.json `station`）、三顧茅廬 `hist_longzhong`（repeat `dialogs`/`dayMsg`、孔明將軍令經 `orderAlias` = 諸葛亮）)；手機 UI（三國群英傳M 風格）: `ui/touch/`(HudLayout 版面/搖桿/互動掣) + `ui/panels/`(背包/商店/角色/對話/記事，正式 Control 面板，玩家自己揀自己確認)；建角面板仍係舊 debug 版
- **地圖世界 B3（spec 12 §10，Step 16.5）**：襄陽西門 → 隆中（臥龍岡 → 草廬室內）；驛站 = 許昌/新野/汝南/宛城/襄陽；`map_draft.py --b3` 起稿
- **地圖世界 B2.5（spec 12 §9，Step 15.9）**：歷史任務地點 13 張 — 許昌北門 → 陳留郊外（西 于毒山寨、東 小沛）；汝南道東 → 汝南城（丁刺史府）；宛城道西門 → 宛城；新野西門 → 荊州地界 → 港口；新野南門 → 樊城 → 漢水渡口 → 襄陽城（監獄、南門 → 長沙）。室內 = `kind: house` + `parent`；汝南/宛城/襄陽有客棧 + 武器/防具店；`map_draft.py --b25` 起稿
- **地圖世界 B2（spec 12）**：B1 之外加汝南道/昆陽/宛城道/博望坡/新野城（新野 = 第二個新手城：客棧/武器店/防具店/兩條任務）；大地圖天下頁撳節點「自動前往」= `sim.cmd_goto_map`；多客棧（`shops.json inns`），死亡返最近客棧
- **地圖世界 B1（spec 12）**：`data/maps.json`（legend/地圖/傳送點/地標/天下節點）+ `data/maps/*.txt`（ASCII 人手地圖，一字一格）拼落 512×512 全域格仔，地圖之間隔 ≥20 格；其他數據寫 `map` + 地圖內座標，GameData 載入轉全域。A* 尋路、踩門口過圖、居民跨圖路由；UI 預渲染地圖貼圖 + 小地圖 + 地圖面板。改地圖直接改 txt（`tools/map_draft.py` 只係起稿，再跑會覆蓋；`--b2` 只起 B2 五張）；新 txt 要喺 export include_filter 範圍（`data/maps/*.txt`）
- `client/data/`：classes.json(六職，只啟用義士)、monsters.json(39 怪+spawn，area = 地圖內座標；掉落由 `tools/import_drops.py` 從原版 npc_drops.csv 生成，唔好手改)、items.json(6068 件)、recipes.json(由 `tools/import_recipes.py` 生成，唔好手改)、work.json、shops.json、maps.json、donation.json(捐獻轉換表【原】)、generals.json(由 `tools/gen_generals.py` 從 `data_src/general_npc.csv` 生成，f101 = 戰等【原】，唔好手改)、titles.json(由 `tools/gen_titles.py` 從攻略 sy2_8_4 生成，唔好手改)、office.json(官令/行動丹)、quiz_generals.json(文官問答 45 題)、general_skills.json(Step 15 特技/寶物/補品/同伴絕招術法設定，人手寫)、commissions.json(Step 16 居民委託 + 收集冊設定，人手寫)
- `legacy/server/`：舊 Node+ws server，只作參考（23 項 TS 測試仍過；`tools/export_vectors.ts` 由佢導出向量）
- **下一步**：跟 `docs/PLAN.md` §2 第一個未剔 Step（Step 17 座騎）；§1 有各 spec 核實現況
- 攻略原文 113 頁：`docs/guide/*.txt`；連結表 `docs/guide_links.tsv`

## 已定決策
- 手機單機（橫屏觸控，Android 先）；範圍 豫州+荊州，新手城 許昌/襄陽/新野
- 義士先行；戰鬥即時制，sim 權威，client 只發意圖
- NPC = LLM(API)：**LLM 只揀動作/生成話語，唔直接改數值**；分 Tier；一定要有規則/模板後備（離線可玩）；測試用 mock，唔碰網絡
- 公式全部【自訂】，放 `client/rules/` + 測試，數值放 `client/data/`；rules 保持純函數 + 數據驅動
- **架構 A2**（已完成遷移）：sim/規則/存檔全部喺 Godot(GDScript)；UI 只發 `sim.cmd_*` 意圖、聽 `event_emitted`、讀 `view_ents()`/`player_ch()`；sim 狀態 = 純資料 Dictionary，`save_string()`/`Sim.load_string()`；所有隨機經 `SimRng`（種子），測試要可重現
- **LLM**：OpenRouter（OpenAI 相容），**玩家自填 key**（本機存，唔入存檔/log），模型名可設定；B2 行為（規則主導+搭話即時+每日反思）；R1 記憶（結構化事實+摘要）
- 待決：D-3 戰局形式（見 DESIGN §8）
- 國戰 → 最後（Phase F）

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
