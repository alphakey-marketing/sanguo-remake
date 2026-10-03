"""gen_landmarks.py —— 史蹟地標搬去原版城圖 (官宅門口落腳點旁)。
舊 26 個地標喺 data/archive/legacy_maps.json (舊圖座標已失效)；有對應原版城嘅 10 個搬過嚟，典故沿用舊文。
用法: python tools/gen_landmarks.py   (idempotent，只寫 maps.json 嘅 landmarks)"""
import json
from pathlib import Path

D = Path(__file__).resolve().parent.parent / "client/data"
# 舊地標 id -> (原版城圖 id, 官宅 portal id)：落腳點 = 官宅門口
MOVE = {
    "xudu_palace": ("xuchang_o", "xc_in_1901"), "chenliu_gate": ("xc1700", "xc_in_1701"),
    "xinye_yamen": ("xc2700", "xc_in_2701"), "wancheng_pailou": ("xc2800", "xc_in_2801"),
    "xiangyang_palace": ("xc2900", "xc_in_2901"), "changsha_town": ("xc2200", "xc_in_2201"),
    "luoyang_seal": ("xc2600", "xc_in_2601"), "xiapi_lubu": ("xc1500", "xc_in_1501"),
    "xiaopei_yuanmen": ("xc1400", "xc_in_1401"), "runan_ding": ("xc2000", "xc_in_2001"),
}


def main():
    mj = json.load(open(D / "maps.json", encoding="utf-8"))
    lg = json.load(open(D / "archive/legacy_maps.json", encoding="utf-8"))["landmarks"]
    portals = {p["id"]: p for p in mj["portals"]}
    out = []
    for lm in lg:
        if lm["id"] not in MOVE:
            continue
        mid, pid = MOVE[lm["id"]]
        lx, ly = portals[pid]["land"]
        out.append({"id": lm["id"], "map": mid, "x": lx, "y": ly, "r": 4, "name": lm["name"], "text": lm["text"]})
    mj["landmarks"] = out
    open(D / "maps.json", "w", encoding="utf-8", newline="\n").write(json.dumps(mj, ensure_ascii=False, indent=1) + "\n")
    print("[landmarks] %d 個地標搬上原版城圖" % len(out))


if __name__ == "__main__":
    main()
