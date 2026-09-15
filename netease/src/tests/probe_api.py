"""Read-only compatibility probe. Never prints QR keys, cookies or audio URLs."""
import ctypes as C
import json
import urllib.request
from pathlib import Path

dll=C.CDLL(str(Path(__file__).parent/"build/ncm_test.dll"))
dll.ncm_eapi.argtypes=[C.c_char_p,C.c_char_p,C.c_size_t]
dll.ncm_eapi.restype=C.c_void_p
crt=C.CDLL("ucrtbase");crt.free.argtypes=[C.c_void_p]
for path,fields in [
    ("/api/login/qrcode/unikey",{"type":3}),
    ("/api/song/enhance/player/url/v1",{"ids":"[347230]","level":"standard","encodeType":"mp3"}),
]:
    fields.update(e_r=False,header={"os":"pc","appver":"3.1.17.204416","deviceId":"CubicESP32S3","channel":"netease"})
    raw=json.dumps(fields,separators=(",",":")).encode()
    ptr=dll.ncm_eapi(path.encode(),raw,len(raw));body=C.string_at(ptr);crt.free(ptr)
    req=urllib.request.Request("https://interface.music.163.com/eapi/"+path[5:],data=body,
      headers={"Content-Type":"application/x-www-form-urlencoded","User-Agent":"NeteaseMusicDesktop/3.1.17.204416",
               "Cookie":"os=pc; appver=3.1.17.204416","Referer":"https://music.163.com/","Accept-Encoding":"identity"})
    try:
        with urllib.request.urlopen(req,timeout=15) as response:
            doc=json.load(response)
        item=(doc.get("data")or [{}])[0] if isinstance(doc.get("data"),list) else {}
        print(json.dumps({"path":path,"code":doc.get("code"),"qr_key_present":bool(doc.get("unikey")),
          "audio_type":item.get("type"),"url_available":bool(item.get("url"))}))
    except Exception as exc:
        print(json.dumps({"path":path,"error":type(exc).__name__}))
