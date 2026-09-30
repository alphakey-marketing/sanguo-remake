import sys,json,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from thumb import at
from rend import spr
from PIL import Image
def rs(j,sc,tsn='grd00'):
    A=at[tsn];cols,rows=j['cols'],j['rows'];t=max(1,round(48*sc))
    W,H=int(j['width']*sc),int(j['height']*sc)
    im=Image.new('RGBA',(cols*t,rows*t),(0,0,0,255));cache={}
    for k,v in enumerate(j['tiles']):
        v&=0xfff
        if v not in cache:
            cache[v]=A.crop(((v%80)*48,(v//80)*48,(v%80)*48+48,(v//80)*48+48)).resize((t,t))
        im.paste(cache[v],((k%cols)*t,(k//cols)*t))
    sc2=t/48;sc_=sc2
    for o in sorted(j['objects'],key=lambda o:o['y']):
        p=spr(o['name'])
        if not p:continue
        s=Image.open(p).convert('RGBA');w=max(1,int(s.width*sc_));h=max(1,int(s.height*sc_))
        s=s.resize((w,h));im.paste(s,(int(o['x']*sc_),int(o['y']*sc_)),s)
    return im.convert('RGB')
if __name__=='__main__':
    j=json.load(open(sys.argv[1]));rs(j,float(sys.argv[3])).save(sys.argv[2])
