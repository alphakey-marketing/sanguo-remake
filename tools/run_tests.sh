#!/bin/sh
# 跑全部 Godot 測試: rules 對拍 + sim 場景 + autotest 端到端。任何一項失敗 exit 1
G="${GODOT:-/d/Download/Sengoku/godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
rc=0
"$G" --editor --headless --path client --quit >/dev/null 2>&1      # 重建 class_name 快取

run() {   # run <label> <args...>: 印出 [TEST]/[FAIL]/PASS 行，Godot exit code 非 0 即失敗
  label=$1; shift
  out=$("$G" --headless --path client "$@" 2>&1); code=$?
  echo "$out" | grep -E "^\[(TEST|FAIL)\]|^PASS|^FAIL"
  [ $code = 0 ] || { echo "!! $label exit $code"; rc=1; }
}
run rules --script tests/run_rules.gd
run quest --script tests/run_quest.gd
run spell --script tests/run_spell.gd
run jewel_ult --script tests/run_jewel_ult.gd
run sim --script tests/run_sim.gd
run world --script tests/run_world.gd
run monsters --script tests/run_monsters.gd
run maps --script tests/run_maps.gd
run equip --script tests/run_equip.gd
run market --script tools/market_sim.gd
run hud --script tests/run_hud.gd
run autotest -- --autotest
run uitest -- --uitest
# 掉落導入核對 (要本機有原版 npc_drops.csv，冇就跳過)
if [ -f /d/Download/sanguo/extracted/text/npc_drops.csv ]; then
  out=$(PYTHONIOENCODING=utf-8 python tools/import_drops.py --check 2>&1); code=$?
  echo "$out"
  [ $code = 0 ] || { echo "!! drops exit $code"; rc=1; }
fi

[ $rc = 0 ] && echo "ALL OK" || echo "SOME FAILED"
exit $rc
