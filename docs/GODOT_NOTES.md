# Godot 4.7 筆記

Godot 路徑: `D:\Download\Sengoku\godot\Godot_v4.7.2-stable_win64_console.exe`（同目錄有 `export_templates/`，Android 匯出時檢查是否齊全）
參考項目（另一個 Godot 4.7 項目，已踩過坑）: `D:\Download\Sengoku\godot_game`（自動測試用 `SELFTEST=1 ... --headless --path <proj> --quit-after 600`；有 `export_presets.cfg`）

## 踩坑筆記（來自 godot_game README）
1. tscn 引用 .gd：`type="Script"`（大寫）
2. `Label.new()` 不吃參數 → 用 `set_text()`
3. 場景腳本引用 autoload class：需先跑一次 editor 匯入
4. 中文字型：`FontFile = load()`，`add_theme_font_override("font", f)`，`add_theme_font_size_override("font", N)`
5. `modulate` 用賦值；`autowrap` 用 `add_theme_constant_override`
6. 檔案讀取：`FileAccess.get_file_as_string()`
7. 函式參數不要寫 `var` 前綴（`func f(x: int)`）
8. 新增/修改 .gd 後，先跑 `--editor --headless --path <proj>` 重建快取，再跑測試

## 本項目慣例（遷移 A2 後）
- `rules/`：純函數，`static func`，無節點依賴，無全域狀態
- `sim/`：`RefCounted` 類，狀態可序列化（Dictionary/JSON），RNG 由外部注入種子
- `ui/`：只讀 sim 狀態、只發「意圖」；唔直接改 sim 內部
- 自動測試：headless 入口，輸出 `[TEST] ... ok/FAIL`，失敗 exit code ≠ 0

## 測試 / 指令
- 全部: `sh tools/run_tests.sh`（rules 向量 + sim 場景 + autotest；exit code 反映成敗）
- 單跑: `Godot --headless --path client --script tests/run_rules.gd`（或 `run_sim.gd`）；autotest: `-- --autotest`
- 手機 UI: `--script tests/run_hud.gd`（HUD 版面：夠大/唔重疊/安全區）；`-- --uitest`（觸控煙霧: 撳掣/面板/搖桿）；截圖 `Godot --path client --resolution 1280x720 -- --uishot`（要 GPU，唔好 --headless，存 user://uishot_*.png）
- 新增/改 `class_name` 檔後先跑 `--editor --headless --path client --quit`，否則 `--script` 睇唔到新 class
- `.csv` 放喺 `res://` 會被當翻譯檔匯入而出錯 → 原始 csv 放 `data_src/`（Godot 項目外）
- GDScript 唔同 JS：`roundi` 對負 .5 向外進位，要用 `MathX.js_round`；JSON 讀返嚟數字全部係 float（`Sim._intify` 還原 int）；`str` 係內建函數名，變數唔好叫 str
- 64 位整數唔好放 JSON（float 精度）；RNG 狀態用 32 位
- **觸控判斷唔好用 `Input.is_emulating_mouse_from_touch()`**：4.7 桌面都回 true。要逐個事件睇：`InputEventScreenTouch/Drag` = 手指；`InputEventMouse` 而 `device == InputEvent.DEVICE_ID_EMULATION` = 觸控模擬出嚟，忽略（唔係會一撳觸發兩次）
- 測試模擬輸入用 `Input.parse_input_event()`（座標要轉 window: `get_viewport().get_final_transform() * p`）；`Viewport.push_input()` 唔會行到 `_unhandled_input`
- Android 返回鍵: `application/config/quit_on_go_back=false` + `_notification(NOTIFICATION_WM_GO_BACK_REQUEST)`；震動要 export preset `permissions/vibrate=true`

## Sim 分層（繼承鏈）
- `sim.gd` 拆咗做 8 個檔: `sim_core -> sim_quest -> sim_char -> sim_econ -> sim_combat -> sim_skill -> sim_ai -> sim`（只有 `sim.gd` 有 `class_name Sim`，其餘用 `extends "res://sim/xxx.gd"`）
- 規矩: 每層只可以叫自己或者下層嘅 func；要叫上層嘅就將 func 搬落下層（或者搬去 `sim.gd`）
- 對外接口（`Sim.new` / `cmd_*` / `view_*` / `save_string` / `Sim.load_string` / 常量 `Sim.W`）不變

## Android APK
- 匯出: `Godot --headless --path client --export-debug "Android" build/sanguo.apk`
- 用預編模板 (`gradle_build/use_gradle_build=false`)，模板喺 `%APPDATA%/Godot/export_templates/4.7.2.stable/android_*.apk`（由 `D:\Download\Sengoku\.dl\export_templates.tpz` 抽出）
- 要 `rendering/textures/vram_compression/import_etc2_astc=true`，唔係就匯唔到
- SDK `D:/Android/Sdk`、JDK 21 `D:/Program Files/Eclipse Adoptium/jdk-21`（editor_settings-4.7.tres）；debug keystore `%APPDATA%/Godot/keystores/debug.keystore`（pass android）
- 安裝: `D:/Android/Sdk/platform-tools/adb install -r client/build/sanguo.apk`
- `client/build/`（APK / web 匯出）已 gitignore

- Godot 4.7: `trait` 係保留字，唔可以做變數名 (Parse Error: Expected variable name after "var")。
- headless 跑 `--uitest`/`--autotest` 如果 script parse error，timer 未掛上 → process 唔會自己退出；見到 hang 先 check-only: `Godot --headless --path client --check-only --script <file>`。
