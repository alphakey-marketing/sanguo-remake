# 計劃：用 `D:\Download\sanguo` 資源強化 sanguo_remake

> 狀態：**待用家批准**（2026-09-29）。批准前唔郁 code。
> 用家決定：優先 = 道具/UI 圖示 + 角色/怪物/NPC 動畫；資料 = 核對漏 + evt 對白補任務；素材用腳本轉入 `client/assets_orig/`；**唔需要 web build**（Godot 本機/手機 export）；美術同資料分開 session 做。

## 0. 現況 vs 資源

| 項 | remake 而家 | sanguo 有 | 差距 |
|---|---|---|---|
| 道具圖 | 28 張 `assets_placeholder/items` | `sprites/Pic_item*` 4763（`NNNN_<itemid><a/b>.png`，1510 喺 Pic_item） | 6068 物品 id 大部分冇圖 |
| UI | `ui_theme.gd` 程式畫墨啡金邊 | `Pic_menu01~28` 2525 件（按鈕/面板/bar） | 純色框 |
| 頭像 | 24 張 jpg | `Pic_npcFace1`（`<npcid>.jpg`）等 835 | 大部分武將/NPC 冇頭像 |
| 怪物 | 紅色方塊（`main.gd _draw`） | `monsters/CP_<npcid>{A,S,W}.png` 527 張（例 544×824） | 全冇動畫 |
| NPC/居民/玩家 | 色塊 / 頭像貼圖 | `sheets/role1~12`、`npc02~14`（例 496×728、1408×1360）+ `effect*` 特效 | 全冇 |
| 地圖 | 一張 map texture | `grd_grd00~03` tile 16166、`upobj_*` 2742 | 本次**唔做**（見 §6） |
| 音效 | 冇/少 | `sound/` 3 個 wav，`.mrg` 可再抽 | 可選 |

## 1. 原則

1. **腳本轉入，唔直接讀 D:\Download\sanguo**：新 `tools/import_orig_assets.py`，輸入 `--src D:\Download\sanguo\extracted`，輸出 `client/assets_orig/{items,ui,faces,monsters,sprites,fx}/`，冪等 + `--check`（同現有導入器一致，接入 `run_tests.sh`）。
2. **缺圖必 fallback**：加一個 `AssetLib`（`ui/asset_lib.gd`），`icon(item_id)`/`face(npc_id)`/`monster_frames(npc_id)` 有圖用圖，冇就用現有 placeholder / 色塊。任何 session 中途停都唔會壞遊戲。
3. **素材唔入 git 大檔**：`assets_orig/` 加 `.gitignore`，只 commit 腳本 + 索引 json（`data/asset_index.json`：id→路徑/幀資料）。用家私人本機用。
4. 生成檔（`monsters.json` 等）照 CLAUDE.md：唔手改，改導入器再跑。
5. 每 session 完 `sh tools/run_tests.sh`（UI-only diff 用針對性 leg：run_hud/uitest，見 memory）。

## 2. 美術線（Art）

### A1 — 素材管線 + AssetLib（地基，一定先做）✅ 2026-09-29
- 寫 `import_orig_assets.py` 骨架 + `asset_index.json` 格式 + `AssetLib` 帶 fallback。
- 驗收：空 `assets_orig/` 遊戲行為同今日一樣；`--check` 過。

### A2 — 道具圖示 ✅ 2026-09-30（覆蓋 6024/6114，經 template 後備；背包/商店/配方/裝備欄已接）
- 以 `Pic_item*` 檔名內嵌 item id（`10001a/b`，a/b 疑為兩尺寸/兩狀態——**先抽樣確認**）map 去 `items.json` id；轉入 `assets_orig/items/<id>.png`（統一 32×32 或原尺寸縮圖）。
- 接 `bag_panel`/商店/裝備/背包/掉落物 icon；寶石 icon（`jewel.csv`）；報告缺圖 id 清單。
- 驗收：覆蓋率報告（已配 N/6068）；bag/shop/equip 面板見圖；uitest + hud leg 過。

### A3 — UI 素材 + 頭像 ✅ 已做（頭像 66 名 + 原版木框皮，`[ui] skin="flat"` 可關；臉譜疊圖留後）
- 揀 `Pic_menu*` 入面：面板底框、按鈕、HP/MP/SP bar、頁籤、金錢/圖示；`ui_theme.gd` 加 StyleBoxTexture 版本，**設定開關**（原版皮 / 現有程式皮）方便比較。
- 頭像：`Pic_npcFace1/2/3/5`、`Pic_Face/face2` 按 npcid 對 `generals.json`/`Npc_table.tsv`，補晒武將/居民/NPC 頭像；招募/對話/同伴面板用。
- 驗收：主要面板（bag/char/recruit/office/quest）截圖過目；uitest 過。

### A4a — 動畫格式研究（spike，1 個短 session，先於 A4b）
- 呢個係全計劃最大風險：README §6 寫明 role sprite（kind 0x0b）解碼器喺主程式、`sheets/` 只預解一部分；`monsters/CP_*A/S/W` 疑係 Attack/Stand/Walk，但幀格、方向數、每幀尺寸未定。
- 做：取 3 隻怪 + 1 個 role + 1 個 npc，切圖成 contact sheet，同用家一齊確認「幀×方向×動作」排列；輸出 `docs/plan/sprite_layout.md` + 切幀腳本。
- **出口判斷**：若排列解得通 → A4b；若 sheet 係亂碼/缺 palette → 該類退回靜態單幀（用 stand 第一幀）＋頭像做居民。

### A4b — 怪物動畫（首批）
- 46 隻現有怪（`monsters.json` 嘅 npc id → `CP_<id>{A,S,W}.png`）切幀成 `SpriteFrames`；`main.gd _draw` 紅方塊改 `AnimatedSprite`/`draw_texture_region`（依 tick 選幀、面向、攻擊/行走/站立）；boss/術法怪同套。
- 驗收：46 隻怪覆蓋率；冇圖 fallback 色塊；戰鬥不卡（同屏 ≤ 50 怪 fps 量度）。

### A4c — 玩家/NPC/居民/同伴 sprite
- 玩家六職業用 `role1~12`（先確認邊個 role 係邊職/性別）；NPC/居民/武將用 `npc02~14`；同伴、座騎/戰騎（`role9901~9905`?）逐步接。**分批**：玩家 → 任務 NPC → 居民 → 座騎。
- 驗收：建角揀職業即見對應 sprite；許昌城 NPC 唔再係色塊。

### A5 — 特效（可選）
- `effect02~12`：術法/絕招/升級/掉落光效；先接 3~5 個高頻（普攻受擊、治療、升級、術法）。

### A6 — 音效（可選）
- 由 `.mrg` 再抽 Sound（`mrg_extract.py`），揀 BGM/攻擊/UI 點擊；`AudioBus` 簡單封裝。

## 3. 資料線（Data）— 獨立 session，同美術並行/交替

### D1 — 資料核對（唔改行為，出報告）
- 對比 `items.csv`(6068) / `general_npc.csv`(1261) / `npc_drops.csv` / `jewel.csv` / `material_sources.csv` vs `client/data/*.json`：缺漏、數值/名稱不一致、掉落漏配、配方材料來源孤兒。
- 產出 `docs/uat/data_audit.md`：分「導入器 bug（修導入器再跑）」「有意偏離（自訂，記錄）」「建議新增（要用家 confirm）」。
- **任何改動只經導入器 + `--check`**；有玩法影響嘅新增項先 ask_user。
- 已知待處理可順手併入：商城 price 衝突(600 vs 500)、渾天儀 26029 冇賣、箭矢 38 種只泛用、`material_ids.json` 剔走。

### D2 — evt 對白補任務
- 用 `evt_dialog_evt1/2.tsv`、`evt_chain_*.tsv`、`evt_all_strings.tsv`（138k 條）按 NPC/任務名 match 去 `quests.json`/`quest_npcs.json`：
  1. 每條現有任務找原作對白（接任務/進行中/交任務/失敗），補 `dialog` 欄；
  2. 順手解決 UAT 已知 gap：**答題後 NPC 冇對話回饋**、**任務對話冇彈幕**（`_quest_emit` 加 speech bubble）；
  3. 原作有而 remake 未有嘅任務 → 只出**候選清單**，用家揀先做。
- 工具：`tools/import_evt_dialog.py`（生成 `data/quest_dialog.json`，唔手改）+ `--check`；`quest_panel` 指引頁/對話框讀取。
- 驗收：`run_quest` 新增「每條任務有對白」測試；有文字冇對應嘅清單報告。

### D3（預留，暫唔做）— 國戰 warbtl
- 你已決定 Spec10 暫緩；只保留 `warbtl.txt` 解析結果，唔落 code。

## 4. 建議 session 次序

| # | Session | 依賴 | 風險 | 預估 |
|---|---|---|---|---|
| 1 | A1 管線 + AssetLib | — | 低 | 小 |
| 2 | A2 道具圖示 | 1 | 低 | 中 |
| 3 | D1 資料核對報告 | — | 低 | 中（可同 1~2 並行） |
| 4 | A3 頭像 + UI 皮 | 1 | 中（風格） | 中 |
| 5 | A4a 動畫格式 spike | 1 | **高** | 小 |
| 6 | A4b 怪物動畫 | 5 | 中 | 大 |
| 7 | D2 evt 對白 | — | 中（配對準確度） | 大 |
| 8 | A4c 玩家/NPC sprite | 5,6 | 中 | 大 |
| 9 | A5/A6 特效/音效 | 1 | 低 | 小~中 |

## 5. 風險 / 注意

- **動畫解碼未確定**（A4a 決定 A4b/c 成敗）；最壞情況退回靜態圖。
- 版權：原始素材只放本機，`assets_orig/` 唔入 git、唔重新分發（同 sanguo README 聲明一致）；因唔做 web，無 pck 體積問題，但手機 export 要留意包大小（建議只轉入用到嘅 id，唔全量）。
- 素材尺寸（原版 24×24 字塊風格）同現有 `TILE`（`main.gd`）比例要對，A4a 一併確認縮放規則。
- 渲染方式改動會碰 `main.gd _draw`（大檔），每次改用針對性 leg，避免全量測試（memory 規則）。

## 6. 本次明確唔做

- 地圖 tile / 建築物件替換（工程最大，你未揀）；日後可另開 A7。
- 國戰 Spec10、web build 維護。
- 改任何遊戲數值/機制（純美術 + 資料補完；有玩法影響一律先問）。

## 7. 待你確認

1. 呢個次序 OK？想唔想 D1（資料核對）排先過美術？
2. A4a 動畫 spike 出結果後，如果只解到部分（例如只得怪物冇玩家），接受「部分靜態」？
3. UI 皮 A3：預設用原版皮，定保留現有墨啡金邊做預設、原版皮做選項？
