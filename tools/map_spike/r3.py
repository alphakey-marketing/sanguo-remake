import sys,os
sys.path.insert(0,'D:/Download/sanguo/tools');sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from mrg_decode import Mrg
from map_parse import parse
from rend import spr
from PIL import Image
R='D:/Download/sanguo/';sc=0.25;t=12
m=Mrg(R+'_archive/client_launcher_folder/Sanguo_Client/Map/Map.mrg')
out=[]
for nm in ('01900','02700','02900'):
    d=parse(m.blob(m.names.index(nm)));cols,rows=d['cols'],d['rows'];row=[]
    for s in ('grd00','grd02'):
        fs={int(f.split('_')[0]):f for f in os.listdir(R+'extracted/sprites/grd_'+s)};miss=0
        im=Image.new('RGBA',(cols*t,rows*t));cache={}
        for k,v in enumerate(d['tiles']):
            if v not in fs: miss+=1;continue
            if v not in cache: cache[v]=Image.open(R+'extracted/sprites/grd_%s/%s'%(s,fs[v])).convert('RGBA').resize((t,t))
            im.paste(cache[v],((k%cols)*t,(k//cols)*t))
        for n,ox,oy in sorted(d['objs'],key=lambda o:o[2]):
            p=spr(n)
            if p:
                sp=Image.open(p).convert('RGBA');sp=sp.resize((max(1,int(sp.width*sc)),max(1,int(sp.height*sc))));im.paste(sp,(int(ox*sc),int(oy*sc)),sp)
        print(nm,s,d['W'],d['H'],'缺格',miss,'/',cols*rows);row.append(im.convert('RGB'))
    out.append(row)
w,h=out[0][0].size;cv=Image.new('RGB',(w*2,h*3))
for i,r in enumerate(out):
    for j,im in enumerate(r):cv.paste(im.resize((w,h)),(j*w,i*h))
cv.save('../../docs/uat/orig_maps_spike/三城_grd00對grd02.png')
