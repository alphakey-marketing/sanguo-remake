# 原版地圖匯入 — 短計劃（三新手城先行）

## 已驗證
- 許昌 = Map.mrg 01900、新野 = 02700、襄陽 = 02900（`map_place_join.tsv` high）。許昌/襄陽 4000×3000，新野 3200×2400。
- 地形：tileset 一律 grd00（grd02 有黑格，grd01/03 缺格）。
- HUD 座標 = 像素。許昌截圖 (3425,741) 對上圖。
- 行走層：`.col` 物件 mask，16px 格，同我哋 TILE=16 一致，1 格對 1 格，唔使轉換。
- 物件：sprite 左上錨，按 y 排序畫。

## 方案（混合）
原版圖做視覺層，我哋 16px 格做邏輯層（行走層直接換成原版 walk）。

## 步驟
1. **匯出器** `tools/import_orig_maps.py`
   - 輸入：三城 (Map.mrg, 01900/02700/02900)。
   - 輸出 `client/data/orig_maps/<id>.json`：W,H,cols,rows,tiles[], objects[{name,x,y}], walk(16px, base64/zlib), orig:{mrg,id}。
   - 順手輸出 `client/assets/orig_maps/atlas_grd00.png`（只打包三城用到嘅 tile）+ 只匯出三城用到嘅 upobj sprite。
   - `--check`：缺格=0、物件 sprite 全有，接入 `run_tests.sh`。
2. **Godot 顯示**：新 `orig_map_view.gd`（TileMapLayer + Sprite2D，物件按 y 排序），`main.gd` 對應地圖 id 時啟用；舊 ASCII 地圖仍可用。
3. **邏輯對接**：行走層改用 orig walk；A*/尋路沿用。
4. **放置**：NPC / 客棧 / 驛站 / 城門位置，先手動定（用截圖座標對），之後再用 `okm_records.tsv` 自動化。
5. **驗證**：headless 測試（walk 尺寸、spawn 點可行走）+ 用家手測許昌。

## 未定（要你決定）
- a) 新手城畫面比例：原版 1:1 (48px tile) 定縮放？建議 1:1，鏡頭跟角色。
- b) 現有 NPC/商店位置要全部重放，工作量 = 每城 30+ 個點。先做許昌一城試水？
- c) 舊 ASCII 許昌保留做後備？建議保留到新版手測過。
- d) 夜晚色調、特效暫不做。

## 風險
- 物件 sprite 總量（三城估 1~2 千張）→ 檔案大小，匯出時統計後再定。
- 地圖入口/出口傳送點要重定（原版座標喺 evt 腳本，未解）。

## 補充（2026-09-30）
- 物件遮擋：角色 y 低於物件底邊時畫喺物件後面（按 y 排序，角色當一個 sprite 入同一排序）。第 2 步做。
- UI 換皮（小地圖/龍頭框/血條/箭頭標記）= 另一份計劃，唔喺本計劃。
- 用家決定：a) 1:1 b) 先許昌 c) 保留 ASCII 許昌 d) 夜色/特效唔做。

## 進度
- [x] 步驟 1 匯出器 `tools/import_orig_maps.py`（三城，--check 已接入 run_tests.sh）。
  實測：許昌 526 物件/145 物件圖、新野 197/95、襄陽 472/140；資產共約 33 MB（assets_orig，gitignore）；JSON 88 KB。
- [x] 步驟 2 Godot 顯示（2026-09-30）：`client/ui/orig_map.gd` + main.gd 物件遮擋；測試圖 `xuchang_o`（許昌原版，oy=644，WORLD_H=840），舊許昌 (37,1) 有臨時傳送入口。run_world 139/0 fail，截圖 map_orig 正常。
  未做：NPC/商店/城門（步驟 4）、行走精度（水邊）。
