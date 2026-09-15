import json
import unittest
from pathlib import Path
from lupa import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[2]

class Host:
    def __init__(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        def from_lua(v):
            if lua_type(v) != 'table': return v
            keys=list(v.keys())
            if keys and set(keys)==set(range(1,len(keys)+1)):
                return [from_lua(v[i]) for i in range(1,len(keys)+1)]
            return {str(k):from_lua(v[k]) for k in keys}
        self.from_lua=from_lua
        def to_lua(v):
            if isinstance(v,dict): return self.lua.table_from({k:to_lua(x) for k,x in v.items()})
            if isinstance(v,list): return self.lua.table_from([to_lua(x) for x in v])
            return v
        self.to_lua=to_lua
        self.lua.globals().encode=lambda v:json.dumps(from_lua(v),ensure_ascii=False,separators=(',',':'))
        self.lua.globals().decode=lambda s:to_lua(json.loads(s))
        self.lua.globals().read_module=lambda name:(ROOT/'package'/Path(name).name).read_text(encoding='utf-8')
        self.lua.execute('''
          function dofile(path)return assert(load(read_module(path),path))()end
          json={encode=encode,decode=decode}; ms=0
          store={load=function()return nil end,save=function(_,s)saved=s;return true end}
          net={cancel=function()end}
          function net.create(url,opts)
            local c={url=url,options=opts,callbacks={}}
            function c:on(k,v)self.callbacks[k]=v end
            function c:request()net.last=self end
            function c:close()self.closed=true end
            return c
          end
          function respond(c,raw,code,headers)
            c.callbacks.headers(code or 200,headers or {})
            c.callbacks.data(code or 200,raw)
            c.callbacks.complete()
          end
          Q=dofile('provider.lua'); P=Q.new({},net,json,store,function()return ms end)
          function result(d,e)got=d;err=e end
        ''')
    def run(self,code): return self.lua.execute(code)
    def respond(self,doc,code=200,headers=None):
        raw=doc if isinstance(doc,str) else json.dumps(doc,ensure_ascii=False)
        self.lua.globals().respond(self.lua.globals().net.last,raw,code,self.to_lua(headers or {}))

class AppTests(unittest.TestCase):
    def setUp(self): self.h=Host()
    def test_firmware_gate_and_home_link(self):
        self.h.run((ROOT/'src/tests/test_firmware_gate.lua').read_text(encoding='utf-8'))
        self.assertRegex((ROOT/'package/control.html').read_text(encoding='utf-8'),r'<a href="/main"[^>]*>回到主页</a>')
    def test_syntax(self):
        for p in (ROOT/'package').glob('*.lua'):
            self.h.lua.eval('function(s)assert(load(s))end')(p.read_text(encoding='utf-8'))
    def test_ids_and_encoding(self):
        self.h.run('''assert(Q.hash33('abc')==108966); assert(Q.hash33('abc',5381)==193485963)
          assert(Q.encode('a& b')=='a%26%20b')
          assert(json.decode(Q.protect_ids('{"id":4294967295,"s":"4294967295"}')).id=='4294967295')''')
    def test_cookie_isolation(self):
        self.h.run(r'''local c=Q.cookies({['Set-Cookie']='qrsig=abc; Path=/\np_skey=def; Expires=Wed, 01 Jan 2030\nMUSIC_U=never'})
          assert(c.qrsig=='abc'and c.p_skey=='def'and c.MUSIC_U==nil)
          assert(not Q.cookie_header({uin='12\r\nx=2'}):find('x=2'))''')
    def test_top_normalization(self):
        self.h.run('P.top(26,20,result)')
        self.h.respond({'code':0,'req_0':{'code':0,'data':{'data':{'totalNum':300},'songInfoList':[{'mid':'abc123','title':'测试','interval':123,'album':{'pmid':'album_1'},'file':{'media_mid':'media123'},'singer':[{'name':'歌手'}]}]}}})
        self.h.run("assert(got.total==300 and got.songs[1].id=='abc123' and got.songs[1].dt==123000); assert(got.songs[1].al.picUrl:find('R90x90'))")
    def test_url_permissions_and_allowlist(self):
        for path,sip,valid in [('', 'https://dl.stream.qqmusic.qq.com/',False),('C400abc.m4a?vkey=x','https://dl.stream.qqmusic.qq.com/',False),('M500abc.mp3?vkey=x','https://evil.example/',False),('M500abc.mp3?vkey=x','http://dl.stream.qqmusic.qq.com/',True)]:
            self.h.run("P.url({mid='abc',media_mid='abc'},result)")
            self.h.respond({'code':0,'req_0':{'code':0,'data':{'midurlinfo':[{'purl':path}],'sip':[sip]}}})
            self.assertEqual(self.h.lua.globals().got is not None,valid)
            if valid: self.assertTrue(self.h.lua.globals().got.url.startswith('https://'))
    def test_cancel_and_timeout(self):
        self.h.run("P.top(26,0,result); old=net.last; P.cancel(); respond(old,'{}'); assert(got==nil); P.top(26,0,result); ms=21000; P.poll(); assert(not P.busy and err)")
    def test_response_limit(self):
        self.h.run("P.top(26,0,result); respond(net.last,string.rep('x',262145)); assert(got==nil and err and not P.busy)")
    def test_session(self):
        self.h.run("assert(not P.save_session({musicid='1',musickey='a;bad'})); assert(P.save_session({str_musicid='4294967295',musickey='private'})); assert(saved.musicid=='4294967295'); assert(not json.encode(P.diagnostics):find('private'))")
    def test_cover_whitelist(self):
        self.h.run("local C=dofile('covers.lua'); assert(C.MAX_BYTES==98304); assert(C.thumbnail('https://evil.com/a.jpg')==nil); assert(C.thumbnail('https://y.gtimg.cn/music/photo_new/T002R300x300M000abc_1.jpg')=='https://y.gtimg.cn/music/photo_new/T002R90x90M000abc_1.jpg')")
    def test_qr_parser(self):
        self.h.run('''local L=dofile('login.lua'); assert(L.parse("ptuiCB('66','0','','0','wait','');")==66)
          assert(L.parse('malicious()')==nil)''')
    def test_qr_cancel_and_expiry(self):
        self.h.run('''L=dofile('login.lua').new(P,function()return ms end)
          L.start(function(s,e)login_status=s end); old=net.last; L.cancel()
          respond(old,'bad'); assert(L.status=='idle' and L.image==nil)
          L.start(function(s,e)login_status=s end); respond(net.last,'\\137PNG\\r\\n\\26\\n',{},{})
        '''.replace("respond(net.last,'\\137PNG\\r\\n\\26\\n',{},{})","respond(net.last,'\\137PNG\\r\\n\\26\\n',200,{['set-cookie']='qrsig=test'})"))
        self.h.run("assert(L.status=='waiting'); ms=151000; L.poll(); assert(L.status=='expired' and L.qrsig==nil and L.image==nil)")
    def test_navigation(self):
        self.h.run("local S=dofile('model.lua').new(); S.page='library'; S.direction('horizontal',1); assert(S.tab==2); assert(S.home()=='library')")
    def test_guest_navigation_wrap(self):
        self.h.run("local S=dofile('model.lua').new(); S.page='library'; S.tab=2; S.direction('horizontal',1); assert(S.tab==1); S.tab_count=5; S.tab=5; S.direction('horizontal',1); assert(S.tab==1)")
    def test_playback_modes_and_blank_lyrics(self):
        self.h.run(r'''local B=dofile('playback.lua')
          assert(B.next_index(3,3,'sequence',true)==1)
          assert(B.next_index(2,3,'single',true)==2)
          assert(B.next_index(2,3,'single',false)==3)
          assert(B.next_index(2,3,'random',true,function()return 1 end)==3)
          local l=B.lyrics('[00:01]first\n[00:02] \n[00:03]\n[00:04]　\n[00:05]second')
          assert(#l==2 and l[2].at==5)
        ''')
    def test_high_heap_delta_does_not_stop(self):
        self.h.run('''http={DELAYACK=1};local closed=0
          local audio={state=function()return {internal_peak_delta=80000,buffer_free=100000,error=0,status=2,source_rate=44100,written_bytes=88200}end,
            close=function()closed=closed+1;return true end}
          local n={poll=function()end,cancel=function()end};local p=dofile('player.lua').new(audio,n,function()return 0 end)
          p.status='playing';p.poll();assert(p.status=='playing'and closed==0)
        ''')
    def test_catalog_memory_and_disk(self):
        self.h.run('''local files={};local disk={save=function(k,v)files[k]=v;return true end,load=function(k)return files[k]end}
          local now=function()return ms end;local epoch=function()return 1789460000 end
          local K=dofile('catalog.lua');local c=K.new(P,now,disk,epoch);c.reset(false)
          local d={songs={{id='a',mid='a'}},total=1};c.put('top26',0,d);assert(c.get('top26',0)==d)
          c.put('top26',0,d);assert(#c.save_queue==1)
          ms=2200;c.poll();assert(c.disk_writes==1)
          local c2=K.new(P,now,disk,epoch);c2.reset(false);assert(c2.get('top26',0).songs[1].id=='a');assert(c2.disk_hits==1)
        ''')
    def test_wechat_confirmation_exchange(self):
        self.h.run("L=dofile('login.lua').new(P,function()return ms end);L.start(function(s)login_status=s end,'wx')")
        self.h.respond('<img src="/connect/qrcode/testuuid"> uuid=testuuid"')
        self.h.run("respond(net.last,'\\255\\216test',200,{}); ms=2000; L.poll()")
        self.h.respond("window.wx_errcode=405;window.wx_code='testcode';")
        self.h.respond({'code':0,'req_0':{'code':0,'data':{'str_musicid':'123','musickey':'test-only','encryptUin':'enc'}}})
        self.h.run("assert(L.status=='done'and saved.login_type==1 and saved.musicid=='123'and L.image==nil)")
    def test_account_and_membership(self):
        self.h.run("P.session={musicid='123',musickey='test',encrypt_uin='enc'};P.membership(result)")
        self.h.respond({'code':0,'req_0':{'code':0,'data':{'identity':{'vip':1,'HugeVip':1},'svip':1}}})
        self.h.run("assert(got.known and got.active and got.name=='超级会员')")

if __name__=='__main__': unittest.main(verbosity=2)
