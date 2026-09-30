import sys,json,os,glob
sys.path.insert(0,os.path.dirname(__file__))
from thumb import render,at
from PIL import Image
S=os.path.dirname(os.path.abspath(__file__))
idx={}
for d in sorted(glob.glob('D:/Download/sanguo/extracted/sprites/upobj_*')):
    for f in os.listdir(d):
        n=f.split('_',1)[1][:-4].lower()
        idx.setdefault(n,[]).append(os.path.join(d,f))
def spr(name):
    n=name.lower().rsplit('.',1)[0]
    return idx.get(n,[None])[0]
def full(j,scale=1.0,anchor='tl',tsn='grd00'):
    im=render(j,tsn).convert('RGBA');miss=0
    for o in sorted(j['objects'],key=lambda o:o['y']):
        p=spr(o['name'])
        if not p: miss+=1;continue
        s=Image.open(p).convert('RGBA')
        x,y=o['x'],o['y']
        if anchor=='bc': x-=s.width//2;y-=s.height
        im.alpha_composite(s,(0,0)) if False else im.paste(s,(x,y),s)
    print('missing sprites',miss,'of',len(j['objects']))
    if scale!=1: im=im.resize((int(im.width*scale),int(im.height*scale)))
    return im
if __name__=='__main__':
    j=json.load(open(sys.argv[1]));a=sys.argv[3] if len(sys.argv)>3 else 'tl'
    full(j,float(sys.argv[4]) if len(sys.argv)>4 else .5,a).convert('RGB').save(sys.argv[2])
