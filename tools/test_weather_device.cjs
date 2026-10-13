// API-only deployment/regression test. Backups live outside the repository.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),base=process.env.DEVICE_URL||'http://192.168.1.30';
const out=process.env.WEATHER_RESUME||fs.mkdtempSync(path.join(os.tmpdir(),'cubic-weather-fix-'));
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function api(p,init){const r=await fetch(new URL(p,base),{...init,signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error(`${r.status} ${p}`);return r;}
async function read(p){return Buffer.from(await(await api('/api/system/fs/file?path='+encodeURIComponent(p))).arrayBuffer());}
async function write(p,b){await api('/api/system/fs/upload?path='+encodeURIComponent(p),{method:'PUT',body:b});}
async function remove(p){await api('/devtools/api/remove?path='+encodeURIComponent(p),{method:'DELETE'});}
async function exitApp(){if((await(await api('/api/system/state')).json()).current_app)await api('/api/system/exit',{method:'POST'});}
async function maybeRead(p){try{return await read(p)}catch(e){if(String(e).includes('404'))return null;throw e}}
const settingsPath='/sd/apps/settings.json',configPath='/sd/apps/NixieClock/config.json';
(async()=>{
 console.log('EVIDENCE '+out);
 const resumed=process.env.WEATHER_RESUME?JSON.parse(fs.readFileSync(path.join(out,'state-backup.json'))):null;
 const original=resumed?resumed.original:(await(await api('/api/system/state')).json()).current_app?.id;
 const backup={};
 for(const p of [settingsPath,configPath,'/sd/apps/devrun/main.lua','/sd/apps/devrun/main.bak'])backup[p]=resumed?(resumed.files[p]===null?null:Buffer.from(resumed.files[p],'base64')):await maybeRead(p);
 fs.writeFileSync(path.join(out,'state-backup.json'),JSON.stringify({original,files:Object.fromEntries(Object.entries(backup).map(([p,b])=>[p,b?.toString('base64')??null]))}));
 const deployed={};let passed=false;const results=[];
 if(resumed)for(const [p,b]of Object.entries(JSON.parse(fs.readFileSync(path.join(out,'deployment-backup.json')))))deployed[p]=b===null?null:Buffer.from(b,'base64');
 try{
  if(process.argv.includes('--deploy')){
   let files=['weather/package/main.lua','weather/package/font/weather_num_28.bin','NixieClock/package/main.lua','NixieClock/package/fireworks.lua','holo_pc_monitor/package/main.lua','holo_pc_monitor/package/temperature.lua'];
   for(const n of fs.readdirSync(path.join(root,'NixieClock/package/font')))if(/^time_i18n_.*\.bin$/.test(n))files.push('NixieClock/package/font/'+n);
   if(process.env.WEATHER_DEPLOY_ONLY)files=files.filter(p=>process.env.WEATHER_DEPLOY_ONLY.split(',').includes(p));
   for(const p of files){const device='/sd/apps/'+p.replace('/package/','/');deployed[device]=await maybeRead(device);}
   fs.writeFileSync(path.join(out,'deployment-backup.json'),JSON.stringify(Object.fromEntries(Object.entries(deployed).map(([p,b])=>[p,b?.toString('base64')??null]))));
   await exitApp();
   for(const p of files){const device='/sd/apps/'+p.replace('/package/','/'),bytes=fs.readFileSync(path.join(root,p));await write(device,bytes);assert((await read(device)).equals(bytes),'upload '+device);}
   console.log('DEPLOYED '+files.length+' verified files');
  }
  const cases=[
   ['weather','zh-fresh','zh-CN','宁波市镇海区','clear','镇海'],
   ['weather','en-cached','en','宁波市镇海区','keep','Zhenhai'],
   ['weather','ja-fresh','ja','日本東京都新宿区','clear','新宿'],
   ['weather','ja-restart','ja','日本東京都新宿区','keep','新宿'],
   ['weather','zh-tw','zh-TW','寧波市鎮海區','clear','鎮海'],
   ['weather','de-long','de','Frankfurt am Main Hessen Deutschland','clear','Frankfurt am Main'],
   ['NixieClock','stale','zh-CN','宁波市镇海区','stale','镇海'],
   ['NixieClock','en-cached','en','宁波市镇海区','keep','Zhenhai'],
   ['NixieClock','ja-fresh','ja','日本東京都新宿区','clear','新宿'],
   ['NixieClock','ja-restart','ja','日本東京都新宿区','keep','新宿'],
   ['NixieClock','zh-tw','zh-TW','寧波市鎮海區','clear','鎮海'],
   ['NixieClock','de','de','Bayern München','clear','München'],
   ...['en','ja','zh-TW','de'].map(lang=>['holo_pc_monitor',lang,lang,lang==='ja'?'日本東京都新宿区':lang==='de'?'Bayern München':'宁波市镇海区','clear']),
  ];
  if(process.argv.includes('--faces'))for(const face of [1,2,3,5,6,7,8,9])cases.push(['NixieClock','face-'+face,'ja','日本東京都新宿区','clear','新宿',face]);
  for(const [app,name,language,address,cache,city,face=4] of cases){
   if(process.env.WEATHER_ONLY && !process.env.WEATHER_ONLY.split(',').some(prefix=>(app+'/'+name).startsWith(prefix)))continue;
   await exitApp();
   const settings=JSON.parse(await read(settingsPath));settings.weather_address=address;settings.language=language;
   if(cache!=='keep')for(const k of ['weather_location_address','weather_location_raw','weather_location_id','weather_city','weather_city_lang'])delete settings[k];
   if(cache==='stale')Object.assign(settings,{weather_location_id:'101210401',weather_location_address:'Ningbo',weather_city:'宁波',weather_city_lang:'zh-CN'});
   const initialSettings=Buffer.from(JSON.stringify(settings));await write(settingsPath,initialSettings);
   if(app==='NixieClock')await write(configPath,Buffer.from(JSON.stringify({default_face:face,auto_switch_ms:0})));
   const code=Buffer.from(`PROBE_APP=${JSON.stringify(app)};PROBE_FACE=${face}\n`+fs.readFileSync(path.join(__dirname,'weather_device_probe.lua'),'utf8'));
   await api('/devtools/api/code/run',{method:'POST',headers:{'Content-Type':'text/plain; charset=utf-8'},body:code});
   let result;for(let i=0;i<50;i++){await pause(1000);try{result=JSON.parse(await read('/sd/apps/devrun/weather-regression.json'))}catch{}if(result?.done)break}
   if(!result?.done || result.error)fs.writeFileSync(path.join(out,app+'-'+name+'-failure.json'),JSON.stringify({probe:result,state:await(await api('/api/system/state')).json()},null,2));
   assert(result?.done,'probe timeout');assert(!result.error,result.error);
   result.app=app;result.case=name;result.saved=JSON.parse(await read(settingsPath));results.push(result);
   fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(results,null,2));
   if(result.screenshot)fs.writeFileSync(path.join(out,app+'-'+name+'.png'),await read('/sd/apps/devrun/weather-regression.png'));
   assert.equal(Object.keys(result.font_errors).length,0,'font loading');
   const apiLang=({'zh-CN':'zh','zh-TW':'zh-hant'})[language]||language;
   assert(result.requests.length>0,'weather requests missing');
   for(const req of result.requests){assert(req.path.endsWith('lang='+apiLang),req.path);assert.equal(req.status,200,req.path);assert.equal(String(req.code),'200',req.path);}
   if(city){assert.equal(result.city,city);assert.equal(result.valid,true);assert.equal(result.forecast_valid,true);}
   if(app==='weather')assert.equal(result.displayed_city,city);
   if(app==='NixieClock'){
    assert.equal(result.running,true);
    if(face===4)assert(result.texts['224,67'].font_path.endsWith('/time_num_34.bin'),'large temperature font');
    if(face===9)assert.equal(result.fireworks,true,'fireworks running');
   }
   if(name==='ja-restart')assert(!result.requests.some(r=>r.path.includes('/cities?')),'restart repeated lookup');
   if(name==='en-cached')assert(result.requests.find(r=>r.path.includes('/cities?')).path.includes('location=101210412'),'language change must use ID');
   if(name==='stale')assert(!result.requests.some(r=>r.path.includes('location=101210401')),'old location used');
   if(app==='holo_pc_monitor')assert((await read(settingsPath)).equals(initialSettings),'monitor changed shared settings');
   console.log('PASS '+app+' '+name+' '+(result.city||'read-only')+' '+apiLang);
  }
  passed=true;
 }finally{
  await exitApp();
  if(!passed)for(const [p,b]of Object.entries(deployed)){if(b)await write(p,b);else await remove(p)}
  for(const [p,b]of Object.entries(backup)){if(b)await write(p,b);else if(await maybeRead(p))await remove(p)}
  for(const [p,b]of Object.entries(backup))if(b)assert((await read(p)).equals(b),'restore '+p);
  for(const p of ['/sd/apps/devrun/weather-regression.json','/sd/apps/devrun/weather-regression.png'])if(await maybeRead(p))await remove(p);
  if(original)await api('/api/system/launch?id='+encodeURIComponent(original),{method:'POST'});
  console.log('RESTORED settings/config/DevRun/app; deployment '+(passed?'kept':'rolled back'));
 }
})().catch(e=>{console.error(e.stack);process.exitCode=1});
