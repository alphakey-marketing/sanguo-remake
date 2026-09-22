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
- 新增/改 `class_name` 檔後先跑 `--editor --headless --path client --quit`，否則 `--script` 睇唔到新 class
- `.csv` 放喺 `res://` 會被當翻譯檔匯入而出錯 → 原始 csv 放 `data_src/`（Godot 項目外）
- GDScript 唔同 JS：`roundi` 對負 .5 向外進位，要用 `MathX.js_round`；JSON 讀返嚟數字全部係 float（`Sim._intify` 還原 int）；`str` 係內建函數名，變數唔好叫 str
- 64 位整數唔好放 JSON（float 精度）；RNG 狀態用 32 位
