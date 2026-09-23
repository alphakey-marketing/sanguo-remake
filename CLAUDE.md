# Sanguo Remake — 新 session 接手簡報

私人本地原型：自家代碼重做三國演義 Online 普通玩法（即時制打怪練功），**目標平台 = 手機單機**，NPC 由 LLM(API) 驅動。只本機跑，唔連任何真實伺服器。

## 先讀（按序）
1. `docs/DESIGN.md` — 整體設計 v2（手機、豫荊、LLM NPC 架構、市場模擬、待決事項）
2. `docs/PLAN.md` — 路線圖 v4（現況速覽、Phase A~F 每步驗收）
3. `docs/spec/01~11` — **完整系統邏輯規格**（角色/戰鬥/善惡/怪物/生產/任務/座騎/名聲/登用/國戰/資料對照）；改機制前先睇
4. `docs/普通玩法_系統摘要.md` — 玩法規格（【原】= 官方攻略；【自訂】= 自己設計）
5. `docs/guide/` — 攻略原文 113 頁；`README.md` — 結構同跑法

## 現況 (2026-09-21)
- **全部喺 `client/` (Godot 4.7, GDScript)**：`rules/`(純函數)、`sim/`(單機世界模擬，狀態可存檔、種子 RNG)、`ui/`(畫面/輸入)、`tests/`
- 測試：`sh tools/run_tests.sh` → rules 對拍 307 向量 + quest 81 + spell 618 + jewel/ult 118 + sim 160 + world 121 + monsters 143 + hud 版面 2394 + `--autotest` 端到端 + `--uitest` 觸控煙霧 21，全 PASS
- 功能：角色/升級/即時戰鬥/怪 AI+重生+掉落/死亡處分/10 個 bot/客棧+武器店/術法系統(Step 9)/寶石+絕招+融合(Step 10：寶石欄 2 格、屬性石 40+輔助石、元素術需特殊石、義士三招絕招任務鏈、打鐵鋪 QTE 融合)；手機 UI（三國群英傳M 風格）: `ui/touch/`(HudLayout 版面/搖桿/互動掣) + `ui/panels/`(背包/商店/角色/對話/記事，正式 Control 面板，玩家自己揀自己確認)；建角面板仍係舊 debug 版
- `client/data/`：classes.json(六職，只啟用義士)、monsters.json(5 怪+spawn)、items.json(6068 件)、shops.json；`data_src/general_npc.csv`(未接入)
- `legacy/server/`：舊 Node+ws server，只作參考（23 項 TS 測試仍過；`tools/export_vectors.ts` 由佢導出向量）
- **下一步 = Step 11**（怪物導入 npc_drops.csv 30+ 隻 + 汝南洞窟 10 層地圖 + 逃跑/群攻 AI + boss 每日重生，spec 04 §1~3/§11 2）
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
