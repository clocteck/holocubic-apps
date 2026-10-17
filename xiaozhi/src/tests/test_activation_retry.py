"""Deterministic wall-clock pairing tests; no real requests or waiting."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[3]


def make_vm(app, clock_base=0):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().clock_base = clock_base
    vm.execute("""
      now=0;timers={};requests={};events={};saved=0;bound=false
      code='057855';latency=0;failure=nil;save_error=nil;with_pending_ws=false
      print=function()end
      function millis()return (clock_base+now)%4294967296 end
      tmr={ALARM_SINGLE=0,create=function()
        local t={};timers[#timers+1]=t
        function t:stop()self.active=false end
        t.unregister=t.stop
        function t:alarm(ms,kind,fn)self.at=now+ms;self.fn=fn;self.active=true end
        return t
      end}
      function run_to(target)
        local limit=1000
        while true do
          local next_timer=nil
          for _,t in ipairs(timers)do
            if t.active and t.at<=target and (not next_timer or t.at<next_timer.at)then next_timer=t end
          end
          if not next_timer then break end
          limit=limit-1;assert(limit>0,'timer spin')
          now=math.max(now,next_timer.at);next_timer.active=false;next_timer.fn(next_timer)
        end
        now=math.max(now,target)
      end
      function active_timers()
        local count=0;for _,t in ipairs(timers)do if t.active then count=count+1 end end
        return count
      end
      function dofile(path)
        if path:match('/i18n.lua$') then return {translator=function()return function(s)return s end end}end
        if path:match('/identity.lua$') then return {
          device_id=function()return '02:01:02:03:04:05'end,
          client_id=function()return 'test-client'end,
          http_headers=function()return {}end,system_info_json=function()return '{}'end}end
        if path:match('/store.lua$') then return {
          device_id=function()return '02:01:02:03:04:05'end,
          update=function(fn)
            if save_error then return false,save_error end
            local doc={};assert(fn(doc)~=false);assert(doc.websocket.url=='wss://bound.test')
            saved=saved+1;return true
          end}end
        error(path)
      end
      sjson={decode=function(raw)
        if raw=='bad' then error('bad json') end
        local ws={url='wss://bound.test',token='test-token',version=1}
        if raw=='bound' then return {websocket=ws} end
        return {activation={code=code},websocket=with_pending_ws and ws or nil}
      end}
      http={post=function(url)
        local activate=url:match('/activate$')~=nil
        requests[#requests+1]={at=now,kind=activate and 'activate' or 'ota'}
        now=now+latency
        if stop_on_request then a:stop() end
        if failure=='exception' then error('HTTP connection lost') end
        if failure=='500' then return 500,'upstream unavailable' end
        if failure=='expired' and activate then return 401,'pairing code expired' end
        if activate then return bound and 200 or 202,'' end
        return 200,failure=='malformed' and 'bad' or (bound and 'bound' or 'unbound')
      end}
      cfg={APP_DIR='/app',ota={url='https://ota.test/',enabled=true,
        interval_ms=3000,max_polls=80},websocket={url=''}}
      function event(name,data)events[#events+1]={name=name,data=data}end
      function assert_no_failure()
        for _,e in ipairs(events)do assert(e.name~='failed',tostring(e.data))end
      end
    """)
    vm.globals().Activation = vm.execute(
        (ROOT / app / "package/activation.lua").read_text(encoding="utf-8")
    )
    vm.execute("a=Activation.new(cfg);assert(a:start(event))")
    return vm


for app in ("xiaozhi", "xiaozhi-service"):
    for base in (0, 4294967000):
        vm = make_vm(app, base)
        vm.execute("""
          run_to(20);assert(a.code=='057855' and #requests==1)
          run_to(6019);assert(#requests==1)
          run_to(6020);assert(#requests==2)
          run_to(299999);assert(not a.slow_retry and a.active and #requests==50)
          for i=2,#requests do assert(requests[i].at-requests[i-1].at==6000)end
          local n=#requests
          run_to(300000);assert(a.slow_retry and a.active and #requests==n)
          assert(a.next_retry_ms==20000 and active_timers()==1)
          bound=true
          run_to(319999);assert(saved==0 and #requests==n)
          run_to(320000);assert(saved==1 and requests[#requests].kind=='ota')
          assert(events[#events].name=='done' and not a.active and a.code=='')
          assert(a.next_retry_ms==0 and active_timers()==0)
          run_to(600000);assert(#requests==n+1);assert_no_failure()
        """)
    print(app + ": 6s fast / real 5min deadline / 20s slow / late binding / clock wrap: PASS")

    vm = make_vm(app)
    vm.execute("""
      run_to(300000);code='000007';run_to(320000)
      assert(a.code=='000007' and a.slow_retry)
      run_to(500000)
      local previous=nil
      for _,r in ipairs(requests)do
        if r.at>=320000 then
          if previous then assert(r.at-previous==20000)end
          previous=r.at
        end
      end
      assert(a.active and active_timers()==1);assert_no_failure()
      local stale=a.timer.fn;a:stop();local n=#requests
      run_to(1000000);stale();assert(#requests==n and active_timers()==0)
      a:start(event);stale();assert(#requests==n)
      run_to(now+20);assert(not a.slow_retry and a.active and active_timers()==1)
    """)
    print(app + ": slow retries persist / refreshed code / stop / stale timer / restart: PASS")

    for failure in ("500", "exception", "malformed"):
        vm = make_vm(app)
        vm.globals().failure = failure
        vm.execute("""
          run_to(60020);assert(a.network_retries>5 and a.active and a.last_error~='')
          run_to(300000);assert(a.slow_retry and a.active and active_timers()==1)
          failure=nil;bound=true;run_to(320000)
          assert(saved==1 and not a.active and a.last_error=='' and active_timers()==0)
          assert_no_failure()
        """)
    vm = make_vm(app)
    vm.execute("""
      failure='expired';run_to(6020)
      assert(a.last_error:find('401',1,true) and a.next_retry_ms==6000)
      bound=true;run_to(12020);assert(saved==1 and not a.active);assert_no_failure()
    """)
    print(app + ": network failures / HTTP exceptions / malformed replies / expired code: PASS")

    vm = make_vm(app)
    vm.execute("""
      latency=7000;run_to(300000)
      assert(now>=300000 and a.slow_retry and a.active and #requests<50)
      assert(a.next_retry_ms==20000 and active_timers()==1);assert_no_failure()
    """)
    vm = make_vm(app)
    vm.execute("""
      with_pending_ws=true;run_to(20);bound=true;run_to(6020)
      assert(saved==1 and a.code=='' and not a.active and active_timers()==0)
      assert(events[#events].name=='done');assert_no_failure()
    """)
    vm = make_vm(app)
    vm.execute("""
      bound=true;save_error='config_commit_failed';run_to(20)
      assert(saved==0 and not a.active and active_timers()==0)
      assert(events[#events].name=='failed' and a.last_error=='config_commit_failed')
    """)
    vm = make_vm(app)
    vm.execute("""
      stop_on_request=true;run_to(600000)
      assert(#requests==1 and not a.active and active_timers()==0)
    """)
    print(app + ": request time counted / pending credentials / storage error / in-flight stop: PASS")
