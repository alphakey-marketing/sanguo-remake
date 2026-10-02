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
- [x] 步驟 3 邏輯對接（2026-09-30）：xuchang_o 行走層 = 原版 walk；出生點連通 >=70%；A* 最遠路 465 步 ~100ms；PATH_CAP 6000→30000（原版大圖對角要 ~2 萬節點）。居民/捕快/連通測試暫略過 orig 圖（步驟 4 放 NPC 後恢復）。
  地面：按地圖資料值分類 (37=磚街 39=石仔庭院，截圖切塊)；up6xx 石帶永遠貼地。

## 進度 2026-09-30：步驟 4 室內圖
- `tools/import_orig_interiors.py`：匯入 28 張室內圖 + 道路圖 1922/1923（`xc<id>`，擺 oy≥860，WORLD_H=1345）。1915 兩個 mrg 都解析唔到，跳過。
- 引擎：傳送點支援 `rect`（矩形觸發區）+ `land`（落地格）。
- 入屋門 = 原版 k2 觸發區（id=室內圖 id）；工作區 600089→1923（木礦藥）、600865→1922（農漁獵）係用家指定，目標為假設。
- 無城內門（標 `orphan`，暫時去唔到）：1909 禁衛府、1912 錢莊、1917 大廳、1920、1921。
- 客棧已搬入 xc1902 (45,30)。

## 進度 (2026-10-01)
- 新局只喺原版許昌開始；舊 ASCII 圖/居民/捕快抽起 (`origStart`/`origHome`)；新手城限定許昌。
- 功能 NPC (商店/設施/客棧) 搬入原版許昌街 + 室內 (`tools/place_orig_npcs.py`，座標係估，之後人手調)。
- 功能 NPC 掛原版名 + okm sprite 編號 (`tools/set_orig_npc_names.py` → shops/facilities 嘅 `npc`)；
  原版 52xxx 人形圖包 (hsnpc01/editnpc01.mrg) 原 rar 冇 (dnpc01 嘅 52001–52007 係武器) → 暫用通用人形 (`AssetLib.npc_sid`)，搵到圖包後補圖，毋須改資料。
- 未做: 任務 NPC 換原版、文官武將搬入、野外圖 1851–1855 接口。

## 進度 (2026-10-01 後段)：全城匯入
- **城圖**：TOWNS 34 城全部匯入（許昌除外）；漢中/武都/梓潼 map22 係空殼 → 用家決定跳過。天水 xc3600 已匯。
- **設計**：每城只有一個邊緣出口 → 傳送去該城外圍 `<城id>25`（xc1925 模板實例），外圍有完整城堡模型 + 城門傳送；25 四邊連鄰城 25 (`client/data/city_links.json`)。
- **完整室內 (18 城)**：陳留、譙、汝南、洛陽、宛、小沛、下邳、平原、濮陽、河內、晉陽、新野、襄陽、長沙、桂陽、武陵、零陵、江陵、江夏（城門用標準編號 = 城id*100+NN）。
  室內名/設施由 `locations.tsv` NPC 名表自動分配 (`_FAC_KW`)；設施總表 `docs/plan/city_facilities.md`。
  商店/設施/客棧自動放置：`place_chenliu_npcs.py` → `place_city_npcs.py` → `set_orig_npc_names.py`（複製條目後綴 `_cl<城id>`）。
- **部分城 (16 城)**：北平/北海/南皮/吳/壽春/天水/安定/建業/會稽/柴桑/盧江/薊/襄平/西涼/鄴/長安 用 `6xxxxx`/`13xxxxx` 另一套門編號，data 內搵唔到房↔門對應（傳送目標喺 server 側）。
  → 只匯功曹(01)+客棧(02)，門 = 城圖最長連號 k2 門串頭兩個 (`PARTIAL`)，**門位係估，要手測**；只放官宅+客棧。其餘房暫缺。
- **world.json**：cities 由 4 增至 36（+32 原版城，pop 600/defense 40 預設值，省份人手填）。公佈欄/救災點只有許昌系舊城有，新城暫冇（災害資料照有）。
- **引擎/資料**：WORLD_H=19100、`map_idx` 改 int32（地圖 >255）、驛站車費 = base + perHop × hops（原版圖用真實 map_hops）、importer 重跑會清走舊匯入殘留 (`gone`)。
- **測試**：只跑相關 leg (maps/b3/tiandi/title/world/militia) 全 `fail 0`；冇跑全套 `run_tests.sh`。
- **未做**：錢莊/拍賣屋/賭場/監牢 模板；16 城其餘房；各城公佈欄/救災；~80 間無城門孤兒房；陳留廟/練兵場；25 外圍嘅怪物/洞穴入口；新城人口/防禦/屬性實數。

## 進度 (2026-10-02)：原版怪 + 洞穴
- **怪**：`tools/import_orig_monsters.py` 匯入 59 隻原版洞穴怪 (等級按洞穴等級帶，數值用 spec 04 模板)；缺 sprite 28 隻退回舊色塊。名單見 `docs/plan/ORIG_MONSTERS.md` (`tools/gen_monster_list.py` 生成)。
- **洞穴圖**：57 張 xx51-55 匯入 (WORLD_H=28000)；`tools/link_caves.py` 配對層間 k2 出口 id、第1層連外圍 xx25 固定洞口 (148,45)，只連有洞穴嘅 13 城。**配對係猜，要手測**。
- **外圍野怪**：按州 (攻略：荊/豫/并司 1-10、兗徐 10-20) 每種 1 隻；洞穴按 spawn_maps 怪名單 3~4 隻/種。
- **注意**：spawn_maps 嘅洞穴所屬城標籤唔可靠 (如 18xx/23xx 同名單、25xx 似攻略「譙洞窟」)；等級帶未全對上攻略；洞穴所屬外圍可能錯配。
- **未做**：按攻略重對洞穴↔城；怪等級重平衡；『兵類(敵友未明)』人形 (神射手/金盾兵…) 未入怪表；一/二轉神秘洞窟。
