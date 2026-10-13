-- PROBE_APP/PROBE_FACE are supplied by test_weather_device.cjs.
local codec=json or sjson
local output='/sd/apps/devrun/weather-regression.json'
local shot='/sd/apps/devrun/weather-regression.png'
local requests, labels, texts, fonts, errors = {}, {}, {}, {}, {}
local original_get=http.cubicserver.get
http.cubicserver.get=function(path,headers,callback)
  local row={path=path};requests[#requests+1]=row
  return original_get(path,headers,function(status,body,h)
    row.status=status
    local plain=body
    if plain and zlib and zlib.isgzip(plain) then plain=zlib.gunzip(plain) end
    local ok,doc=pcall(codec.decode,plain or '')
    if ok then row.code=doc.code; row.now=doc.now; row.location=doc.location or doc.locations end
    return callback(status,body,h)
  end)
end
local original_label=lv_label_set_text
lv_label_set_text=function(id,v) labels[tostring(id)]=tostring(v);return original_label(id,v) end
local original_draw=lv_canvas_draw_text
lv_canvas_draw_text=function(canvas,x,y,w,v,dsc)
  texts[tostring(x)..','..tostring(y)]={x=x,y=y,text=tostring(v),font=type(dsc)=='table' and tostring(dsc.font_handle) or ''}
  return original_draw(canvas,x,y,w,v,dsc)
end
local original_font=lv_font_load
lv_font_load=function(path)
  local handle,err=original_font(path)
  if handle then fonts[tostring(handle)]=path else errors[#errors+1]='font: '..path..' '..tostring(err) end
  return handle,err
end
file.putcontents(output,codec.encode({done=false,stage='loading',app=PROBE_APP,face=PROBE_FACE}))
local ok,err=pcall(dofile,'/sd/apps/'..PROBE_APP..'/main.lua')
if not ok then file.putcontents(output,codec.encode({done=true,error=tostring(err)}));return end
if HOLO_TIME_APP and PROBE_APP=='NixieClock' then
  HOLO_TIME_APP.state.face=PROBE_FACE or 4;HOLO_TIME_APP.state.last_render_face=0
end
file.putcontents(output,codec.encode({done=false,stage='started',app=PROBE_APP,face=PROBE_FACE}))
local ticks=0
local timer=tmr.create()
timer:alarm(1000,tmr.ALARM_AUTO,function()
  ticks=ticks+1
  if ticks%5==0 then file.putcontents(output,codec.encode({done=false,stage='waiting',ticks=ticks,requests=requests})) end
  local pending=false
  for _,r in ipairs(requests) do if not r.status then pending=true end end
  if ticks<10 or (pending and ticks<40) then return end
  timer:stop()
  local result={done=true,requests=requests,font_errors=errors,labels=labels,texts=texts}
  for _,row in pairs(texts) do row.font_path=fonts[row.font] end
  if PROBE_APP=='weather' then
    local a=WEATHER_APP
    result.city=a.CITY_NAME;result.displayed_city=labels[tostring(a.ui.city_label)]
    result.city_lang=a.CITY_NAME_LANGUAGE;result.id=a.state.resolved_location_id
    result.valid=a.state.valid;result.forecast_valid=a.state.forecast.valid
    result.temperature=labels[tostring(a.ui.temp_label)]
  elseif PROBE_APP=='NixieClock' then
    local a=HOLO_TIME_APP
    result.city=a.state.city;result.id=a.state.weather_location_id
    result.valid=a.state.weather_valid;result.forecast_valid=a.state.forecast_valid
    result.running=a.running;result.face=a.state.face
    result.fireworks=FIREWORKS_CLOCK_APP and FIREWORKS_CLOCK_APP.running or false
  end
  local saved,save_err=pcall(function()
    local snap,e=lv_snapshot_take(lv_scr_act(),LV_IMG_CF_TRUE_COLOR)
    if not snap then error(tostring(e)) end
    local done,se=lv_snapshot_save_to_png(snap,shot);lv_snapshot_free(snap)
    if not done then error(tostring(se)) end
  end)
  result.screenshot=saved;result.screenshot_error=not saved and tostring(save_err) or nil
  file.putcontents(output,codec.encode(result))
end)
