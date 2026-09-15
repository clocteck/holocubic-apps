"""Read-only unauthenticated endpoint probes. Never print QR tokens or images."""
import requests
import json
import re
import base64
import io
from PIL import Image

s=requests.Session();s.trust_env=False
s.headers['Referer']='https://y.qq.com/'
def rpc(module,method,param,comm=None):
    r=s.post('https://u.y.qq.com/cgi-bin/musicu.fcg',json={'comm':comm or {'ct':24,'cv':0,'format':'json'},'req_0':{'module':module,'method':method,'param':param}},timeout=12)
    d=r.json();item=d.get('req_0',{});data=item.get('data',{})
    print(method, 'HTTP',r.status_code,'code',d.get('code'),item.get('code'),'keys',list(data.keys()))
    return data

qq=s.get('https://ssl.ptlogin2.qq.com/ptqrshow',params={'appid':716027609,'e':2,'l':'M','s':3,'d':72,'v':4,'daid':383,'pt_3rd_aid':100497308},timeout=12)
print('QQ QR',qq.status_code,Image.open(io.BytesIO(qq.content)).size,'signature present',bool(qq.cookies.get('qrsig')))
wx=s.get('https://open.weixin.qq.com/connect/qrconnect',params={'appid':'wx48db31d50e334801','redirect_uri':'https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/','response_type':'code','scope':'snsapi_login','state':'STATE'},timeout=12)
uuid=re.search(r'uuid=([^"&\s]+)',wx.text)
print('wechat page',wx.status_code,'uuid',bool(uuid))
if uuid:
    raw=s.get('https://open.weixin.qq.com/connect/qrcode/'+uuid[1],timeout=12)
    im=Image.open(io.BytesIO(raw.content)); print('wechat QR',raw.status_code,im.format,im.size,len(raw.content))
d=rpc('music.search.SearchCgiService','DoSearchForQQMusicMobile',{'query':'晴天','search_type':0,'num_per_page':20,'page_num':1,'highlight':False,'grp':True},{'ct':11,'cv':13020508,'v':13020508,'format':'json','tmeAppID':'qqmusic'})
print('mobile search songs',len(d.get('body',{}).get('song',{}).get('list',[])))
