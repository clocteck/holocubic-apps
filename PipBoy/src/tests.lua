local Data = assert(load(read_source("package/data.lua"), "data.lua"))()
local count = 0
local function equal(actual, expected, message)
  assert(actual == expected, (message or "unexpected value") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
  count = count + 1
end
local function fixture(settings)
  local e, requests, docs = {}, {}, {}
  docs.settings = settings or { timezone = "CST-8", weather_location_id = "101020100", temperature_unit = "C" }
  e.file = { getcontents = function() return "settings" end }
  e.json = { decode = function(raw) assert(docs[raw], "bad JSON"); return docs[raw] end }
  e.time = {
    settimezone = function(value) e.zone = value end,
    initntp = function(value) e.ntp = value end,
    getlocal = function() return {year=2026, mon=10, day=12, hour=14, min=30, sec=0, wday=2} end,
  }
  e.sys = { getbrightness = function() return e.level end, setbrightness = function() error("must never write brightness") end }
  e.level = 73
  e.http = { cubicserver = { get = function(url, headers, callback)
    requests[#requests+1] = { url=url, headers=headers, callback=callback }
  end } }
  e.zlib = { isgzip = function(raw) return raw:sub(1,3) == "gz:" end, gunzip = function(raw) return raw:sub(4) end }
  local model = Data.new(e)
  model:init()
  return model, e, requests, docs
end

local m,e,q,d = fixture()
equal(e.zone, "CST-8", "system timezone")
equal(e.ntp, "ntp.aliyun.com", "same NTP as Holo Clock")
equal(m:brightness(), 73)
e.level = 0; equal(m:brightness(), 0, "zero brightness is valid")
e.level = 200; equal(m:brightness(), 100)
e.level = nil; equal(m:brightness(), nil)
e.sys.getbrightness = function() error("unavailable") end; equal(m:brightness(), nil)
equal(m:temperature_text(), "--°C")
equal(Data.weekday(m:local_time()), "MON")
equal(Data.weekday({year=2024,mon=2,day=29}), "THU")
equal(Data.weekday({year=2027,mon=1,day=1}), "FRI")
for code,name in pairs({[100]="sun",[150]="moon",[103]="partly-day",[153]="partly-night",[104]="cloud",[305]="rain",[302]="storm",[400]="snow",[501]="fog",[503]="wind",[404]="sleet",[999]="unknown"}) do
  equal(Data.weather_asset(code),name,"weather PNG mapping")
end
equal(Data.weather_asset("unexpected"),"unknown")
m:tick(2000); equal(#q, 0)
m:tick(3000); equal(#q, 1)
equal(q[1].url, "/v1/weather/now?location=101020100&unit=m&lang=zh")
equal(q[1].headers, "Accept-Encoding: gzip\r\n")
m:tick(4000); equal(#q, 1, "no duplicate inflight request")
d.weather = {code="200", now={temp="24",humidity="48",icon="100",text="晴"}}
q[1].callback(200,"gz:weather")
equal(m.state.valid,true); equal(m.state.icon,"100"); equal(m.state.humidity,48)
equal(m:temperature_text(),"24°C")
d.settings.temperature_unit="F"; m:tick(30000); equal(m:temperature_text(),"75°F")
equal(#q,1,"unit change does not refetch")
m:tick(1804000); equal(#q,2,"30 minute refresh")
q[2].callback(503,"bad"); equal(m.state.valid,false); equal(m.state.temp,nil)
m:tick(1864000); equal(#q,3,"60 second retry")
q[3].callback(200,"bad"); equal(m.state.valid,false,"malformed JSON")

m,e,q,d=fixture({weather_address="上海",language="en-US"})
m:tick(3000)
equal(q[1].url,"/v1/weather/cities?location=%E4%B8%8A%E6%B5%B7&number=1&lang=en")
d.city={code=200,locations={{id="101020100"}}}; q[1].callback(200,"city")
equal(#q,2); equal(q[2].url,"/v1/weather/now?location=101020100&unit=m&lang=en")
d.weather={code=200,now={temp="-1",humidity="101",icon="302",text="Thunderstorms"}}
q[2].callback(200,"weather"); equal(m.state.humidity,100); equal(m:temperature_text(),"-1°C")
d.settings={weather_location_id="101010100",timezone="UTC0"}
m:tick(30000); equal(#q,3); equal(e.zone,"UTC0"); equal(m.state.valid,false,"city change clears previous city")
q[2].callback(200,"weather"); equal(m.state.valid,false,"old city callback ignored")
q[3].callback(200,"weather"); equal(m.state.valid,true)
m:stop(); q[3].callback(500,"bad"); equal(m.state.valid,true,"stopped callbacks ignored")
m:tick(9999999); equal(#q,3,"stopped model never fetches")

m,e,q,d=fixture({weatherAddress="101020100"})
m:tick(3000); equal(q[1].url,"/v1/weather/now?location=101020100&unit=m&lang=zh")
m:tick(23000); equal(m.state.weather_status,"timeout"); equal(m.inflight,nil)
d.weather={code=200,now={temp="30"}}; q[1].callback(200,"weather")
equal(m.state.valid,false,"late timeout callback ignored")
m:tick(83000); equal(#q,2)
q[2].callback(200,"weather"); equal(m.state.icon,"999")

m,e,q,d=fixture({})
m:tick(3000); equal(#q,0); equal(m.state.weather_status,"no-location")
e.time.getlocal=function() return {year=1970} end
equal(m:local_time(),nil,"no fake date before sync")
e.os={date=function() return {year=2026,mon=10,day=12,hour=1,min=2,sec=3} end}
equal(m:local_time().hour,1,"valid OS time fallback")

m,e,q,d=fixture()
e.http.cubicserver.get=function() error("network down") end
m:tick(3000); equal(m.inflight,nil); equal(m.state.weather_status,"error")
e.http=nil; m:tick(63000); equal(m.state.weather_status,"unavailable")

-- Main entry point integration: create widgets, update real values, clean up on exit.
m,e,q,d=fixture()
setmetatable(e,{__index=_G}); e._G=e
local objects, sequence, serial, timer, writes = {}, {}, 100, nil, 0
local function create(parent)
  serial=serial+1; objects[serial]={parent=parent}; return serial
end
e.lv_scr_act=function() return 1 end
e.lv_obj_create=create; e.lv_img_create=create; e.lv_label_create=create
e.lv_obj_set_pos=function(id,x,y) objects[id].x=x;objects[id].y=y end
e.lv_obj_set_size=function(id,w,h) objects[id].w=w;objects[id].h=h end
e.lv_label_set_text=function(id,value) objects[id].text=value;writes=writes+1 end
e.lv_img_set_src=function(id,path) objects[id].src=path end
e.lv_font_load=function() serial=serial+1;return serial end
e.lv_font_free=function(id) sequence[#sequence+1]="free" end
e.lv_obj_del=function(id) sequence[#sequence+1]="delete";objects[id].deleted=true end
for _,name in ipairs({"pad_all","border_width","radius","shadow_width","bg_color","bg_opa","text_font","text_color","text_align"}) do
  e["lv_obj_set_style_"..name]=function() end
end
e.lv_obj_set_style_text_align=function(id,value) objects[id].align=value end
e.lv_obj_add_flag=function() end; e.lv_obj_clear_flag=function() end
e.file.exists=function() return true end
e.tmr={ALARM_AUTO=1,create=function()
  timer={alarm=function(self,ms,mode,fn) self.fn=fn end,stop=function(self) self.stopped=true end,
    unregister=function(self) self.unregistered=true end}
  return timer
end}
e.app={exiting=function() return e.exit_requested end}
e.dofile=function(path)
  equal(path,"/sd/apps/PipBoy/data.lua","self-contained data module")
  return assert(load(read_source("package/data.lua"),"data.lua","t",e))()
end
assert(load(read_source("package/main.lua"),"main.lua","t",e))()
local app=e.PIP_BOY_APP
equal(app.running,true)
equal(objects[app.labels.brand].text,"PIP BOY")
equal(objects[app.labels.brightness].text,"BRI 73%")
equal(objects[app.labels.temperature].text,"--°C")
equal(objects[app.root].w,320);equal(objects[app.root].h,240)
equal(objects[app.labels.weekday].align,2,"LVGL CENTER enum, not LEFT")
equal(objects[app.labels.weekday].x,16,"weekday has left inset")
equal(objects[app.labels.brightness].align,3,"LVGL RIGHT enum")
local initial_writes=writes
timer.fn(); equal(writes,initial_writes,"unchanged values do not redraw")
timer.fn();timer.fn();equal(#q,1)
d.weather={code=200,now={temp="24",humidity="48",icon="100",text="晴"}}
q[1].callback(200,"weather");timer.fn()
equal(objects[app.labels.temperature].text,"24°C")
equal(objects[app.labels.humidity].text,"RH 48%")
equal(objects[app.weather_icon].src,"S:/apps/PipBoy/assets/weather-line/sun.png")
e.level=21;timer.fn();equal(objects[app.labels.brightness].text,"BRI 21%")
local root=app.root
e.exit_requested=true;timer.fn()
equal(app.running,false);equal(timer.stopped,true);equal(timer.unregistered,true)
equal(objects[root].deleted,true);equal(sequence[1],"delete","delete labels before freeing fonts")
equal(#sequence,6);equal(e.PIP_BOY_APP,nil)
local saved_writes=writes
q[1].callback(200,"weather");timer.fn();equal(writes,saved_writes)
print(string.format("PASS: %d assertions (clock, weather, units, brightness, retries, stale callbacks, LVGL lifecycle)",count))
