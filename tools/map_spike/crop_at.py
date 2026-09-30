import sys,os,json
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from rs import rs
from PIL import Image,ImageDraw
X,Y=int(sys.argv[1]),int(sys.argv[2]);out=sys.argv[3]
CT=['Map02_02000','Map04_00500','Map04_00600','Map04_00700','Map04_00800','Map04_00900','Map04_01000']
cv=Image.new('RGB',(2*700,4*476),(0,0,0))
for i,n in enumerate(CT):
    j=json.load(open('mx/maps/%s.json'%n));im=rs(j,0.7)
    cx,cy=int(X*.7),int(Y*.7);c=im.crop((cx-350,cy-238,cx+350,cy+238))
    ImageDraw.Draw(c).text((5,5),n,fill=(255,255,0));cv.paste(c,((i%2)*700,(i//2)*476))
cv.save(out)
