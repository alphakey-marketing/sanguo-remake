"""把原版 evt_dialog 對白套入舊任務 stage.dialog (只換對白文字，唔改任務流程/位置/獎勵)。
MAP: quest_id -> {stage_idx: [conv_id, ...]}；原版 conv 欄: [0]=玩家 [1]=選項(略) [2+]=NPC。
用法: python tools/apply_orig_dialog.py [--check]   (--check = 淨驗證 conv 存在，唔寫檔)"""
import json, re, sys, collections
SRC = 'D:/Download/sanguo/extracted/text/evt_dialog_evt1.tsv'
QJ = 'client/data/quests.json'
NJ = 'client/data/quest_npcs.json'

MAP = {
    'hist_sunjian': {0: [2771, 2772], 2: [2775]},
    'hist_yudu': {0: [2806, 2808], 1: [2811, 2812]},
    'hist_chengong': {0: [2824, 2826, 2827], 2: [2831]},
    'hist_dingyuan': {0: [3184, 3186], 1: [3187], 2: [3188]},
    'hist_huanggai': {0: [2779, 2780], 1: [2791], 2: [2782]},
}

def load_convs():
    c = collections.OrderedDict()
    for l in open(SRC, encoding='utf8').read().split('\n'):
        f = l.split('\t')
        if len(f) >= 4 and f[0].isdigit() and f[2].isdigit():
            c.setdefault(int(f[0]), []).append((int(f[2]), f[3]))
    return c

def lines(conv, npc_name, speakers=None):
    out = []
    for slot, t in conv:
        if slot == 1:
            continue                                    # 選項行
        t = re.sub(r'ok_\d+', '你', t.replace('~^', '').strip())      # ok_NNN = 玩家名佔位
        if not re.search(r'[\u4e00-\u9fff]', t) or len(t) <= 4 and not re.search(r'[。！？]', t):
            continue                                    # 純表情/音效
        out.append('%s：「%s」' % ('你' if slot == 0 else (speakers or {}).get(slot, npc_name), t))
    return out

def main():
    convs = load_convs()
    qd = json.load(open(QJ, encoding='utf8'))
    names = {n['id']: n['name'] for n in json.load(open(NJ, encoding='utf8'))['npcs']}
    qs = {q['id']: q for q in qd['quests']}
    bad = 0
    for qid, sm in MAP.items():
        q = qs[qid]
        for si, ids in sm.items():
            st = q['stages'][si]
            npc = names.get(st.get('npc'), st.get('npc'))
            ls = []
            for cid in ids:
                if cid not in convs:
                    print('MISSING conv', cid); bad += 1; continue
                ls += lines(convs[cid], npc)
            if ls and '--check' not in sys.argv:
                st['dialog'] = ls
                st['origConv'] = ids
    if '--check' not in sys.argv:
        json.dump(qd, open(QJ, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    print('ok' if not bad else 'bad', len(MAP), 'quests')

if __name__ == '__main__':
    main()
