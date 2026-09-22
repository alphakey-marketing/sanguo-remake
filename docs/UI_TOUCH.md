# 手機觸控 UI 原型（三國群英傳M 風格）

Step 3.2「手機原型檢查點」之一部分：client 加觸控輸入層，模仿《三國群英傳M》橫屏 MMORPG UX。
先做最細可用版（搖桿/攻擊/自動/背包/角色框/目標框），真機手感未驗證前唔再加嘢。

## 畫面布局（640x360 邏輯座標，自動伸縮）

| 位置 | 元素 | 群英傳M 對應 |
|---|---|---|
| 左下 55%x62% | 浮動虛擬搖桿（按下先彈出，拖住走；放手出 direction） | 左下虛擬搖桿 |
| 右下 | 普攻（大圓紅圈） | 攻擊/技能掣 |
| 右下（普攻上） | 自動掛機 toggle | 自動戰鬥掣 |
| 左上 | 角色框：頭像 + 名/Lv + 善惡 + HP/MP/SP/EXP bar + 金 | 左上方角色資訊 |
| 頂中 | 目標框（點咗怪先出：名 + Lv + HP bar） | 鎖定目標資訊 |
| 右上 | 背包掣 | 系統按鈕列 |
| 底部中央 | 日誌（最後 3 行） | 聊天/訊息列 |
| 左下角 | 開場提示（12 秒後淡出） | 新手提示 |

## 操作模型

- **按住拖 = 移動**（浮動搖桿；sim 每 tick 將目標點推前 2~4 格，揀第一個空格）
- **點怪 = 攻擊**（sim 自動追擊直至目標死；重複點自己 = 取消目標）
- **點地 = 行路**（`cmd_move`）
- **普攻掣** = 打目標，冇目標就打最近唔高自己兩級嘅怪
- **自動掣** = 掛機（打最近怪；冇怪行去野區；搖桿郁/普攻會熄自動）
- **真機多點觸控**：搖桿 + 另一隻手指點怪/點地並存
- **桌面試**：左鍵拖左下 = 搖桿，左鍵點 = 世界點擊，右鍵 = 自動（同真機邏輯一致）

## 實作

- `client/ui/touch/sango_joystick.gd` — 浮動搖桿元件（`SangoJoystick`，注意：**Godot 4.7 內置有 `VirtualJoystick` 原生 class，唔可以咁改名**）
- `client/ui/touch/mobile_hud.gd` — `MobileHud`（Control 覆蓋層）：`_input` 路由搖桿區/按鈕 → consume，其餘放行俾 `main.gd` 做世界點擊；`_draw` 畫全部 HUD
- `client/ui/main.gd` — 接線：tick loop 加 `_steer_tick()`（搖桿）/`_auto_tick()`（掛機）；`_unhandled_input` 加 ScreenTouch 世界點擊（Android 用 `Input.is_emulating_mouse_from_touch()` 分流，避免 mouse/touch 雙重處理）
- 截圖工具：`--sshot` 開場 2.5 秒後存 `user://sshot_ui.png`（要 GPU mode，`--headless` 攞唔到）

## 踩坑（已記）

1. **Godot 4.7 內置 `VirtualJoystick`**：class_name 撞原生名 → `Class "X" hides a native class`，script 靜靜唔載。改 `SangoJoystick`
2. **Control 掛喺 Node2D 下面 `size` 恒 = 0**：`.new()` 加 `set_anchors_preset(FULL_RECT)` 都冇用；座標一律 `get_viewport_rect().size`（同 main.gd 一樣）
3. **GDScript type inference**：冇回傳型別嘅 func（`_me()` 等）唔可以用 `var x := _me()`，要 `var x = _me()`
4. **Android 雙重事件**：`emulate_mouse_from_touch=true` 時 touch 會額外合成 mouse 事件，UI 同世界點擊都要分 flow，唔係會 double-trigger
5. **改咗 class_name 後要 `--editor --headless --quit` 重建 global class cache**（run_tests.sh 頭一步有做）

## 桌面快測

```sh
sh tools/run_tests.sh                      # 全部要 PASS
Godot_v4.7.2 ... --path client             # 視窗玩: 滑鼠模擬觸控
Godot_v4.7.2 ... --path client -- --sshot  # 截圖檢查佈局
```

## Android 導出（真機試手感）

前置（一次過）：
1. 裝 [Android Studio](https://developer.android.com/studio)（SDK + NDK）
2. Godot Editor → **Editor → Manage Export Templates** → 裝返 **4.7.2** 模板
3. Godot Editor → **Editor Settings → Export/Android** → 填 Android SDK 路徑
4. 「Export」按鈕附近 → **Android** → 揀 Playback 機（或插線開 USB debugging）→ **Install to Device**（首次佢會自動生成 debug keystore）

`export_presets.cfg` 已放好（arm64-v8a, 橫屏, immersive）：
```sh
Godot_v4.7.2 ... --headless --path client --export-debug "Android" build/sanguo.apk
```
> 若 editor 對 preset 有警告：刪 `export_presets.cfg`，喺 editor 手動加一次 Android preset 即可（欄位好少）。

### 字體（必做先好上真機）
Godot Android 預設字體對 CJK 可能有 tofu。落返一個 OFL 字體入專案：
- 下載 Noto Sans SC（https://fonts.google.com/noto/specimen/Noto+Sans+SC）→ `client/assets/fonts/NotoSansSC-Regular.otf`
- Project Settings → `gui/theme/custom_font` 指過去（`ThemeDB.fallback_font` 會跟埋，全 game 即時生效）

## 手感問題清單（真機填）

日期 / 機種 / 問題 / 建議：

| # | 現象 | 嚴重度 | 處理 |
|---|---|---|---|
| | | | |
| | | | |