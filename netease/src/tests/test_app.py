import ctypes as C
import hashlib
import base64
from urllib.parse import parse_qs
import json
import math
import random
import re
from PIL import Image
import struct
import zlib
from pathlib import Path
import unittest
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]

def png_fixture(w=136,h=136,size=None):
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    raw=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))
    raw+=chunk(b'IDAT',zlib.compress((b'\0'+b'\x40\x80\xc0\xff'*w)*h))
    if size is not None:
        raw+=chunk(b'tEXt',b'x'*(size-len(raw)-24))
    return raw+chunk(b'IEND',b'')

class NativeTests(unittest.TestCase):
    def test_png_userdata_descriptor_and_limits(self):
        check=self.dll.ncm_test_png_header
        check.argtypes=[C.c_void_p,C.c_size_t];check.restype=C.c_uint32
        class Descriptor(C.Structure):
            _fields_=[('header',C.c_uint32),('size',C.c_uint32),('data',C.c_void_p)]
        init=self.dll.ncm_test_png_init
        init.argtypes=[C.c_void_p,C.c_void_p,C.c_size_t,C.c_uint32]
        init.restype=None
        for raw in [png_fixture(),png_fixture(size=96*1024)]:
            source=C.create_string_buffer(raw)
            header=check(source,len(raw))
            self.assertEqual(header,2|(136<<10)|(136<<21))
            storage=C.create_string_buffer(C.sizeof(Descriptor)+len(raw))
            init(storage,source,len(raw),header)
            d=Descriptor.from_buffer(storage)
            self.assertEqual(d.data,C.addressof(storage)+C.sizeof(Descriptor))
            self.assertEqual(C.string_at(d.data,d.size),raw)
        for raw in [png_fixture(w=137),png_fixture(h=0),png_fixture()[:-1],
                    png_fixture()+b'x',png_fixture(size=96*1024+1),b'not png']:
            self.assertEqual(check(C.create_string_buffer(raw),len(raw)),0)
    @classmethod
    def setUpClass(cls):
        cls.dll = C.CDLL(str(Path(__file__).parent / "build/ncm_test.dll"))
        cls.dll.ncm_eapi.argtypes = [C.c_char_p, C.c_char_p, C.c_size_t]
        cls.dll.ncm_eapi.restype = C.c_void_p
        cls.crt = C.CDLL("ucrtbase")
        cls.crt.free.argtypes = [C.c_void_p]

    def test_eapi_vectors(self):
        for path, doc in [("/api/login/qrcode/unikey", {"type": 3, "e_r": False}),
                          ("/api/song/enhance/player/url/v1", {"ids": "[123]", "level": "standard", "encodeType": "mp3"}),
                          ("/api/test", {"text": "中文", "padding": "x"*8192})]:
            raw=json.dumps(doc,ensure_ascii=False,separators=(",",":")).encode()
            digest=hashlib.md5(b"nobody"+path.encode()+b"use"+raw+b"md5forencrypt").hexdigest().encode()
            plain=path.encode()+b"-36cd479b6b5-"+raw+b"-36cd479b6b5-"+digest
            pad=16-len(plain)%16
            encrypt=Cipher(algorithms.AES(b"e82ckenh8dichen8"),modes.ECB()).encryptor()
            expected=b"params="+(encrypt.update(plain+bytes([pad])*pad)+encrypt.finalize()).hex().upper().encode()
            ptr=self.dll.ncm_eapi(path.encode(),raw,len(raw))
            self.assertTrue(ptr)
            self.assertEqual(C.string_at(ptr),expected)
            self.crt.free(ptr)

    def test_non_power_of_two_ring_wrap(self):
        capacity=384*1024
        ring=C.create_string_buffer(capacity)
        write=self.dll.ncm_test_ring_write;read=self.dll.ncm_test_ring_read
        for fn in [write,read]:
            fn.argtypes=[C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32];fn.restype=C.c_uint32
        rng=random.Random(21)
        position=capacity-3
        total=0xfffffff0
        for n in [0,1,3,6144,capacity]+[rng.randrange(1,9000)for _ in range(200)]:
            raw=bytes(rng.randrange(256)for _ in range(n))
            src=C.create_string_buffer(raw);dst=C.create_string_buffer(n)
            end=write(ring,position,src,n)
            self.assertEqual(read(ring,position,dst,n),end)
            self.assertEqual(dst.raw,raw)
            self.assertEqual(end,(position+n)%capacity)
            position=end;total=(total+n)&0xffffffff

    def test_qr(self):
        dll=self.dll
        dll.qrcodegen_encodeText.restype=C.c_bool
        dll.qrcodegen_getModule.restype=C.c_bool
        qr=C.create_string_buffer(4096);tmp=C.create_string_buffer(4096)
        self.assertTrue(dll.qrcodegen_encodeText(b"https://music.163.com/login?codekey=abc123",tmp,qr,1,1,10,-1,True))
        n=dll.qrcodegen_getSize(qr)
        self.assertGreaterEqual(n,21)
        self.assertTrue(dll.qrcodegen_getModule(qr,0,0))
        self.assertFalse(dll.qrcodegen_getModule(qr,1,1))
        self.assertTrue(dll.qrcodegen_getModule(qr,3,3))

    def test_doubled_output_and_saturation(self):
        gain=self.dll.ncm_test_output_gain
        gain.argtypes=[C.c_uint32];gain.restype=C.c_float
        output=self.dll.ncm_test_output_sample
        output.argtypes=[C.c_float,C.c_uint32,C.POINTER(C.c_uint32)]
        output.restype=C.c_int16
        for volume in [0,1,25,50,100]:
            previous_gain=65534.0*volume*.01
            self.assertAlmostEqual(gain(volume),previous_gain*2,delta=.02)
            clipped=C.c_uint32(0)
            for sample in [-.1,0,.1]:
                self.assertAlmostEqual(output(sample,volume,C.byref(clipped)),sample*previous_gain*2,delta=1.1)
            self.assertEqual(clipped.value,0)
        clipped=C.c_uint32(0)
        self.assertEqual(output(1,100,C.byref(clipped)),32112)
        self.assertEqual(output(-1,100,C.byref(clipped)),-32112)
        self.assertEqual(clipped.value,2)

    def test_weapi_vectors(self):
        self.dll.ncm_weapi.argtypes=[C.c_char_p,C.c_size_t]
        self.dll.ncm_weapi.restype=C.c_void_p
        raw=b'{"uid":123,"limit":20,"csrf_token":""}'
        def encrypt(text,key):
            pad=16-len(text)%16
            cipher=Cipher(algorithms.AES(key),modes.CBC(b"0102030405060708")).encryptor()
            return base64.b64encode(cipher.update(text+bytes([pad])*pad)+cipher.finalize())
        expected=encrypt(encrypt(raw,b"0CoJUm6Qyw8W8jud"),b"CubicMusic2026S3").decode()
        ptr=self.dll.ncm_weapi(raw,len(raw))
        self.assertTrue(ptr)
        form=parse_qs(C.string_at(ptr).decode())
        self.crt.free(ptr)
        self.assertEqual(form["params"][0],expected)
        self.assertEqual(len(form["encSecKey"][0]),256)

    def test_dsp(self):
        class Biquad(C.Structure):
            _fields_=[(x,C.c_float) for x in ["b0","b1","b2","a1","a2","z1","z2"]]+[("active",C.c_int)]
        class Effects(C.Structure):
            _fields_=[("gain10",C.c_int*5)]+[(x,C.c_int)for x in ["hpf_hz","bass","mix1000","drive1000","low_hz","high_hz","out_low_hz","out_high_hz"]]
        class DSP(C.Structure):
            _fields_=[("eq",Biquad*5)]+[(x,Biquad)for x in ["hpf","extract_hp","extract_lp","output_hp","output_lp"]]+[("settings",Effects)]+[(x,C.c_float)for x in ["headroom","mix","drive"]]+[("rate",C.c_uint32),("clipped",C.c_uint32)]
        self.dll.ncm_dsp_configure.argtypes=[C.POINTER(DSP),C.POINTER(Effects),C.c_uint32]
        self.dll.ncm_dsp_sample.argtypes=[C.POINTER(DSP),C.c_float]
        self.dll.ncm_dsp_sample.restype=C.c_float
        fx=Effects((C.c_int*5)(0,0,0,0,0),0,0,0,3500,50,180,120,600)
        d=DSP();self.dll.ncm_dsp_configure(C.byref(d),C.byref(fx),44100)
        self.assertTrue(all(not b.active for b in d.eq))
        self.assertAlmostEqual(self.dll.ncm_dsp_sample(C.byref(d),0.2),0.2,places=6)
        fx.gain10[:]=[60,36,-14,-10,5];fx.bass=1;fx.mix1000=250;fx.hpf_hz=100
        for rate in [22050,44100,48000]:
            self.dll.ncm_dsp_configure(C.byref(d),C.byref(fx),rate)
            for i in range(rate):
                y=self.dll.ncm_dsp_sample(C.byref(d),math.sin(i*2*math.pi*80/rate))
                self.assertTrue(math.isfinite(y))
                self.assertLessEqual(abs(y),0.980001)

class LuaTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().ROOT=ROOT.as_posix()
        # Windows Lua narrow fopen cannot open the Chinese workspace path.
        self.lua.globals().read_source=lambda p: Path(p).read_text(encoding="utf-8")
        self.lua.execute("dofile=function(p)return assert(load(read_source(p),p))()end")

    def test_syntax(self):
        load=self.lua.eval("load")
        for path in (ROOT/"package").glob("*.lua"):
            value=load(path.read_text(encoding="utf-8"),str(path))
            self.assertFalse(isinstance(value,tuple),f"{path}: {value}")

    def test_firmware_gate_and_home_link(self):
        self.lua.execute((ROOT/'src/tests/test_firmware_gate.lua').read_text(encoding='utf-8'))
        self.assertRegex((ROOT/'package/control.html').read_text(encoding='utf-8'),r'<a href="/main"[^>]*>回到主页</a>')

    def test_navigation(self):
        self.lua.execute("""
          local s=dofile(ROOT..'/package/model.lua').new()
          assert(s.home()=='login')
          s.page='library'
          s.direction('horizontal',-1);assert(s.tab==3)
          s.direction('horizontal',1);assert(s.tab==1)
          s.direction('vertical',1);assert(s.page=='about')
          assert(s.home()=='player')
          s.direction('vertical',1);assert(s.page=='player')
          s.direction('vertical',-1);assert(s.page=='about')
          s.direction('vertical',1);assert(s.page=='player')
          assert(s.direction('horizontal',-1)=='previous')
          assert(s.home()=='pause')
          local a,d=s.gesture(30,0,1000);assert(a=='horizontal' and d==1)
          assert(s.gesture(35,0,2000)==nil)
          s.gesture(0,0,2100)
          a,d=s.gesture(0,-30,2800);assert(a=='vertical' and d==-1)
          s.page='songs';s.items={{},{},{}};s.cursor=1
          s.direction('horizontal',-1);assert(s.cursor==3)
          s.direction('vertical',1);assert(s.page=='library')
        """)

    def test_provider(self):
        self.lua.execute((ROOT/"src/tests/test_provider.lua").read_text(encoding="utf-8"))

    def test_thumbnail_retry_and_audio_priority(self):
        self.lua.execute((ROOT/'src/tests/test_covers.lua').read_text(encoding='utf-8'))

    def test_sd_cover_fifo_and_recovery(self):
        self.lua.execute((ROOT/'src/tests/test_cover_disk.lua').read_text(encoding='utf-8'))

    def test_lyric_states_retries_and_blank_lines(self):
        self.lua.execute((ROOT/'src/tests/test_lyrics.lua').read_text(encoding='utf-8'))

    def test_browser_list_survives_playback(self):
        self.lua.execute((ROOT/'src/tests/test_web_list.lua').read_text(encoding='utf-8'))

    def test_library_cache_background_and_switching(self):
        self.lua.execute((ROOT/'src/tests/test_library_cache.lua').read_text(encoding='utf-8'))

    def test_account_logout_and_play_modes(self):
        self.lua.execute((ROOT/'src/tests/test_account_modes.lua').read_text(encoding='utf-8'))

    def test_main_default_favorites_modes_and_logout(self):
        self.lua.execute((ROOT/'src/tests/test_main_flow.lua').read_text(encoding='utf-8'))

    def test_png_network_sd_and_96k_limit(self):
        self.lua.globals().PNG_SAMPLE=png_fixture(w=92,h=92,size=25940)
        self.lua.globals().PNG_MAX=png_fixture(size=96*1024)
        self.lua.globals().PNG_OVER=png_fixture(size=96*1024+1)
        self.lua.execute((ROOT/'src/tests/test_png.lua').read_text(encoding='utf-8'))

    def test_large_ids_survive_host_json_boundary(self):
        protect=self.lua.execute("return dofile(ROOT..'/package/provider.lua').protect_ids")
        payload={'code':200,'account':{'id':98765432109},'ids':[2147483647,2147483648,4294967295,98765432109],
                 'caption':'escaped \\" 98765432109 and \\path','small':12,'negative':-2147483649,
                 'fraction':3000000000.5,'scientific':1e30,'empty':None}
        encoded=json.dumps(payload,ensure_ascii=False)
        parsed=json.loads(protect(encoded))
        self.assertEqual(parsed['account']['id'],'98765432109')
        self.assertEqual(parsed['ids'],[2147483647,'2147483648','4294967295','98765432109'])
        for field in ['caption','small','negative','fraction','scientific','empty','code']:
            self.assertEqual(parsed[field],payload[field])
        self.assertEqual(json.loads(protect('[98765432109,"98765432109",-1,0]')),['98765432109','98765432109',-1,0])

    def test_library_sources_and_order(self):
        self.lua.execute("""
          local lib=dofile(ROOT..'/package/library.lua')
          assert(table.concat(lib.titles,',')=='收藏,最近播放,每日推荐')
          local ids,songs=lib.likes({ids={123,'98765432109',123,-1,0}})
          assert(#ids==2 and ids[2]=='98765432109' and #songs==0)
          assert(lib.likes({})==nil)
          ids=lib.likes({ids={}});assert(#ids==0)
          ids,songs=lib.recent({data={list={
            {data={id='98765432109',name='最新'}},
            {data={id=123,name='之前'}},
            {data={id='98765432109',name='重复'}},
          }}})
          assert(#ids==2 and ids[1]=='98765432109' and songs[2].name=='之前')
          ids,songs=lib.recent({data={list={}}});assert(#ids==0 and #songs==0)
          assert(lib.recent({data={}})==nil)
        """)

    def test_five_line_lyrics_and_cover(self):
        self.lua.execute("""
          local v=dofile(ROOT..'/package/ui_view.lua')
          assert(v.rate({output_rate=44100})=='44.1k')
          assert(v.rate({output_rate=48000})=='48k')
          assert(v.rate(nil)=='--k')
          local lines={}
          for i=1,8 do lines[i]={at=i*10,text='line'..i}end
          local rows,index=v.lyrics(lines,41)
          assert(#rows==5 and index==4 and rows[3]=='line4')
          assert(rows[1]=='line2' and rows[5]=='line6')
          rows=v.lyrics(nil,0);assert(#rows==5 and rows[3]=='暂无歌词')
          assert(v.cover({page='player'},{song={al={picUrl='album'}},list_cover='playlist'})=='album')
        """)

    def test_device_clock_and_fixed_lyric_baselines(self):
        # Fail explicitly if regenerated fonts require updated baseline offsets.
        for size,ascent in [(13,13),(16,22)]:
            header=(ROOT/f'package/font/ui{size}.bin').read_bytes()[:20]
            self.assertEqual(int.from_bytes(header[16:18],'little'),ascent)
        self.lua.execute("""
          local v=dofile(ROOT..'/package/ui_view.lua')
          assert(v.clock(nil)=='--:--')
          assert(v.clock({getlocal=function()error('unavailable')end})=='--:--')
          assert(v.clock({getlocal=function()return {year=1970,hour=8,min=0}end})=='--:--')
          local display,dst=v.clock({getlocal=function()return {year=2026,hour=9,min=5,dst=1}end})
          assert(display=='09:05' and dst==true) -- already DST, no extra hour
          display,dst=v.clock({getlocal=function()return {year=2026,hour=23,min=59,dst=0}end})
          assert(display=='23:59' and dst==false)
          local prior
          for row=1,5 do
            local y,height,baseline=v.lyric_row(row)
            assert(height==31 and y+(row==3 and 22 or 13)==baseline)
            if prior then assert(baseline-prior==30)end
            prior=baseline
          end
        """)

    def test_staged_ui(self):
        self.lua.execute("""
          local loaded,objects,nextid,writes={},{},0,0
          local function create()
            nextid=nextid+1;objects[nextid]={};return nextid
          end
          local function noop()writes=writes+1 end
          LV_PART_MAIN=0;LV_OBJ_FLAG_HIDDEN=1;LV_OBJ_FLAG_SCROLLABLE=2
          LV_TEXT_ALIGN_CENTER=1;LV_TEXT_ALIGN_RIGHT=2;LV_TEXT_ALIGN_LEFT=0
          LV_FONT_MONTSERRAT_14=14
          lv_scr_act=function()return 0 end
          for _,n in ipairs({'lv_obj_clean','lv_obj_clear_flag','lv_obj_add_flag',
            'lv_obj_set_style_bg_color','lv_obj_set_style_bg_opa','lv_obj_set_pos',
            'lv_obj_set_width','lv_obj_set_height','lv_obj_set_size','lv_obj_set_style_text_font',
            'lv_obj_set_style_text_color','lv_label_set_long_mode','lv_obj_set_style_text_align',
            'lv_obj_remove_style_all','lv_img_set_src','lv_img_set_pivot','lv_img_set_zoom','lv_font_free'})do _G[n]=noop end
          lv_obj_create=create;lv_label_create=create;lv_img_create=create
          lv_img_set_src=function(id,src)
            if id==guard_image then assert(objects[id].hidden,'source replaced while visible')end
            writes=writes+1;objects[id].src=src
            objects[id].pivot={68,68}
          end
          lv_img_set_pivot=function(id,x,y)writes=writes+1;objects[id].pivot={x,y}end
          lv_obj_set_pos=function(id,x,y)writes=writes+1;objects[id].pos={x,y}end
          lv_obj_set_size=function(id,w,h)writes=writes+1;objects[id].width=w;objects[id].height=h end
          lv_obj_set_height=function(id,h)writes=writes+1;objects[id].height=h end
          lv_label_set_long_mode=function(id,mode)writes=writes+1;objects[id].mode=mode end
          lv_img_set_zoom=function(id,z)writes=writes+1;objects[id].zoom=z end
          lv_obj_add_flag=function(id,flag)if flag==LV_OBJ_FLAG_HIDDEN then objects[id].hidden=true end end
          lv_obj_clear_flag=function(id,flag)
            if flag==LV_OBJ_FLAG_HIDDEN then
              if id==guard_image then assert(objects[id].src~=nil,'revealed empty image')end
              objects[id].hidden=false
            end
          end
          lv_label_set_text=function(id,v)writes=writes+1;objects[id].text=v end
          lv_font_load=function(path)loaded[#loaded+1]=path;return #loaded+100 end
          local original=dofile
          dofile=function(path)return original((path:gsub('/sd/apps/netease',ROOT..'/package')))end
          local u=dofile(ROOT..'/package/ui.lua')()
          assert(not u.ready and #loaded==1 and loaded[1]:find('boot13'))
          assert(not u.load_next() and #loaded==2 and loaded[2]:find('ui13'))
          assert(not u.load_next() and #loaded==3 and loaded[3]:find('ui16'))
          assert(u.load_next() and u.ready)
          guard_image=u.art
          local s={page='player',index=1,queue={1},items={},cursor=1,tab=1}
          local a={error='',message='',player={status='idle',position=0}}
          u.render(s,a);assert(#u.lines==5 and objects[u.lines[3]].text=='暂无歌词')
          s.page='about';a.nickname='昵称';a.uid=1;u.render(s,a)
          assert(objects[u.account].text=='昵称')
          s.page='library';u.render(s,a)
          s.page='playlists';u.render(s,a)
          s.page='login';u.render(s,a)
          s.items={};for i=1,21 do s.items[i]={name='song'..i}end
          a.message='已登录'
          for _,page in ipairs({'playlists','songs','library','player','about','login'})do
            s.page=page;u.render(s,a)
            local before=writes
            for i=1,10 do u.render(s,a)end
            assert(writes==before,page..': unchanged UI wrote '..(writes-before)..' times')
          end
          s.page='songs';s.cursor=1;u.render(s,a)
          assert(objects[u.badge].text=='1 / 21')
          assert(objects[u.time].text=='左右选择 · 上下返回')
          s.cursor=2;u.render(s,a);assert(objects[u.badge].text=='2 / 21')
          s.page='player';a.song={dt=120000};u.render(s,a)
          a.player.position=7;u.render(s,a)
          assert(objects[u.time].text=='00:07 / 02:00')
          a.clock_text='09:05';a.player.stats={output_rate=44100};u.render(s,a)
          assert(objects[u.badge].text=='09:05 · 44.1k')
          a.clock_text='09:06';u.render(s,a)
          assert(objects[u.badge].text=='09:06 · 44.1k')
          local baseline
          for row,o in ipairs(u.lines)do
            local current=objects[o].pos[2]+(row==3 and 22 or 13)
            if baseline then assert(current-baseline==30)end
            baseline=current
          end
          a.lyrics={{at=0,text=string.rep('长句',100)},{at=10,text='下一行'}}
          a.player.position=11;u.render(s,a)
          assert(objects[u.lines[3]].pos[2]+22==116)
          a.song.name=string.rep('长歌名',40);u.render(s,a)
          assert(objects[u.title].height==36 and objects[u.title].mode==1)
          assert(objects[u.title].pos[2]+objects[u.title].height<objects[u.sub].pos[2])
          assert(objects[u.sub].pos[2]+objects[u.sub].height<=198)
          local raw='cover1';local dimensions={width=136,height=136}
          a.covers={get=function()return raw,dimensions end}
          u.render(s,a)
          assert(objects[u.art].pivot[1]==0 and objects[u.art].pivot[2]==0)
          assert(objects[u.art].pos[1]==12 and objects[u.art].pos[2]==40)
          local before=writes;u.render(s,a);assert(writes==before)
          raw='cover2';u.render(s,a)
          assert(objects[u.art].pivot[1]==0 and objects[u.art].pivot[2]==0)
          s.page='songs';u.render(s,a)
          assert(objects[u.art].pos[1]==12 and objects[u.art].pos[2]==40)
          dimensions={width=136,height=100};raw='wide';u.render(s,a)
          assert(objects[u.art].pos[1]==12 and objects[u.art].pos[2]>40)
          before=writes;u.render(s,a);assert(writes==before)
          local wrapped=0;local handle={}
          a.audio={png_image=function(data)assert(data=='png');wrapped=wrapped+1;return handle end}
          dimensions={width=136,height=136,format='png'};raw='png';u.render(s,a)
          assert(objects[u.art].src==handle and u.artsource==handle and u.cover_error=='')
          before=writes;u.render(s,a);assert(writes==before and wrapped==1)
          dimensions={width=136,height=136,format='jpeg'};raw='jpeg';u.render(s,a)
          assert(objects[u.art].src=='jpeg'and u.artsource=='jpeg')
          u.close()
        """)

    def test_player(self):
        self.lua.execute((ROOT/"src/tests/test_player.lua").read_text(encoding="utf-8"))
    def test_playback_pipeline(self):
        self.lua.execute((ROOT/"src/tests/test_playback_pipeline.lua").read_text(encoding="utf-8"))
    def test_boot_icon_and_info(self):
        self.lua.execute((ROOT/"src/tests/test_boot_icon.lua").read_text(encoding="utf-8"))
        png=(ROOT/'package/main.png').read_bytes()
        with Image.open(ROOT/'package/main.png') as icon:
            rgba=icon.convert('RGBA')
            self.assertEqual([rgba.getpixel(p)[3] for p in ((0,0),(95,0),(0,95),(95,95))],[0,0,0,0])
            self.assertGreater(sum(1 for p in rgba.getdata() if p[3]==0),100)
        self.assertEqual(struct.unpack('>II',png[16:24]),(96,96))
        bmp=(ROOT/'package/boot.bmp').read_bytes()
        self.assertEqual(len(bmp),18498)
        self.assertEqual(struct.unpack('<iiHHI',bmp[18:34]),(96,-96,1,16,3))
        html=(ROOT/'package/info.html').read_text(encoding='utf-8')
        self.assertIn('href="/main"',html)
        self.assertIn('v1.0.2',html)
        self.assertIn('version = 1.0.2',(ROOT/'package/app.info').read_text(encoding='utf-8'))
        self.assertIn('"1.0.2"',(ROOT/'src/main/ncm_music.c').read_text(encoding='utf-8'))
        icon=re.search(r'src="data:image/png;base64,([^"]+)"',html)
        self.assertIsNotNone(icon)
        self.assertEqual(base64.b64decode(icon[1]),png)
        self.assertIn('1.211',html)

    def test_input(self):
        self.lua.execute((ROOT/"src/tests/test_input.lua").read_text(encoding="utf-8"))

    def test_effects_settings(self):
        self.lua.execute((ROOT/"src/tests/test_effects.lua").read_text(encoding="utf-8"))

    def test_monotonic_clock(self):
        self.lua.execute((ROOT/'src/tests/test_clock.lua').read_text(encoding='utf-8'))

    def test_transport_backpressure_and_cancel(self):
        self.lua.execute("""
          local stamp=0;local requests={}
          local http={DELAYACK=99}
          function http.createConnection(url,method,opts)
            local c={cb={},acks=0,closed=0,url=url,method=method}
            function c:on(k,f)self.cb[k]=f end
            function c:setbody(b)self.body=b end
            function c:request()requests[#requests+1]=self end
            function c:ack()self.acks=self.acks+1 end
            function c:close()self.closed=self.closed+1 end
            return c
          end
          local net=dofile(ROOT..'/package/transport.lua').new(http,function()return stamp end)
          local a=net.create('one',{method='POST',body='body'})
          a:on('data',function()return http.DELAYACK end);a:request();net.poll()
          assert(#requests==1 and requests[1].method=='POST' and requests[1].body=='body')
          assert(requests[1].cb.data(200,'abc')==http.DELAYACK)
          local b=net.create('two',{});b:request();net.poll()
          assert(#requests==1 and requests[1].closed==1 and requests[1].acks==1)
          requests[1].cb.complete();net.poll();assert(#requests==1)
          stamp=201;net.poll();assert(#requests==2)
        """)

    def test_storage_recovery(self):
        self.lua.execute("""
          local files,encoded,seq={},{},0
          local json={}
          function json.encode(t)seq=seq+1;local k=tostring(seq);encoded[k]=t;return k end
          function json.decode(s)assert(encoded[s]);return encoded[s]end
          local fs={}
          function fs.getcontents(p)return files[p]end
          function fs.exists(p)return files[p]~=nil end
          function fs.mkdir(p)files[p]='DIR';return true end
          function fs.putcontents(p,b)files[p]=b;return true end
          function fs.remove(p)files[p]=nil end
          function fs.rename(a,b)if not files[a]then return nil end;files[b]=files[a];files[a]=nil;return true end
          local store=dofile(ROOT..'/package/storage.lua').new(fs,json)
          assert(store.save('session',{cookie={MUSIC_U='one'}}))
          assert(store.save('session',{cookie={MUSIC_U='two'}}))
          assert(store.save('session',{cookie={MUSIC_U='three'}}))
          assert(store.load('session').cookie.MUSIC_U=='three')
          assert(store.save('session',{cookie={MUSIC_U='two'}}))
          assert(store.load('session').cookie.MUSIC_U=='two')
          files['/sd/data/netease/session.json']='corrupt'
          assert(store.load('session').cookie.MUSIC_U=='three')
        """)

if __name__=="__main__":
    unittest.main(verbosity=2)
