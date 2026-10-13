"""Three on-device launches with temporary Lua timing instrumentation."""
import argparse,json,time,urllib.request,urllib.parse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--folder',required=True);p.add_argument('--runs',type=int,default=3);a=p.parse_args()
folder=Path(a.folder);http=urllib.request.build_opener(urllib.request.ProxyHandler({}));base=a.device.rstrip('/')
def api(path,body=None,method=None):
    with http.open(urllib.request.Request(base+path,data=body,method=method),timeout=45) as r: result=json.load(r)
    if not result.get('ok',True):raise RuntimeError(result)
    return result
def current():
    c=api('/api/system/state').get('current_app');return c.get('id') if isinstance(c,dict) else c
def close():
    c=current()
    if c not in (None,'radio'):raise RuntimeError('Another foreground App; refusing to close it')
    if c=='radio':api('/api/system/exit',b'')
    deadline=time.monotonic()+20
    while current()=='radio':
        if time.monotonic()>deadline:raise RuntimeError('Radio exit timed out')
        time.sleep(.25)
def upload(directory,names):
    for name in names:
        raw=(directory/name).read_bytes()
        result=api('/api/system/fs/upload?'+urllib.parse.urlencode({'path':'/sd/apps/radio/'+name}),raw,'PUT')
        assert result['entry']['size']==len(raw),name
before=api('/radio/api/state') if current()=='radio' else None
reports=[]
try:
    close();upload(folder/'instrumented',['startup_profile.lua','storage.lua','ui.lua','radio.lua','main.lua'])
    for run in range(1,a.runs+1):
        if run>1:close()
        print('PROFILE_RUN_START',run,flush=True)
        started=time.monotonic();api('/api/system/launch?id=radio',b'');launch_return=time.monotonic()-started
        deadline=started+25;state={}
        while time.monotonic()<deadline:
            try:state=api('/radio/api/state')
            except Exception:state={}
            if state.get('stats',{}).get('written_bytes',0)>0:break
            time.sleep(.5)
        reports.append({'run':run,'launch_api_return_seconds':round(launch_return,3),'observed_seconds':round(time.monotonic()-started,3),'status':state.get('status'),'error':state.get('error'),'written_bytes':state.get('stats',{}).get('written_bytes'),'station_count_source':state.get('storage',{}).get('stations_source')})
        (folder/'runs.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
        print('PROFILE_RUN_END',json.dumps(reports[-1]),flush=True)
        time.sleep(.5)
finally:
    close();upload(folder/'originals',['storage.lua','ui.lua','radio.lua','main.lua'])
    print('ORIGINAL_APP_FILES_RESTORED',flush=True)
    api('/api/system/launch?id=radio',b'')
    if before:
        deadline=time.monotonic()+30
        while True:
            try:
                if api('/radio/api/state').get('storage'):break
            except Exception:pass
            if time.monotonic()>deadline:raise RuntimeError('Restored App not ready')
            time.sleep(.5)
        api('/radio/api/control',json.dumps({'action':'volume','value':before['volume']}).encode(),'POST')
        if before['status']=='idle':api('/radio/api/control',b'{"action":"stop"}','POST')
(folder/'runs.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('PROFILE_COMPLETE',flush=True)
