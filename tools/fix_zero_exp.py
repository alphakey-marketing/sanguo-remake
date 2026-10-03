# 任務/boss 怪 exp=0 → 10*lv+20 (用家 2026-10-03: 任務/boss 怪都要有經驗)
import json
p = 'client/data/monsters.json'
d = json.load(open(p, encoding='utf8'))
n = 0
for m in d['monsters']:
    if int(m.get('exp', 0)) == 0:
        m['exp'] = 10 * int(m['level']) + 20
        n += 1
json.dump(d, open(p, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
print('fixed', n)
