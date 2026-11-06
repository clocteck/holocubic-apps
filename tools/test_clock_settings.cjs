// Exercise the actual launcher functions without touching a device.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),cp=require('node:child_process'),path=require('node:path');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'launcher/package/main.html'),'utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(script);
const line=name=>html.split('\n').find(l=>l.includes('function '+name+'('));
const persist=html.slice(html.indexOf('  var settingsWriteQueue='),html.indexOf('  var volumeTimer='));
const elements=new Map();
const q=id=>{if(!elements.has(id))elements.set(id,{value:'',textContent:'保存',disabled:false});return elements.get(id)};
let disk={time_format:'24',timezone:'CST-8',temperature_unit:'F',weather_address:'Tokyo',language:'ja',brightness:70,
  volume:37,alarms:[{hour:13,minute:5}],weather_location_id:'123',unknown_future_field:{keep:true}};
let uploads=0;
const c=vm.createContext({console,Promise,Number,String,Object,Array,JSON,SETTINGS_PATH:'/sd/apps/settings.json',state:{language:'ja'},
  q,window:{clearTimeout(){}},localStorage:{getItem:()=>'',setItem:()=>{}},LANGUAGE_KEY:'lang',navigator:{language:'en'},
  applyLanguage:l=>c.state.language=l,loadVolume:async()=>{},renderAppsAndServices:()=>{},syncWeatherLocation:()=>{},
  showToast:(m,e)=>{if(e)throw Error(m)},renderVolume:()=>{},saveVolume:()=>{},
  fetch:async(url)=>({ok:true,status:200,json:async()=>structuredClone(disk)}),
  api:async(url,init)=>{assert(url.startsWith('/api/system/fs/upload?'));disk=JSON.parse(init.body);uploads++;return {ok:true}}
});
vm.runInContext(persist+'\n'+['normalizeTimeFormat','readSettings','loadSettings','saveSettings','restoreSettings'].map(line).join('\n'),c);
(async()=>{
  await c.loadSettings();assert.equal(q('#timeFormatPreview').value,'24');assert.equal(q('#temperatureUnitPreview').value,'F');
  q('#autostartPreview').value='weather';q('#timeFormatPreview').value='12';
  await c.saveSettings({preventDefault(){}});
  assert.equal(disk.time_format,'12');assert.equal(disk.volume,37);assert.equal(disk.weather_location_id,'123');
  assert.deepEqual(disk.alarms,[{hour:13,minute:5}]);assert.deepEqual(disk.unknown_future_field,{keep:true});
  await c.loadSettings();assert.equal(q('#timeFormatPreview').value,'12');
  disk.time_format=12;await c.loadSettings();assert.equal(q('#timeFormatPreview').value,'12');
  delete disk.time_format;await c.loadSettings();assert.equal(q('#timeFormatPreview').value,'24');
  disk.time_format='garbage';await c.loadSettings();assert.equal(q('#timeFormatPreview').value,'24');
  c.restoreSettings();await vm.runInContext('settingsWriteQueue',c);
  assert.equal(disk.time_format,'24');assert.equal(disk.temperature_unit,'C');assert.equal(disk.volume,37);
  assert.deepEqual(disk.alarms,[{hour:13,minute:5}]);
  await Promise.all([c.persistSettings({time_format:'12'}),c.persistSettings({volume:46})]);
  assert.equal(disk.time_format,'12');assert.equal(disk.volume,46);
  const before=uploads;c.fetch=async()=>({ok:true,json:async()=>{throw Error('bad JSON')}});
  await assert.rejects(c.persistSettings({time_format:'24'}));assert.equal(uploads,before);
  // Every unrelated source line must stay byte-for-byte unchanged (ignoring CRLF).
  const old=cp.execFileSync('git',['show','bb89ab2:launcher/package/main.html'],{cwd:root,encoding:'utf8'}).replace(/\r/g,'');
  const strip=s=>s.replace(/\r/g,'').split('\n').filter(l=>!['function loadSettings(','function saveSettings(','function restoreSettings(','id="timeFormatPreview"'].some(k=>l.includes(k))).join('\n');
  const withoutNew=html.replace(/  function normalizeTimeFormat\(value\)[\s\S]*?(?=  var WEATHER_EDITOR_COPY=)/,'')
    .replace(/  var brightnessSaveTimer=0;[\s\S]*?(?=  var volumeTimer=)/,'')
    .replace('bindVolumeSettings();bindBrightnessSettings();','bindVolumeSettings();');
  assert.equal(strip(withoutNew),strip(old));
  console.log('PASS: JS syntax, load/save/reset, numeric/default/invalid values, preservation, queued writes, failed JSON; unrelated HTML/JS unchanged');
})().catch(e=>{console.error(e);process.exitCode=1});
