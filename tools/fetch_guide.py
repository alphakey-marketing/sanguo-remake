# 由 Wayback 抓官方免費版攻略 (syfree.chinesegamer.net) 轉純文字，慢速、可續傳
# 用法: python fetch_guide.py links.tsv 輸出目錄
import re, sys, time, html, pathlib, urllib.request

links = [l.split('\t') for l in open(sys.argv[1], encoding='utf-8').read().splitlines() if 'syfree' in l]
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)

def clean(b: bytes) -> str:
    t = b.decode('big5', errors='replace')
    t = re.sub(r'<script.*?</script>|<style.*?</style>', '', t, flags=re.S | re.I)
    t = re.sub(r'<br\s*/?>|</p>|</div>|</tr>|</li>', '\n', t, flags=re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '', t)).replace('\xa0', ' ')
    return re.sub(r'\n\s*\n+', '\n', re.sub(r'[ \t]+', ' ', t)).strip()

fail = []
for url, title in links:
    name = url.split('/')[-1].replace('?', '_').replace('&', '_').replace('=', '')
    f = out / (name.replace('.asp', '') + '.txt')
    if f.exists() and f.stat().st_size > 50: continue
    src = 'https://web.archive.org/web/2010id_/' + url
    for attempt in range(3):
        try:
            req = urllib.request.Request(src, headers={'User-Agent': 'Mozilla/5.0 (personal research)'})
            b = urllib.request.urlopen(req, timeout=30).read()
            f.write_text(f'# {title}\n# {url}\n\n' + clean(b), encoding='utf-8')
            print('ok', name, title, len(b), flush=True); break
        except Exception as e:
            time.sleep(4 * (attempt + 1))
    else:
        fail.append((name, title)); print('FAIL', name, title, flush=True)
    time.sleep(4)
print('done, fail =', fail)
