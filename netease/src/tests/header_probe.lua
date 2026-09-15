local url='http://192.168.0.80:18765/'
local result={version=sys.version(),get=false,stream=false,complete=false}
local json=sjson or json
local function save()
  file.putcontents('/sd/apps/netease/header-test-result.json',json.encode(result))
end
local function check(code,h)
  local value=h and h['set-cookie']
  return code==200 and type(value)=='string'
    and value:find('MUSIC_U=synthetic%-test')~=nil
    and value:find('__csrf=synthetic%-csrf')~=nil
    and value:find('NMTID=synthetic%-device')~=nil
    and value:find('Wed, 09 Jun 2030',1,true)~=nil
end
local connection
http.get(url,{timeout=8000},function(code,body,headers)
  result.get=check(code,headers);result.get_code=code;save()
  connection=http.createConnection(url,'GET',{async=true,timeout=8000})
  connection:on('headers',function(status,h)result.stream=check(status,h);result.stream_code=status end)
  connection:on('data',function()end)
  connection:on('complete',function()result.complete=true;save()end)
  connection:request()
end)
local screen=lv_scr_act();lv_obj_clean(screen)
local label=lv_label_create(screen);lv_label_set_text(label,'HTTP header regression test')
save()
