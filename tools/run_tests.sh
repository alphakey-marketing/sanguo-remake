#!/bin/sh
# 跑全部 Godot 測試: rules 對拍 + sim 場景 + autotest 端到端。任何一項失敗 exit 1
G="${GODOT:-/d/Download/Sengoku/godot/Godot_v4.7.2-stable_win64_console.exe}"
GTOUT="${GODOT_RUN_TIMEOUT:-600}"   # 每個 Godot run 硬上限 (秒)：防 smoke/test parse error 或死迴圈拖死成個 leg
cd "$(dirname "$0")/.." || exit 1
rc=0
timeout $GTOUT "$G" --editor --headless --path client --quit >/dev/null 2>&1      # 重建 class_name 快取

run() {   # run <label> <args...>: 印出 [TEST]/[FAIL]/PASS 行，Godot exit code 非 0 即失敗
  label=$1; shift
  out=$(timeout $GTOUT "$G" --headless --path client "$@" 2>&1); code=$?
  if [ $code = 124 ]; then
    echo "!! $label TIMEOUT (${GTOUT}s 冇結束，已斬) — 當失敗處理，唔會拖死 relay leg"
  fi
  echo "$out" | grep -E "^\[(TEST|FAIL)\]|^PASS|^FAIL"
  [ $code = 0 ] || { echo "!! $label exit $code"; rc=1; }
}
run rules --script tests/run_rules.gd
run quest --script tests/run_quest.gd
run hist --script tests/run_hist.gd
run group --script tests/run_group.gd
run ult --script tests/run_ult.gd
run expert --script tests/run_expert.gd
run b3 --script tests/run_b3.gd
run mount --script tests/run_mount.gd
run war_beast --script tests/run_war_beast.gd
run spell --script tests/run_spell.gd
run stealth --script tests/run_stealth.gd
run jewel_ult --script tests/run_jewel_ult.gd
run sim --script tests/run_sim.gd
run residents --script tests/run_residents.gd
run rumor --script tests/run_rumor.gd
run llm --script tests/run_llm.gd
run marry --script tests/run_marry.gd
run char --script tests/run_char.gd
run class --script tests/run_class.gd
run world --script tests/run_world.gd
run monsters --script tests/run_monsters.gd
run maps --script tests/run_maps.gd
run equip --script tests/run_equip.gd
run craft --script tests/run_craft.gd
run master --script tests/run_master.gd
run tiandi --script tests/run_tiandi.gd
run recruit --script tests/run_recruit.gd
run general --script tests/run_general.gd
run title --script tests/run_title.gd
run militia --script tests/run_militia.gd
run civic --script tests/run_civic.gd
run camp --script tests/run_camp.gd
run battle --script tests/run_battle.gd
run scene --script tests/run_scene.gd
run pk --script tests/run_pk.gd
run karma --script tests/run_karma.gd
run down --script tests/run_down.gd
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

# 配方導入核對 (recipes.json 要同 items.json 一致)
out=$(PYTHONIOENCODING=utf-8 python tools/import_recipes.py --check 2>&1); code=$?
echo "$out"
[ $code = 0 ] || { echo "!! recipes exit $code"; rc=1; }

# 登用武將導入核對 (generals.json 要同 data_src/general_npc.csv + 攻略戰等表一致)
out=$(PYTHONIOENCODING=utf-8 python tools/gen_generals.py --check 2>&1); code=$?
echo "$out"
[ $code = 0 ] || { echo "!! generals exit $code"; rc=1; }

# 頭銜表核對 (titles.json 要同攻略 sy2_8_4 一致)
out=$(PYTHONIOENCODING=utf-8 python tools/gen_titles.py --check 2>&1); code=$?
echo "$out"
[ $code = 0 ] || { echo "!! titles exit $code"; rc=1; }

[ $rc = 0 ] && echo "ALL OK" || echo "SOME FAILED"
exit $rc
