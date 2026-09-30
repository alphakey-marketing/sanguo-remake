# A4a 動畫格式研究結果（2026-09-30）

## 結論：解得通 ✅（怪物 / NPC / 居民 / 馬）；玩家 role1~12 要多一步（疊層）

資料來源用 `extracted/sheets/<set>/`（已預解整張 sheet，透明底 RGBA）。`extracted/sprites/role_*` 嘅長條圖幀闊唔一致（trim 過），**唔用**。

### 排列（已驗證：怪 CP_20003、狐 npc03/31001、人形 npc05/20005）
- 檔名 `CP_<npcid><A|S|W>.CP.png`：A=Attack 攻擊、S=Stand 站立、W=Walk 行走。
- 每張 = **8 列 × 8 欄**：列 = 8 個方向，欄 = 8 幀動畫；格尺寸 = 圖寬/8 × 圖高/8（每個動作格尺寸唔同，例 20003：A 68×103、S 49×83、W 50×86）。
- 方向順序：列 0 = 朝向鏡頭（正面），之後逐列轉；具體 0~7 對應 N/NE/E… 要落 A4b 時用 8 方向逐列對 heading 校（未定，靠肉眼一次）。
- 腳掂地位置每格一致（sheet 已對齊），可直接用格底中點做錨。

### 覆蓋
- `sheets/NPC` 325 檔、`d2npc01` 526（怪，同 `monsters/`）、`dnpc01` 230、`npc02~14`、`role9901~9905`（疑座騎/戰騎，未核）。`monsters/` 有 177 個 npc id（每個 A/S/W）→ 對現有 46 隻怪應全覆蓋（A4b 出報告）。

### 玩家 role1~12：唔係 A/S/W，係疊層
- 檔名 7 位數字（`CP_1111300`、`CP_1211300`、`CP_1311300`…），role1 有 540 檔；同樣 8×8 格。抽樣：`1111300` = 人物本體（行走幀），`1311300` = 武器/特效層。
- 疑為「部位/裝備 × 動作」編碼，要疊層 + 對職業/性別/武器。**未解**，A4c 前要再做小 spike（解碼位數含義）。

### 出口判斷
- A4b（怪物動畫）✅ 可行，無阻。
- A4c：NPC/居民/武將（npc0x）✅ 可行；玩家疊層 🟡 需再 spike；退路 = 用 npc 人形 sprite 頂玩家。

工具：`tools/slice_sprites.py`（`contact` 出對照圖、`frames` 印格尺寸）。

## A4b 落地（2026-09-30）
- 方向列次序（用老鼠驗證）：**順時針 N,NE,E,SE,S,SW,W,NW = 列 0..7**（列 0 背向鏡頭、列 4 面向鏡頭）。
- 怪 → sprite：`monsters.json` 怪 id → `Npc_Client.Dat` 記錄（先 id、再 dropSrc、再同名），sprite id = 記錄 offset 150 (u16)；`npc_dat.py` 舊註解「sprite=id+10000」對怪物**唔啱**。
- 覆蓋：136 隻怪只有 **30 隻**有 sheet（sprite id 有記錄但 `extracted/sheets` 冇抽到，例：野狗 30176、野豬 30177、惡虎 30173）；`1001~1105` 一批係 remake 自訂怪，原版本無。其餘繼續紅色塊。要補全需再從 `.mrg` 抽（另開 task）。
- 客戶端：`Sim.view_ents` 加 `mdef`；`main.gd _mon_track/_draw_mon_sprite` 由位置變化推方向/行走，aggro 未郁 = 攻擊，其餘站立；8fps 循環；`AssetLib.mon_sheet(def, act)`。

## 補抽調查（2026-09-30）：缺圖係客戶端本身冇，抽唔到
- 掃晒 `Sanguo_Client/role/*.mrg` 全部 CP 名 + 全客戶端 mrg 搜 id：`sheets/` 已包含 mrg 內**全部**可用 CP（NPC 325、d2npc01 525、npc02~14 等一一對得），冇漏抽。
- 缺嘅 sprite（野狗 30176、野豬 30177、惡虎 30173、山羊 30182、瘋貓 30183、狐貍 30170、花鹿 30178、野狼 30171、花豹 30172、大熊 30174、野牛 30179、戰狂 50083、孟獲魔化 57088）喺 mrg **完全冇**；只有 `Sound/sounds4.mrg` 有佢哋嘅音效 → 圖應由後期 patch（`patchlist.txt` 嘅 Data*.zip，本機冇）提供。
- 有嘅動物 sprite 只有 30165~30169/30175/30181/30185/…（老鼠、雞等）。
- 結論：要多覆蓋只能「揀相近現有 sprite 頂替」（要用家決定）或畫/用其他素材，唔係抽取問題。

## A4c 落地（2026-09-30）
- `sheets/` 底色係實心 (40,90,60) → 導入器 `_keyed_copy` 轉透明（怪物同人形都適用）。
- 人形：`import_orig_assets.py --sets actor`：95 個 sprite；`_actor_by_name` 418 個名（Npc_Client.Dat @150，例：武將/NPC 同名）；冇專屬圖就按 role 由 `ACTOR_POOL`（civ_m/civ_f/soldier/elder，人手由 contact sheet 分類）決定性揀。
- 玩家：暫時每職業一個佔位 sprite（`ACTOR_POOL.player`），因為 role1~12 疊層碼未解。
- `main.gd`：所有 ent 追蹤方向/行走；`_draw_mon_sprite` 同時畫怪同人形；任務 NPC / 同伴武將用 `_draw_idle_actor`；冇圖 fallback 舊頭像/色塊。
- 已知：坐騎/戰騎 (role9901~9905) 未接；名字比對係整名（同名多人取先出現者）。

## A4c 座騎 (2026-09-30)
- role9901~9905 **唔係坐騎**：係龍/蝶/鶴/人形變身特效層 (7 位碼分層)，未用。
- 真馬圖 = `sheets/npc02/CP_123001~5S` (5 款披甲馬, 8x8, cell 159x169)。`imp_mount` 按毛色將 6 馬種對應 5 款 (`MOUNT_MAP`)，index `mount_S` (key=馬種)。
- `main.gd _draw_my_mount` 有圖畫 sprite (row4, 0.3 倍)，冇就用舊色塊。
- 戰騎 (war_beasts 10 種) 原版無對應 sprite，仍用舊 fallback。
