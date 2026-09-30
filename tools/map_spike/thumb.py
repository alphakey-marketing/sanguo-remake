import sys,json,glob,os
from PIL import Image,ImageDraw
import os
S=os.path.dirname(os.path.abspath(__file__))
at={n:Image.open(f'{S}/mx/atlas_{n}.png').convert('RGBA') for n in('grd00','grd03')}
def render(j,ts_name='grd00'):
    cols,rows=j['cols'],j['rows'];A=at[ts_name]
    im=Image.new('RGB',(cols*48,rows*48),(255,0,255))
    for k,t in enumerate(j['tiles']):
        x,y=(k%cols)*48,(k//cols)*48
        t&=0xfff
        tile=A.crop(((t%80)*48,(t//80)*48,(t%80)*48+48,(t//80)*48+48))
        im.paste(tile,(x,y),tile)
    return im
if __name__=='__main__':
    W0,H0=int(sys.argv[1]),int(sys.argv[2]);out=sys.argv[3];ts=int(sys.argv[4])
    fs=[]
    for f in sorted(glob.glob(S+'/mx/maps/*.json')):
        j=json.load(open(f))
        if j['width']==W0 and j['height']==H0: fs.append((f,j))
    per=6;th=int(ts*H0/W0)
    sheets=(len(fs)+per*5-1)//(per*5)
    for s in range(sheets):
        chunk=fs[s*per*5:(s+1)*per*5]
        cv=Image.new('RGB',(per*ts,((len(chunk)+per-1)//per)*(th+14)),(30,30,30));d=ImageDraw.Draw(cv)
        for i,(f,j) in enumerate(chunk):
            im=render(j).resize((ts,th));x,y=(i%per)*ts,(i//per)*(th+14)
            cv.paste(im,(x,y+14));d.text((x+2,y),os.path.basename(f)[:-5],fill=(255,255,0))
        cv.save(f'{out}_{s}.png');print(f'{out}_{s}.png',len(chunk))
