# Sanguo Remake（私人本地原型）

自家代碼重做三國演義 Online 類玩法。目標：**手機單機**遊戲（豫州+荊州），NPC 由 LLM(OpenRouter，玩家自填 key) 驅動。只喺本機跑，唔連任何真實伺服器。

## 結構
```
client/            Godot 4.7 項目 (GDScript) — 整個遊戲喺度
  rules/           純函數規則 (combat/stats/shop/mathx)，全部【自訂】數值
  sim/             單機世界模擬 (sim.gd、bot_sys.gd、sim_rng.gd、game_data.gd)；狀態可存檔、RNG 有種子
  ui/              畫面/輸入 (main.tscn/main.gd + touch/ 手機 HUD：搖桿/普攻/自動/背包/目標框)；只發意圖、聽事件
  tests/           run_rules.gd (向量對拍)、run_sim.gd (場景/決定性/存檔)
  data/            玩法數值表 (classes/monsters/shops/items.json)
  assets_placeholder/  原版頭像佔位 — 私人測試專用，見下
data_src/          尚未接入嘅原始表 (general_npc.csv)
tests/vectors/     由舊 TS rules 導出嘅測試向量 (rules.json)
tools/             run_tests.sh、export_vectors.ts、fetch_guide.py
docs/              DESIGN.md (整體設計)、PLAN.md (計劃/進度)、GODOT_NOTES.md、UI_TOUCH.md (手機 HUD/導出/手感記錄)、普通玩法_系統摘要.md
legacy/            舊 Node+ws server (已被 Godot sim 取代，只作參考；npm test 仍可跑)
```

## 跑法
```
# 開遊戲 (Godot 編輯器開 client/project.godot 按 F5，或):
D:\Download\Sengoku\godot\Godot_v4.7.2-stable_win64_console.exe --path client
# 全部測試 (rules 對拍 + sim 場景 + autotest 端到端):
sh tools/run_tests.sh
```
Godot: `D:\Download\Sengoku\godot\`。新增 class_name 後要先 `--editor --headless --path client --quit` 重建快取（`run_tests.sh` 已包含）。
更新測試向量（改咗 legacy TS rules 先需要）: `node tools/export_vectors.ts`

## 素材規則
- `client/assets_placeholder/` = 原版素材，**僅私人本地測試，唔公開、唔分發**，已喺 `.gitignore`。
- 引用一律經 `res://assets_placeholder/`。成品前換走: `grep -r assets_placeholder client/ui/*.gd` → 逐個換自製/AI 素材 → 刪成個資料夾。
