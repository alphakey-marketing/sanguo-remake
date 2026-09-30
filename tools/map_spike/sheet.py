import sys,json,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from rs import rs
from PIL import Image,ImageDraw
S=os.path.dirname(os.path.abspath(__file__))
W,H,out=int(sys.argv[1]),int(sys.argv[2]),sys.argv[3];minobj=int(sys.argv[4]);sc=float(sys.argv[5])
rows=[r for r in json.load(open(S+'/rows.json')) if r[1]==W and r[2]==H and r[0]>=minobj]
rows.sort(key=lambda r:r[3]);print(len(rows))
tw=round(48*sc)*(W//48+1);th=round(48*sc)*(H//48+1);per=5;n=20
for s in range(0,len(rows),n):
    ch=rows[s:s+n];cv=Image.new('RGB',(per*tw,((len(ch)+per-1)//per)*(th+14)),(30,30,30));d=ImageDraw.Draw(cv)
    for i,r in enumerate(ch):
        j=json.load(open(f'{S}/mx/maps/{r[3]}.json'));im=rs(j,sc)
        x,y=(i%per)*tw,(i//per)*(th+14);cv.paste(im,(x,y+14));d.text((x+2,y),f'{r[3]} o={r[0]}',fill=(255,255,0))
    cv.save(f'{out}_{s//n}.png');print(f'{out}_{s//n}.png')
