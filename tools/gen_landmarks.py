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

# 原版新增地標 (沒有舊文，典故自寫，史實從簡): (id, 城圖 id, portal id, 名, 典故)
NEW = [
    ("xudu_temple", "xuchang_o", "xc_in_1906", "許昌廟", "許昌城內古廟，香火不絕。建安年間曹操遷都於此，百姓常來祈求戰亂早息。"),
    ("xudu_hufu", "xuchang_o", "xc_in_1908", "虎威府", "許昌武將官署，出征前諸將在此聽令。"),
    ("xudu_wangyun", "xuchang_o", "xc_in_1946", "王允府", "司徒王允舊邸。獻連環計，使董卓、呂布反目，是漢室少有的一次反擊。"),
    ("xudu_liubei", "xuchang_o", "xc_in_1947", "劉備家", "劉備客居許昌時的住所。後園種菜，以避曹操之疑，才有青梅煮酒論英雄。"),
    ("luoyang_temple", "xc2600", "xc_in_2606", "洛陽廟", "東漢故都洛陽古廟。董卓焚城遷都後，滿目瓦礫，此廟猶存。"),
    ("luoyang_drill", "xc2600", "xc_in_2607", "洛陽練兵場", "洛陽練兵場，昔日北軍五校操練之地，今多為各路豪傑練武處。"),
    ("xiangyang_temple", "xc2900", "xc_in_2906", "襄陽廟", "襄陽古廟，劉表治荊州十餘年，境內安寧，士人多來避亂。"),
    ("xiangyang_drill", "xc2900", "xc_in_2907", "襄陽練兵場", "襄陽練兵場，劉表水陸之兵在此操演，蔡瑁統領水軍。"),
]


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
    for lid, mid, pid, nm, tx in NEW:
        lx, ly = portals[pid]["land"]
        out.append({"id": lid, "map": mid, "x": lx, "y": ly, "r": 4, "name": nm, "text": tx})
    mj["landmarks"] = out
    open(D / "maps.json", "w", encoding="utf-8", newline="\n").write(json.dumps(mj, ensure_ascii=False, indent=1) + "\n")
    print("[landmarks] %d 個地標搬上原版城圖" % len(out))


if __name__ == "__main__":
    main()
