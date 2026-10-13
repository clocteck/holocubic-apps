const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const dir=path.join(__dirname,"../package");
const html=fs.readFileSync(path.join(dir,"main.html"),"utf8");
const sources=[["inline",html.match(/<script data-inline="launcher-control">([\s\S]*?)<\/script>/)[1]],
  ["external",fs.readFileSync(path.join(dir,"control.js"),"utf8")]];
function setup(script,mode="new"){
  new vm.Script(script);
  const nodes=new Map(),timers=new Map(),toasts=[],posts=[],writes=[];
  let nextTimer=0,volume=0,pending=false,fail=0;
  let file={volume:17,language:"en",brightness:70,temperature_unit:"F",custom:{keep:true}};
  const q=id=>{if(!nodes.has(id))nodes.set(id,{value:"",disabled:false,title:"",listeners:{},
    addEventListener(k,f){this.listeners[k]=f}});return nodes.get(id)};
  const c=vm.createContext({Promise,COPY:{"zh-CN":{},en:{},de:{},ja:{},"zh-TW":{}},
    SETTINGS_PATH:"/sd/apps/settings.json",LANGUAGE_KEY:"test",state:{settings:{},language:"en"},q,
    navigator:{language:"en"},document:{hidden:false},
    window:{setTimeout:f=>{timers.set(++nextTimer,f);return nextTimer},clearTimeout:id=>timers.delete(id),
      setInterval:()=>999,clearInterval(){},addEventListener(){}},
    localStorage:{getItem:()=>null},applyLanguage(){},renderAppsAndServices(){},
    showToast:(text,error)=>toasts.push({text,error}),t:k=>k,
    fetch:async(url,opt={})=>{
      if(url.startsWith("/audio/api/settings")){
        if(mode==="old")return {ok:false,status:404};
        if(fail)return {ok:false,status:fail};
        if(opt.method==="POST"){volume=Number(new URL(url,"http://device").searchParams.get("volume"));posts.push(volume);pending=true;}
        return {ok:true,json:async()=>({ok:true,api_version:1,volume,pending,saved:!pending,error:""})};
      }
      if(url.startsWith("/display/api/settings"))return {ok:true};
      assert.equal(new URL(url,"http://device").searchParams.get("path"),"/sd/apps/settings.json");
      return {ok:true,json:async()=>structuredClone(file)};
    },
    api:async(url,opt)=>{file=JSON.parse(opt.body);writes.push(file);return {ok:true}}
  });
  const start=script.indexOf("  var settingsWriteQueue="),end=script.indexOf("  function normalizeLedColor",start);
  assert.ok(start>=0&&end>start);vm.runInContext(script.slice(start,end),c);
  return {c,q,posts,writes,toasts,timers,get volume(){return volume},file:()=>file,
    settle(){pending=false;file.volume=volume},fail(n){fail=n},remote(n){volume=n;pending=false}};
}
async function test(label,source){
  const h=setup(source),{c,q}=h;
  c.bindVolumeSettings();await c.loadSettings();
  assert.equal(q("#volumePreview").value,"0");assert.equal(q("#volumePreview").disabled,false);
  q("#volumePreview").value="38";q("#volumePreview").listeners.input.call(q("#volumePreview"));
  assert.equal(h.posts.length,0);
  await q("#volumePreview").listeners.change();
  assert.equal(h.volume,38);assert.equal(h.writes.length,0,"volume never uploads a JSON file");
  assert.ok(!h.toasts.some(x=>x.text==="savedOnDevice"),"accepted is not durable saved");
  h.settle();await c.loadVolume();assert.equal(h.toasts.at(-1).text,"savedOnDevice");
  q("#volumePreview").value="12";const first=c.saveVolume();
  q("#volumePreview").value="83";await c.saveVolume();await first;
  assert.deepEqual(h.posts.slice(-2),[12,83],"serialized and last value wins");
  h.settle();
  q("#timezonePreview").value="CST-8";q("#weatherLocationPreview").value="Ningbo";
  q("#apModePreview").value="true";q("#brightnessPreview").value="60";q("#autostartPreview").value="";
  await c.saveSettings();assert.equal(h.file().volume,83);assert.equal(h.file().custom.keep,true);
  h.fail(503);q("#volumePreview").value="99";await c.saveVolume();
  assert.equal(h.volume,83);assert.equal(h.toasts.at(-1).error,true);
  await c.loadVolume();assert.equal(c.state.volumeSupported,null,"temporary error is not legacy firmware");
  h.fail(0);await c.loadVolume();q("#volumePreview").value="0";await c.saveVolume();
  assert.equal(h.volume,0,"mute survives normalization");
  h.settle();h.remote(46);await c.loadVolume();assert.equal(q("#volumePreview").value,"46","app edits reach dashboard");
  // A slow GET started before an edit must not revert the slider afterwards.
  const fetch=c.fetch;let release;
  c.fetch=(url,opt)=>opt.method==="GET"&&url.startsWith("/audio/")?new Promise(resolve=>{release=resolve}):fetch(url,opt);
  const stale=c.loadVolume();q("#volumePreview").value="71";await c.saveVolume();
  release({ok:true,json:async()=>({ok:true,api_version:1,volume:46,pending:false,saved:true})});
  await stale;assert.equal(q("#volumePreview").value,"71");c.fetch=fetch;
  const old=setup(source,"old");old.c.bindVolumeSettings();await old.c.loadSettings();
  assert.equal(old.c.state.volumeSupported,false);assert.equal(old.q("#volumePreview").disabled,true);
  old.q("#volumePreview").value="99";await old.c.saveVolume();
  assert.equal(old.posts.length,0);assert.equal(old.writes.length,0);
  assert.equal(old.file().volume,17,"old firmware volume is read-only on dashboard");
  console.log("PASS "+label+": memory API, pending/save status, mute, queue, shared fields, failure recovery, legacy and stale response");
}
(async()=>{for(const [name,source] of sources)await test(name,source)})().catch(e=>{console.error(e);process.exitCode=1});
