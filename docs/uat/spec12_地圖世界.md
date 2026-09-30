# Spec 12 — 地圖世界：應有 UI + 邏輯對照

> 用途：你逐項睇（應有咩 UI / 邏輯），去試，比 feedback。✅=已實作　🟡=部分　❌=未做。
> 現況權威 = spec 12 + PLAN S12 + code（`rules/path.gd`、`rules/station.gd`、`rules/disaster.gd`、`rules/clock.gd`、`sim/sim_core.gd`、`sim/sim_char.gd`、`sim/sim_station.gd`、`sim/sim.gd`、`ui/panels/map_panel.gd`、`data/maps.json` + `data/maps/*.txt`、`data/world.json`、`data/facilities.json`）。
> 注意：B1~B3 全部 ✅（*邏輯層*）。⚠️ 呢份只對照「地圖世界」核心機制；相關面板（座騎/戰騎/結婚/官宅等）各自對應 spec 08/09 等 UAT，唔喺度重複。

## ⏸️ 進度暫停點（2026-09-29）

- **已做 ✅**：地圖框架（80 map）、A*/過圖/自動尋路、驛站、天災/時辰/日夜、地圖面板（區域/天下/市價）、新手城。
- **待改（待用家）**：
  - 新手城 3 揀一已做（`cmd_set_home` + 建角頁，`run_world t_set_home` 測試）
  - 地標有 `ch.landmarks` 但冇頁面儲起再睇 → 可加「典故」頁
  - HUD 左上縮細 / 移動模式切換 = subsession 自發建議，待 confirm
- **【待決】B4**：世界 23 節點已全部 open，但正式開通州郡未定 → 開新州郡圖前問用家。

## 0. 現況總覽
- ✅ B1（地圖框架 + 許昌 + 潁川郊外 + 汝南洞窟 10 層 + A* + 過圖 + 小地圖 + 預渲染貼圖 + 區名橫幅 + 地標典故）
- ✅ B2（汝南道/昆陽/宛城道/博望坡/新野 + 大地圖撳城自動尋路 + 多客棧死亡返最近）
- ✅ B2.5（陳留郊外/于毒山寨/小沛 + 汝南城丁府 + 宛城 + 荊州地界/港口/樊城/漢水渡口/襄陽+監獄 + 長沙；本批另加洛陽/下邳/零陵）
- ✅ B3（隆中 + 草廬 + 驛站 + 三顧茅廬）
- ❌ B4 其餘州郡【待決】— 見底「待決」段

**地圖數據核實**：`maps.json` = 80 張 map、26 個 landmark、world 節點 23 個（含豫/荊/兗/徐州/司隸等）；`facilities.json` 驛站 5 個（許昌/新野/汝南/宛城/襄陽）；`world.json` 天災表 + clock + night + 三城（許昌/襄陽/新野）。
**注意**：小地圖 / 區名橫幅 / 地標彈字嘅**直接視覺效果**喺呢份標 🟡，因為要靠人手畫面核實（code 有 `MapArt.minimap`、`area_name`、`landmark` 事件，但冇咗 screenshots 證實實際顯示）。

---

## 1. 地圖結構（豫 + 荊 + 周邊）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 多地圖並排全域格仔 | — | `maps.json` OX/OY → 全域 `W×H` 網格；地圖之間留空 void | ✅ `game_data.gd` 拼圖 + `map_at/map_id_at` |
| 地形 13 種字元（`.` `,` `=` `:` `_` `%` `b` `+` `#` `H` `T` `^` `~` 空格） | — | walk 表；`#/H/T/^/~/空格` 唔行得 | ✅ legend 全齊 |
| 每張 map 自動 zone（id = map id、safe 跟地圖） | zone 名 / 顏色 | old zone id 保留（`field_1`/`runan_f1..10`/`town`） | ✅ `zone_by_id` + old id 兼容 |
| **新手城 3 揀一（許昌/襄陽/新野）** | 建角揀 hometown？ | `world.homeCity`（現值 = 許昌）；新手 spawn 喺 `_home_map().spawn` 近客棧 | ✅ `cmd_set_home` + 建角頁 `_build_home`；Lv1 先改得；有測試 |
| **先讀 80 張地圖**（含 33 張戰役/場景副本地圖） | — | 戰役/場景 `.txt` 一齊入 export | ✅ 已見 `zhangniujiao_*`、`qicai_*`、`taohuadu_*`、`shichangshi_*` 等 |
| **戰役 / 場景大地圖標示** | 天下頁顯示「戰役窗口」+「特殊場景窗口」狀態 | `sim.view_battles` / `sim.view_scenes` read-model | ✅ map_panel `_draw_world()` 頂部兩個指示框 |

| 你嘅 feedback 重點（地圖結構） |
|---|
| 1. 新手城只能由 code 決定（許昌）——你想唔想建角可以揀 3 城？ |
| 2. 天下面板「豫州 / 荊州」州界標示 + 各節點（鹽襄/洛陽/下/下邳等）睇得清楚？ |
| 3. 戰役 / 特殊場景窗口指示（喺天下頁頂）會唔會太縮埋，難發現？ |

---

## 2. 邊界過圖 + 傳送點

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| **踩 auto 傳送點自動過圖**（城門/地圖邊/洞窟樓梯） | 過圖畫面（黑屏/區名橫幅） | `portal_at`（cell→id）；只有今 tick 行咗上去先觸發；落地唔彈返 | ✅ `sim.gd _on_moved` + `cmd_travel` |
| 互動掣「傳送」（舊式，要行近） | 傳送點附近互動掣 | `cmd_travel(point_id)` 檢查 `_near` + gate | ✅ 保留 |
| 門禁（Step 16） | 入唔到原因訊息 | `_gate_why`：時辰窗口（襄陽監獄子~丑）+ 道具（丁府鑰匙） | ✅ 邏輯已通（任務後接齊道具） |
| 跨圖路由 BFS `_route_to_map` | — | 傳送點 = 邊，BFS 第一跳；居民返客棧/落野用 | ✅ `sim_char.gd` |
| 傳送點成對（`to.to==自己`）+ 全部地圖由許昌去得 | — | `_map_hops_bfs` 驗連通 | ✅ `map_hops`（-1 = 去唔到） |
| **過圖次數已知**（許昌→新野 5、許昌→襄陽 8 等） | — | BFS hops | ✅（B2/B2.5/B3 驗收覆核過） |

| 你嘅 feedback 重點（過圖） |
|---|
| 1. 踩城門 / 洞窟樓梯過圖，落地會唔會有「突然閃黑」或跳位嘅感覺？ |
| 2. 入襄陽監獄（子~丑時）+ 丁府（要鑰匙）門禁感受（spec 說留到任務 Step 16 先接收屋道具，而家試唔到實入，屬預期） |

---

## 3. A* 自動尋路 / 行走

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| A* 4 方向尋路（決定性、同分先比插入次序） | — | `RulesPath.find`：f→h→入隊次序；上限 6000 | ✅ `rules/path.gd`（次序固定 右左下上） |
| 路徑存 `e.path`（全域格），`step()` 每 tick 行一格 | 行路動畫 | `_set_dest` + `step` 移動段 | ✅ |
| `tx,ty` 被追怪改 → 作廢路徑行直線 | — | `_set_dest` 檢 `greedy_reaches` | ✅ |
| **追擊用 A***（目標視線被擋先用，上限 800） | — | `_set_dest` cap 控制 | ✅（追怪場景） |
| 怪物行直線 | — | `_think_mob` 唔用 A* | ✅ |
| A* 繞過河 / 屋 / 牆 | 見到繞路行徑 | `RulesPath.find(data.walk)` | ✅ |
| 騎馬移速 ×1.5~2 / 戰騎 | 移動更快 | `_ride_steps` `_beast_tick` | ✅（spec 07/08） |
| 中邪定身 / 吟唱斷 move | 行唔到 / 吟唱中郁 = 斷 | `_move` 檢查 status + casting | ✅ |

| 你嘅 feedback 重點（尋路） |
|---|
| 1. 自動尋路（大地圖撳城）繞河 / 行官道靚唔靚？有冇「兜大圈」或「入死巷」？ |
| 2. 騎馬行路提速感受明顯？ |
| 3. 頂死牆邊行路有冇彈跳 / 走位奇怪？ |

---

## 4. 大地圖 / 小地圖 / 地圖面板

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| **預渲染地圖貼圖**（每格 16px，程序化像素，夜晚調暗） | 當前地圖一張 Image | `MapArt` + modulate | ✅（視覺要人睇確認 → 睇「feedback」） |
| 鏡頭限當前地圖（細過畫面置中） | — | — | ✅（code 有，人手確認） |
| **小地圖**（右上 112×52，自己/怪/NPC 色） | 右上縮圖 + 自己黃/怪紅/NPC 藍 | minimap 程文化 | ✅ code（`MapArt.minimap`）＋ geors 專長顯示設施 → 視覺要人睇 |
| 撳小地圖 → 開地圖面板 | 撳縮圖彈面板 | mobile_hud 接 | ✅ |
| **地圖面板「區域」頁**：當前地圖全圖 + 地標/設施/任務 NPC/自己 + 地標名（未到過 = 「？」） | panel 第 0 頁 | `_draw_area` | ✅ |
| **地圖面板「天下」頁**：城池節點 + 路線；自己發光；未開放 = 灰；撳已開放 → 自動前往 | panel 第 1 頁 | `_draw_world` + `select_node` + `cmd_goto_map` | ✅ |
| 地圖面板「市價」頁（城際價差） | panel 第 2 頁 | `view_market_prices` | ✅（spec 05 衍生，順手加） |
| **自動尋路取消**：手動行 / 死亡取消；打怪暫停、打完繼續 | 途中訊息 | `cmd_move` 清 `goto`；`sim_ai._think_player` 無攻擊目標先 `_goto_tick` | ✅ 死亡清 goto = ✅ |
| 到達發 `goto_done` + 訊息 | 到達提示 | `_goto_tick` emit `goto_done` | ✅ |
| **格殺座標選擇目錄**：已到過地標有名，未到過 = 「？」 | 區域頁金/灰圓點 | `_draw_area` 用 `ch.landmarks` 判斷 | ✅ |

| 你嘅 feedback 重點（大地圖/小地圖） |
|---|
| 1. 小地圖位置 / 大小（右上 112×52）阻唔阻 HUD 其他掣？自己/怪/NPC 三色區得區？ |
| 2. 採用地圖「區域」頁全圖 + 地標「？」睇法啱唔啱？（未去過用「？」引仔去探） |
| 3. 天下頁：變更/路線/灰節點/「自動前往」手感；撳已開放節點彈「自動前往」掣順唔順？ |
| 4. 夜晚地圖調暗效果會唔會太暗／影響打怪？ |
| 5. 自動尋路途中被打斷（手動行/死亡/打怪）嘅反饋夠唔夠清晰？ |

**已知自動測試問題（相關）**：
- 地圖/過圖/尋路有 `tests/run_maps.gd`（B1~B2）、`run_b3.gd`（B3 驛站+三顧）、`run_battle.gd`、`run_scene.gd`；問人自動測試確認全 PASS。撳小地圖開 panel、天下頁節點圖標 = `--uitest` 觸控煙霧覆蓋。
- **潛在**：區域頁 `_draw_area` 用 `main.facilities` 過濾 `Rect2i(ox,oy,w,h)`，若設施放喺 map 邊界外一格會漏畫（防止話，屬邊緣 case）。

---

## 5. 驛站搭車（B3）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 驛站設施（5 城各一，一開始全開，唔入存檔） | 地圖上驛站 + 行事近互動掣「驛站」 | `facilities.json station:true` | ✅ |
| 車費 = base + perHop×過圖次數（30 + 15/張） | 揀目的地時顯示車費 | `RulesStation.fare`；`world.json station` | ✅ |
| 行近 → 互動掣「驛站」→ 揀目的地 → 扣金即時到目的驛站旁 | 驛站面板（目的地列表 + 車費 + 原因） | `sim_station.gd cmd_station / station_view` | ✅ |
| 同伴一齊跟車 | 同伴一齊現身 | `cmd_station` 搬埋 `_companion_of` | ✅ |
| 取消自動尋路 / 攻擊 / 吟唱 | — | `cmd_station` 清 `goto/atk_target/casting` + emit `cast_interrupted` | ✅ |
| 唔夠金 / 去錯 / 唔喺驛站 → 原因訊息 | 顯示「車費要 X 金唔夠」等 | `RulesStation.check` | ✅ |
| **戰騎「玄妙」遠程用驛站**（唔喺驛站都用） | — | `station_near==""` + `_friend_effect_active(station)` → remote 傳送 | ✅（S07c） |

| 你嘅 feedback 重點（驛站） |
|---|
| 1. 驛站互動掣 / 目的地清單 UX：車費同目的地資訊清唔清？ |
| 2. 傳送有冇「突然跳 map」而 lost 方向感？（如傳到襄陽但唔知自己喺邊） |
| 3. 同伴跟車 / 傳送斷哂唱唱左/番數值效果是否穩定？ |
| 4. 車費（許昌→襄陽 150 金）會唔會太貴 / 太便宜？ |

---

## 6. 天氣 / 季節 / 時辰 / 日夜循環 / 天災

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| **世界時鐘**：十二時辰 × 8 刻 = 96 刻/日；四季 30 日/季；`gameMinPerTick` | HUD 時辰/季節顯示 | `RulesClock` + `clock_view()` | ✅ code 齊 |
| 日夜循環（夜晚調暗） | 夜晚畫面變暗 | `_advance_clock` 更新 `is_night`；貼圖 modulate | ✅ |
| **夜怪**（天黑出，天光滅） | 夜晚見到夜怪 | `_sync_night_spawns`（時辰變時補/滅） | ✅ |
| **天災每日每城擲骰**（受季節限制，大/中/細） | 天災通知（`disaster` 事件） | `RulesDisaster.roll_day` + `_daily_hook` | ✅ |
| 大/中天災停對應 cat 商店進貨 1~3 日 | — | `shutdownEnd/shutdownCats` | ✅ |
| 天災過期移除 | — | `RulesDisaster.expire` | ✅ |
| 天災影響市場 / 救災（spec 08 已接） | (市場價 / 救災面板) | `_market_daily` + `RulesDisaster` | ✅ |
| **天文專長睇天氣**（lv≥1 + 渾天儀 26029） | 天氣列表 | `view_weather()` | 🟡 邏輯 ✅；**渾天儀來源**（fox 皮任務）留後續批次，冇道具就睇唔到 |
| 地理專長小地圖顯示設施 | 小地圖多畫設施 | `geo_unlocked()` gate | ✅ code |
| **行動力每日回復 / 俸祿 / 民心等日結** | — | `_daily_hook` 鏈 | ✅（唔屬本 spec 核心，列入確認時鐘行得） |

| 你嘅 feedback 重點（天氣/天災/時辰） |
|---|
| 1. HUD 而家長咩樣顯示時辰/季節/日夜？清楚唔清楚？（接受建議） |
| 2. 夜晚變暗 + 夜怪出現嘅節奏啱唔啱（幾晚一搵怪）？ |
| 3. 天災出現有冇彈通知？大/中天災停商店有冇預警（玩家行入先發現？） |
| 4. 天文專長想睇天氣，但渾天儀打唔到（來源留後）——你要唔要臨時商店發佢嚟試？ |

**已知自動測試問題（相關）**：
- 日夜 + 夜怪 + 天災由 `run_sim.gd` 天災 / clock 揀定測試（種子決定性）+ `--autotest` 端到端覆蓋。
- **混天儀來源**：`world.json` / 商城單機化留後（§4 S01c），天文天氣功能邏輯靠 `26029` 道具 unlock，而家冇正式掉落 → **天災/天氣 UI 只能測到「天文專長未解鎖 → 空列表」**，特殊道具解鎖後先見全貌。

---

## 7. 地標 / 區名 / 典故（歷史感）

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| **區域命名**（許田圍場/許下屯田/潁水渡口…） | 行人區彈區名橫幅 | `area_name()` 供 HUD | ✅ `area_name`（橫幅視覺要靠人睇） |
| **史蹟地標**（26 個）：開始掩藏，首次行入 → 彈典故 + 記入 `ch.landmarks` | 彈「【地標名】典故」訊息；區域頁由「？」變名 | `_on_moved` 檢 `RulesCombat.in_range` + emit `landmark` | ✅ |
| 地標冇獎勵（純典故） | — | — | ✅ 明確暫時「冇獎勵」 |

| 你嘅 feedback 重點（地標/區名） |
|---|
| 1. 行入區彈橫幅會唔會太頻密 / 遮畫面？ |
| 2. 首次踩地標彈典故（一段字）閱讀體驗點？想唔想有離場掣 / 儲起再睇？ |

---

## 8. 野外 / 洞穴 / 迷宮地圖 + 新手城

| 功能 | 應有 UI | 應有邏輯 | 現況 |
|---|---|---|---|
| 野外地圖（潁川郊外/汝南道/宛城道/隆中…）怪等級帶（博望坡南口 6 格內 Lv≤2） | 怪物分布 + 地圖面板顯示怪 Lv 範圍 | `_lv_text`（天下頁灰正常顯示怪 Lv）+ spawn zone | ✅ |
| 洞穴/迷宮（汝南洞窟 10 層 / 戰役多層 / 桃花渡 / 七彩奪寶陣 / 十常侍 26 層） | 樓梯過層 + 地圖面板層數 | 副本地圖 + `cmd_/auto` 傳送 | ✅（戰役/場景另見 spec 04/15 對照） |
| 室內地圖 `kind:house`（草廬 / 丁府 / 襄陽監獄）：安全、冇怪；`parent` = 所屬城池 | 大地圖「而家喺度」當返主城 | `_here_node()` 攞 `parent` | ✅ code |
| 免費安全區回復（城內每 N tick 回 HP/MP/SP） | 城嘢條自動慢慢回 | `_safe_regen_tick` | ✅ |
| **多客棧死亡返最近**（許昌/汝南/新野…同分 = 許昌） | 死亡復活點 | `nearest_inn(map_hops)` | ✅ `sim_char.gd` |
| 新手城 3 城（許昌 / 襄陽 / 新野）設施/居民齊 | — | `add_residents`（每城 12~20 居民）；商店/驛站/客棧 | ✅（居民 S09a / 設施各城） |
| **新地圖跟 S04/S06/S08 加** | — | 戰役/場景/專長任務地圖融入 | ✅（睇下面「地圖批次」段） |

| 你嘅 feedback 重點（野外/洞穴/新手城） |
|---|
| 1. 博望坡南口落怪難度（Lv≤2）新手起步啱唔啱順滑？ |
| 2. 洞穴 / 迷宮樓梯過層有冇「迷路」煩？map 面板層數清楚？ |
| 3. 死亡返最近客棧（潁川→許昌、博望坡→新野等）復活點啱唔啱？ |
| 4. 城內安全區回血節奏、新手城居民密度感? |

---

## 9. 地圖批次（S04/S06/S08 加嘅地圖）+ 相關 UI 欠債

- ✅ **戰役地圖**（Step 19 起，S04c）：張牛角 + 褚飛燕/李大目/張白騎/黃龍/十常侍 26 層 → `zhangniujiao_*` `chufeiyan_*` `lidamu_*` `zhangbaiqi_*` `huanglong_*` `shichangshi_*`
- ✅ **特殊場景**（S04d）：桃花渡 5 層 + 七彩奪寶陣 7 層 → `taohuadu_*` `qicai_*`（其餘 5 個留後）
- ✅ **專長/任務搬圖**（S06d/S06e）：原作豫荊以外地點一律搬去現有豫荊地圖（洛陽/下邳/零陵等都有咗）；出豫荊新地圖押後
- 🟡 **名額競爭 `title_contest_view` read-model 已備但無面板**（非地圖核心，屬官宅 spec 09 欠債，喺度提示）

---

## 已知自動測試問題（相關）

- `tests/run_maps.gd`（B1~B2：地圖檔格式/連通/過圖/尋路/存檔 roundtrip）、`run_b3.gd`（B3：驛站+三顧全線）、`run_battle.gd`、`run_scene.gd`、`run_sim.gd`（時鐘/天災）、`--autotest`（端到端）、`--uitest`（觸控煙霧：驛站等）。
- **地形 / 過圖 / 天災 全為種子驅動決定性** → 可重現。
- **無法手測**：天災/天氣睇唔晒（渾天儀來源停後）；門禁（丁府鑰匙未接任務）→ 屬預期，靠 code review 斷。
- **潛在地圖視覺**（縮圖/夜晚/區名橫幅/典故彈字）未能單靠自動測試確定 → 靠你親手畫面 feedback。

---

## 【待決】B4 其餘州郡

- PLAN §2 標 **B4 其餘州郡【待決】**；S12 未剔格 =「收集 S04~S10 期間加嘅地圖做總驗收」。
- 現況（本份核實）：世界網格已**超出純豫荊**——含 **兗州（陳留）、徐州（小沛/下邳）、司隸（洛陽）、荊州南部（零陵/長沙）** 等節點，用者已經可以透過地圖去到一啲非豫荊城（長沙/洛陽/零陵等係「搬去現有豫荊地圖」處理）。
- 問題：**邊啲州郡要喺 B4 真係正式開通 / 用邊種地圖（要多地圖+boss+quest）仍然未定**。PLAN 已有「推薦方針」（唔新開圖，搬現有）；若你想正式開 B4（例如開放更多州郡 + 各自新手城選擇），需要你決定：
  1. B4 要開放邊啲州郡（範圍）？
  2. 新手城 3 揀一（許昌/襄陽/新野）定唔定？（見 §1「新手城」🟡）
  3. 會唔會用「搬現有圖」方針，定要由 0 開新州郡地圖？
  4. 遺留地圖批次（戰役/場景未開嘅 5 個、混天儀來源、S06d 絕招任務道具來源）屬於本 spec 12 定延後。

---

## 10. UAT-feedback 實作（收到 5 點，已實作頭 4 點）

收到 5 點 feedback。已實作頭 4 點，全部經 `run_tests.sh` 相關 leg 過（maps 3410 / hud 5056 / sim / quest / world fail 0）：

| # | 需求 | 實作 | 檔案 | 現況 |
|---|---|---|---|---|
| 1 | 建角可以揀 3 城（許昌/襄陽/新野） | 建角第 1 頁加「新手城」區（3 掣），揀完搬去嗰城客棧；`cmd_set_home` 未出發 Lv1 先揀得，出發後拒改 | `sim_char.gd`（`newbie_cities`/`cmd_set_home`）＋ `sim_core.gd`（`_city_map`/`_home_map`）＋ `create_panel.gd`（`_build_home`）＋ `main.gd`（`set_home` 派送） | ✅ |
| 2 | 左上角色狀態框唔好咁大 | 角色框 244×98 → 210×84；頭像 64→46；欄位/條收細 | `hud_layout.gd`＋`mobile_hud.gd` `_draw_status` | ✅ |
| 3 | 設定揀「搖桿/撳地行」移動方式，唔好互相干擾 | 新「移動方式」設定（存 `user://settings.cfg`，默認搖桿）；搖桿 = 禁撳地行（唔同搖桿爭）＋隱搖桿 zone；撳地行 = 全畫面撳地移動 | `main.gd`（`move_mode`/settings + `_hud_tap` 門）＋ `mobile_hud.gd`（joystick zone/handle）＋ `more_panel.gd`（設定掣） | ✅ |
| 4 | 地標典故想儲起再睇 | 記事面板加第 5 tab「地標」（→ 6 tab），按地圖列出，撳 ▸▾ 展開典故全文；探過=金●、未探=☆ | `sim_quest.gd`（`view_landmarks`）＋ `quest_panel.gd`（`_landmark_section`/`_lm_row`+tab） | ✅ |
| 5a | 開通全部地圖＋實裝 NPC＋怪物 | **審計：現有 80 圖已齊** —— 全 overworld field/cave 圖都有 `monsters.json` spawn；戰役/場景 `_fN` 用各自 spawn 機制；10 城都 `add_residents`＋任務 NPC | （審計，冇改） | ✅ 已滿 |
| 5b | 新州郡（益州/成都） | **未做，下一個 tranche**（見下面「益州行前計劃」） | — | ❌ 待做 |

### 益州（成都）行前計劃（#5b，下一個 tranche）
> 現況：`monsters.json` 已有 益州刀捕校/魔使者/隱影者 等怪 def，但冇成都地圖/益州 world node。世界網格 512×640，底排最大已佔到 y=570 → **oy=590 起有 70 行空位**，可放成都批次（唔使加大 WORLD_H）。
>
> 要做（全部以 `run_maps.gd` 0-fail 做 gate，逐加逐驗）：
> 1. 新 `.txt`：`chengdu.txt`（城，仿 lingling 城牆/`+` 城門/`:` 街/`H` 屋）、`yizhou.txt`（益州郊外）
> 2. `maps.json`：加 2 map entry（`ox`/`oy`≈590+、`kind city/field`、`spawn`、`areas`）＋一段 portal 連去現有荊南（如 零陵 lingling → 保證由許昌 BFS 去得）+ 成都城↔郊外 portal 成對
> 3. `world.json`：`cities[]` 加 成都、`inns[]` 加成都客棧、`shops`/store；`facilities.json` 加 成都驛站；`residents.json` 加 成都 city count
> 4. `monsters.json` spawns：用現有益州怪 def 喺 yizhou 開 spawn；再補一兩個成都野怪等級帶
> 5. `maps.json` 世界節點：加 `chengdu`（province 益州, city, map）＋ edges 連去現有荊南節點；landmarks 加成都史蹟
> 6. `run_maps.gd`＋`--autotest` 過：地圖連通 / 傳送點成對 / 由許昌全去得 / 存檔 roundtrip 決定性
> 7. 若做新手城：`NEWBIE_CITIES` 同 create_panel 考慮加唔加成都做第 4 揀 → 需問用家
> ⚠️ 成都地圖 txt 係手繪，必須維持每行等闊＋legend 全合法＋行得格連通+Ping portal 成對，否則 `run_maps.gd` 會截出嚟——建議逐張加、逐張過，唔好一次冚齊。