import sys,os,json,struct,zlib,glob
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,'D:/Download/sanguo/tools')
from mrg_decode import Mrg
from rs import rs
from PIL import Image,ImageDraw
import numpy as np
MX=sys.argv[1]; OUT=sys.argv[2]; SC=0.25
W='D:/Download/sanguo/extracted/maps/walk/'
CT=[('Map02','02000'),('Map04','00500'),('Map04','00600'),('Map04','00700'),('Map04','00800'),('Map04','00900'),('Map04','01000')]
ims=[]
for mrg,nm in CT:
    m=Mrg(glob.glob('D:/Download/sanguo/_archive/client_launcher_folder/Sanguo_Client/Map/%s.mrg'%mrg)[0])
    i=m.names.index(nm)
    d=open(W+'%s_%05d.walk'%(mrg,i),'rb').read()
    gw,gh=struct.unpack('<HH',d[:4]);g=np.frombuffer(zlib.decompress(d[4:]),np.uint8).reshape(gh,gw)
    j=json.load(open('%s/maps/%s_%s.json'%(MX,mrg,nm)))
    im=rs(j,SC).convert('RGBA')
    c=max(1,16*SC)
    ov=Image.new('RGBA',im.size,(0,0,0,0));dr=ImageDraw.Draw(ov)
    for y,x in zip(*np.nonzero(g)):
        dr.rectangle([x*c,y*c,x*c+c,y*c+c],fill=(255,0,0,110))
    im=Image.alpha_composite(im,ov).convert('RGB')
    ImageDraw.Draw(im).text((5,5),'%s_%s idx%d'%(mrg,nm,i),fill=(255,255,0))
    im.save('%s_%s_%s.png'%(OUT,mrg,nm));print(mrg,nm,i,im.size)
