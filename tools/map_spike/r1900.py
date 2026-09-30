import sys,os,glob
sys.path.insert(0,'D:/Download/sanguo/tools')
from mrg_decode import Mrg
from map_parse import parse
from PIL import Image
R='D:/Download/sanguo/'
m=Mrg(R+'_archive/client_launcher_folder/Sanguo_Client/Map/Map.mrg')
i=m.names.index('01900');d=parse(m.blob(i))
print(i,d['type'],d['W'],d['H'],len(d['objs']))
cols,rows=d['cols'],d['rows'];sc=0.25;t=12
out=sys.argv[1]
for s in ('grd00','grd01','grd02','grd03'):
    fs={int(f.split('_')[0]):f for f in os.listdir(R+'extracted/sprites/grd_'+s)}
    cache={};im=Image.new('RGB',(cols*t,rows*t),(255,0,255))
    for k,v in enumerate(d['tiles']):
        if v not in fs: continue
        if v not in cache: cache[v]=Image.open(R+'extracted/sprites/grd_%s/%s'%(s,fs[v])).convert('RGB').resize((t,t))
        im.paste(cache[v],((k%cols)*t,(k//cols)*t))
    im.save('%s_%s.png'%(out,s))
    # crop full-res around (3425,741)
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from rend import spr
X,Y=int(sys.argv[2]),int(sys.argv[3]);W,H=1000,680
x0,y0=X-W//2,Y-H//2
res=[]
for s in ('grd00','grd02'):
    fs={int(f.split('_')[0]):f for f in os.listdir(R+'extracted/sprites/grd_'+s)}
    im=Image.new('RGB',(W,H),(0,0,0))
    for k,v in enumerate(d['tiles']):
        cx,cy=(k%cols)*48,(k//cols)*48
        if cx+48<x0 or cx>x0+W or cy+48<y0 or cy>y0+H or v not in fs: continue
        im.paste(Image.open(R+'extracted/sprites/grd_%s/%s'%(s,fs[v])).convert('RGB'),(cx-x0,cy-y0))
    im=im.convert('RGBA')
    for n,ox,oy in sorted(d['objs'],key=lambda o:o[2]):
        p=spr(n)
        if not p: continue
        sp=Image.open(p).convert('RGBA')
        if ox>x0+W or oy>y0+H or ox+sp.width<x0 or oy+sp.height<y0: continue
        im.paste(sp,(ox-x0,oy-y0),sp)
    res.append(im.convert('RGB'))
cv=Image.new('RGB',(W,H*2))
for i,r in enumerate(res):cv.paste(r,(0,i*H))
cv.save(out+'_crop.png')
