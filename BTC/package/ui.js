"use strict";
const $=id=>document.getElementById(id);
// Lua JSON represents an empty table as {}; only arrays may be iterated.
const asArray=value=>Array.isArray(value)?value:[];
const LANG=document.documentElement.lang||"zh-CN", LI={"zh-CN":0,en:1,"zh-TW":2,ja:3}[LANG]??0;
const tr=k=>LABELS[k]?.[LI]||LABELS[k]?.[0]||k;
const API=document.documentElement.dataset.base+"/api";
const groups=["all","ashare","hongkong","nasdaq","taiwan","crypto","metal","fx"];
let state=null,browse="all",onlySaved=false,mutation=false,revision=0,polling=false,searchToken=0,searchTimer=null,toastTimer=null;
let results=[],searchJobs=[],searchWorking=false,currencyGeneration="",listSignature="",directorySignature="",chartHover=null;
const text=(id,value)=>{$(id).textContent=value??"—";};
const name=a=>(ASSET_NAMES[LANG]||{})[a.id]||a.text||a.symbol||"—";
const market=a=>({0:"SZ / BJ",1:"SH",100:"INDEX",101:"COMEX",105:"NASDAQ",106:"NYSE",107:"AMEX",178:"TW",116:"HK"})[a.market??a.secid?.split(".")[0]]||tr(a.group);
const key=a=>a.secid||((a.source||a.group)+":"+a.symbol);
const timeLabel=v=>/^\d{10,13}$/.test(String(v))?new Date(Number(v)*(String(v).length===10?1000:1)).toLocaleString(LANG,{month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",hour12:false}):String(v||"");
const fmtBytes=n=>n>=1048576?(n/1048576).toFixed(2)+" MB":Math.round(n/1024)+" KB";
function toast(message,error=false){clearTimeout(toastTimer);text("toast",message);$("toast").classList.toggle("error",error);$("toast").hidden=false;toastTimer=setTimeout(()=>$("toast").hidden=true,error?6500:3000);}
async function api(route,body){
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),18000);
 try{const r=await fetch(API+route,{cache:"no-store",signal:controller.signal,...(body===undefined?{}:{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)})});const data=await r.json();if(!r.ok||data.ok===false)throw new Error(data.error||data.save_error||("HTTP "+r.status));return data;}finally{clearTimeout(timeout);}
}
async function command(route,body={},message=tr("saved_ok")){
 if(mutation){toast(tr("busy"));return null;}
 mutation=true;revision++;setControlsBusy(true);
 try{const s=await api(route,body);if(s.settings)render(s);if(s.catalog)renderCatalog(s.catalog);if(message)toast(message);return s;}
 catch(e){toast(e.message,true);return null;}
 finally{mutation=false;setControlsBusy(false);setTimeout(poll,300);}
}
function setControlsBusy(b){["refresh","chartMode","ma","displayCurrency","tilt"].forEach(id=>$(id).disabled=b);document.querySelectorAll("#intervals button, form button[type=submit]").forEach(el=>el.disabled=b);}
async function poll(){if(polling||mutation||document.hidden)return;polling=true;const rev=revision;try{const s=await api("/state");if(rev===revision&&!mutation)render(s);$("connection").classList.remove("offline");text("connection",tr("online"));}catch(e){$("connection").classList.add("offline");text("connection",tr("offline"));}finally{polling=false;}}
function render(s){
 s={...s,assets:asArray(s.assets),points:asArray(s.points),intervals:asArray(s.intervals),catalog:s.catalog?{...s.catalog,groups:asArray(s.catalog.groups)}:s.catalog};const old=state;state=s;const a=s.active||{},cfg=s.settings||{},fx=a.group==="fx";
 text("assetName",name(a));text("assetMeta",(a.symbol||"—")+" · "+market(a));text("currentMarket",tr(a.group));text("price",s.price_text||"—");text("currencyTag",(s.currency||"")+(s.unit_text||""));
 const chinese=a.group==="ashare"||a.group==="taiwan";const positive=Number(s.change)>=0;const color=(positive===chinese)?"#d54250":"#17815e";
 text("change",(positive?"↗ ":"↘ ")+(s.change_text||"—")+"  ("+(s.change_pct_text||"—")+")");$("change").style.color=color;
 text("quoteTime",fx?tr("daily"):(s.loading?tr("refreshing"):tr("next_update")+" "+(s.next_fetch_in_s??0)+"s"));
 text("updated",s.updated_text);text("high",s.max_price_text);text("low",s.min_price_text);text("version",s.version);
 const rawWarning=s.save_error||s.error||"";const warning=!s.save_error&&rawWarning.startsWith("quote unavailable;")?tr("quote_unavailable"):rawWarning;$("quoteWarning").title=rawWarning;$("quoteWarning").hidden=!warning;text("quoteWarning",warning);
 $("chartMode").value=cfg.mode||"line";$("ma").value=cfg.ma||"off";$("displayCurrency").value=cfg.currency||"USD";$("tilt").checked=cfg.tilt_enabled!==false;
 $("chartMode").parentElement.hidden=fx;$("ma").parentElement.hidden=fx;$("displayCurrency").hidden=fx;document.querySelector('label[for="displayCurrency"]').hidden=fx;document.querySelector(".settings-divider").hidden=fx;
 const sig=asArray(s.intervals).map(i=>i.label).join()+fx;
 if($("intervals").dataset.signature!==sig){$("intervals").replaceChildren();for(const i of asArray(s.intervals)){const b=document.createElement("button");b.type="button";b.dataset.interval=i.label;b.textContent=fx?({"7D":"7D","30D":"1M","90D":"3M","1Y":"1Y"}[i.fx_label]||i.fx_label):({"5m":"5m","1h":"1h","1day":"1D","7day":"1W"}[i.label]||i.label);b.onclick=()=>command("/set",{interval:i.label},"");$("intervals").append(b);}$("intervals").dataset.signature=sig;}
 for(const b of $("intervals").children){b.classList.toggle("active",b.dataset.interval===cfg.interval);b.setAttribute("aria-pressed",b.dataset.interval===cfg.interval);}
 text("sourceLabel",s.live_source||a.source);const pts=asArray(s.points);text("rangeLabel",pts.length?(timeLabel(pts[0].time)+" — "+timeLabel(pts[pts.length-1].time)):"—");
 const listSig=JSON.stringify(asArray(s.assets).map(x=>[x.id,x.text,x.custom]));
 if(listSig!==listSignature){listSignature=listSig;renderSaved();startSearch();}else markSelection();
 renderCatalog(s.catalog);drawChart();
 if(old&&JSON.stringify(old.catalog?.groups?.map(m=>[m.generation,m.outdated]))!==JSON.stringify(s.catalog?.groups?.map(m=>[m.generation,m.outdated])))startSearch();
 if(!old&&fx){$("fxBase").value=a.base||"USD";$("fxQuote").value=a.quote||"CNY";}
}
function normalizedAsset(a){if(a.secid||a.id)return a;return {...a,secid:a.market+"."+a.symbol,source:"eastmoney"};}
function isSelected(a){return state?.active&&(a.id===state.active.id||key(a)===key(state.active));}
function markSelection(){for(const el of $("results").children){const a=results[Number(el.dataset.index)];const selected=a&&isSelected(a);el.classList.toggle("selected",!!selected);el.setAttribute("aria-selected",!!selected);const mark=el.querySelector(".instrument-mark");if(mark)mark.textContent=selected?"●":(a.custom?"✓":"↗");}}
function renderResults(){
 const fragment=document.createDocumentFragment();
 results.forEach((a,i)=>{const b=document.createElement("button");b.type="button";b.className="instrument";b.dataset.index=i;b.id="result-"+i;b.setAttribute("role","option");const copy=document.createElement("span");copy.className="instrument-copy";const n=document.createElement("strong"),m=document.createElement("small"),mark=document.createElement("span");n.textContent=name(a);m.textContent=a.symbol+" · "+market(a);mark.className="instrument-mark";copy.append(n,m);b.append(copy,mark);b.onclick=()=>selectAsset(a);b.onkeydown=e=>{if(e.key==="ArrowDown"||e.key==="ArrowUp"){e.preventDefault();const target=e.key==="ArrowDown"?b.nextElementSibling:b.previousElementSibling;(target||$("search")).focus();}if(e.key==="Escape")$("search").focus();};fragment.append(b);});
 $("results").replaceChildren(fragment);markSelection();
}
async function selectAsset(a){const p=a.id?{asset:a.id}:{source:"eastmoney",symbol:a.symbol,name:a.text,market:String(a.market),group:a.group};await command("/set",p,"");}
function setBrowse(g){browse=g;searchToken++;for(const b of $("marketTabs").children){b.classList.toggle("active",b.dataset.group===g);b.setAttribute("aria-pressed",b.dataset.group===g);}$("stockPicker").hidden=g==="fx";$("fxForm").hidden=g!=="fx";if(g!=="fx")startSearch();}
function localMatches(q){return asArray(state?.assets).filter(a=>(browse==="all"||a.group===browse)&&(!onlySaved||a.custom)&&q.split(/\s+/).every(w=>(name(a)+" "+a.symbol).toLocaleLowerCase().includes(w)));}
function startSearch(){
 const token=++searchToken;searchWorking=false;const q=$("search").value.trim().toLocaleLowerCase();results=localMatches(q);renderResults();$("loadMore").hidden=true;text("listCaption",q?tr("search_results"):tr("common"));text("searchStatus","");
 searchJobs=[];if(onlySaved||browse==="fx"){if(!results.length)text("searchStatus",tr("no_results"));return;}
 const requested=browse==="all"?["ashare","hongkong","nasdaq","taiwan"]:[browse];
 for(const g of requested){const m=state?.catalog?.groups?.find(m=>m.group===g);if(m?.count&&!m.outdated)searchJobs.push({group:g,cursor:0,generation:m.generation});}
 if(!searchJobs.length){if(!results.length||q)text("searchStatus",requested.some(g=>["ashare","hongkong","nasdaq","taiwan"].includes(g))?tr(requested.some(g=>state?.catalog?.groups?.some(m=>m.group===g&&m.outdated))?"directory_outdated":"download_hint"):tr("no_results"));return;}
 // An empty query shows common/saved instruments first. Directory browsing is explicit.
 if(!q&&results.length){$("loadMore").hidden=false;return;}
 loadDirectoryResults(token);
}
async function loadDirectoryResults(token=searchToken){
 if(searchWorking)return;searchWorking=true;$("loadMore").hidden=true;text("searchStatus",tr("searching"));const initial=results.length,q=$("search").value.trim();
 try{while(searchJobs.length&&results.length-initial<30){
   if(token!==searchToken)return;const j=searchJobs[0];const data=await api("/catalog/search?"+new URLSearchParams({group:j.group,q,cursor:j.cursor,generation:j.generation}));if(token!==searchToken)return;
   const seen=new Set(results.map(key));for(const item of asArray(data.items)){const a=normalizedAsset(item);if(!seen.has(key(a))){results.push(a);seen.add(key(a));}}
   if(!data.next_cursor)searchJobs.shift();else j.cursor=data.next_cursor;
   renderResults();if(results.length>=600){searchJobs=[];break;}
  }
  text("searchStatus",results.length?results.length+" · "+tr("search_results"):tr("no_results"));
 }catch(e){if(token===searchToken)text("searchStatus",e.message);}finally{if(token===searchToken){searchWorking=false;$("loadMore").hidden=!searchJobs.length;}}
}
function renderSaved(){
 const saved=asArray(state?.assets).filter(a=>a.custom);text("savedCount",saved.length+" "+tr("saved"));$("savedManagement").replaceChildren();$("savedFx").replaceChildren();
 for(const a of saved){const row=document.createElement("div"),label=document.createElement("span"),button=document.createElement("button");row.className="saved-row";label.textContent=name(a)+" · "+a.symbol;button.type="button";button.textContent=tr("remove");button.onclick=()=>{if(confirm(tr("remove_confirm")+"\n"+name(a)))command("/custom/remove",{id:a.id});};row.append(label,button);$("savedManagement").append(row);}
 for(const a of asArray(state?.assets).filter(a=>a.group==="fx")){const b=document.createElement("button");b.type="button";b.textContent=a.base+" / "+a.quote;b.onclick=()=>{$("fxBase").value=a.base;$("fxQuote").value=a.quote;selectAsset(a);};$("savedFx").append(b);}
}
function renderCatalog(c){
 if(!c)return;const sig=JSON.stringify(c);if(sig===directorySignature)return;directorySignature=sig;
 const rows=asArray(c.groups);$("directoryRows").replaceChildren();
 for(const m of rows){const row=document.createElement("div"),info=document.createElement("div"),title=document.createElement("strong"),sub=document.createElement("small"),b=document.createElement("button");row.className="directory-row";title.textContent=tr(m.group==="fx"?"currency_directory":m.group);sub.textContent=m.outdated?tr("directory_outdated"):m.count?m.count.toLocaleString()+" · "+fmtBytes(m.bytes)+" · "+(m.updated?new Date(m.updated*1000).toLocaleDateString(LANG):"—"):tr("not_downloaded");info.append(title,sub);if(m.error){const error=document.createElement("small");error.className="directory-error";error.textContent=m.error;info.append(error);}b.type="button";b.className="text-button";b.textContent=tr(m.count?"update":"download");b.disabled=c.running;b.onclick=()=>updateDirectory(m.group);row.append(info,b);$("directoryRows").append(row);}
 const total=rows.reduce((n,m)=>n+m.count,0),bytes=rows.reduce((n,m)=>n+m.bytes,0);text("directorySummary",total?total.toLocaleString()+" · "+fmtBytes(bytes)+" · SD":tr("on_demand"));
 $("updateAll").disabled=c.running;$("downloadProgress").hidden=!c.running;text("downloadLabel",tr(c.group||"directories")+" · "+(c.downloaded||0)+" / "+(c.total||"—"));$("progress").value=c.total?c.downloaded/c.total*100:0;
 const fx=rows.find(m=>m.group==="fx");if(fx&&fx.generation!==currencyGeneration){currencyGeneration=fx.generation;loadCurrencies();}
 text("fxDirectoryHint",fx?.count?fx.count+" · "+tr("currency_directory"):tr("download_hint"));
}
async function updateDirectory(group){const s=await command("/catalog/update",{group},tr("directory_started"));if(s){$("directoryDetails").open=true;directorySignature="";renderCatalog(s.catalog);}}
async function loadCurrencies(){
 let downloaded=[];try{downloaded=asArray((await api("/catalog/currencies")).items);}catch(e){toast(e.message,true);}
 const map=new Map(FX_CURRENCIES.map(c=>[c.code,c[['zh','en','tw','ja'][LI]]]));for(const [code,label] of downloaded)if(!map.has(code))map.set(code,label);
 $("currencyOptions").replaceChildren();for(const [code,label] of [...map].sort((a,b)=>a[0].localeCompare(b[0]))){const option=document.createElement("option");option.value=code;option.label=code+" · "+label;$("currencyOptions").append(option);}
}
function syncCustom(){
 const src=$("customSource").value,fx=src==="fx";$("customGroupField").hidden=fx||src==="binance"||src==="twse";$("customMarketField").hidden=src!=="eastmoney";$("customSymbolField").hidden=fx;$("customNameField").hidden=fx;$("customBaseField").hidden=!fx;$("customQuoteField").hidden=!fx;$("customSymbol").required=!fx;
 $("customSymbol").placeholder=src==="binance"?"BTCUSDT":src==="twse"?"2330.TW / 6488.TWO":src==="yahoo"?"AAPL":"600519";
}
function fxParams(base,quote){base=base.trim().toUpperCase();quote=quote.trim().toUpperCase();if(!/^[A-Z]{3}$/.test(base)||!/^[A-Z]{3}$/.test(quote)||base===quote)throw new Error(tr("invalid_fx"));return {source:"fx",base_currency:base,quote_currency:quote};}
// Canvas chart: bounded by the device's 64 points; no external scripts or price requests.
function drawChart(){
 const canvas=$("chart"),rect=canvas.getBoundingClientRect(),dpr=Math.min(3,window.devicePixelRatio||1),w=rect.width,h=rect.height;
 if(!w||!h)return;canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);const ctx=canvas.getContext("2d");ctx.scale(dpr,dpr);ctx.clearRect(0,0,w,h);
 const points=asArray(state?.points).filter(p=>Number.isFinite(Number(p.close))),fx=state?.active?.group==="fx";$("chartEmpty").hidden=points.length>0;if(!points.length)return;
 const candle=state.settings.mode==="candle"&&!fx,pad={l:3,r:66,t:14,b:25},cw=w-pad.l-pad.r,ch=h-pad.t-pad.b;
 let low=Math.min(...points.map(p=>Number(candle?p.low:p.close))),high=Math.max(...points.map(p=>Number(candle?p.high:p.close)));let span=high-low;if(span<1e-8)span=Math.abs(high)*.01||1;low-=span*.1;high+=span*.1;
 const y=v=>pad.t+ch*(high-v)/(high-low),first=Number(points[0].time_value),last=Number(points.at(-1).time_value);
 const x=i=>pad.l+cw*(points.length===1?.5:(Number.isFinite(first)&&Number.isFinite(last)&&last>first?(points[i].time_value-first)/(last-first):i/(points.length-1)));
 const format=v=>Number(v).toLocaleString(LANG,{maximumFractionDigits:fx?5:2,minimumFractionDigits:fx?2:2});
 ctx.font="11px system-ui, sans-serif";ctx.textBaseline="middle";
 for(let i=0;i<=4;i++){const v=low+(high-low)*i/4,yy=y(v);ctx.strokeStyle="#e9edf3";ctx.setLineDash([3,4]);ctx.beginPath();ctx.moveTo(pad.l,yy);ctx.lineTo(pad.l+cw,yy);ctx.stroke();ctx.fillStyle="#8993a2";ctx.fillText(format(v),w-pad.r+9,yy);}ctx.setLineDash([]);
 const cn=["ashare","taiwan"].includes(state.active.group),up=cn?"#d54250":"#17815e",down=cn?"#17815e":"#d54250";
 if(candle){const bw=Math.max(2,Math.min(8,cw/points.length*.65));points.forEach((p,i)=>{ctx.strokeStyle=Number(p.close)>=Number(p.open)?up:down;ctx.fillStyle=ctx.strokeStyle;ctx.beginPath();ctx.moveTo(x(i),y(p.high));ctx.lineTo(x(i),y(p.low));ctx.stroke();ctx.fillRect(x(i)-bw/2,Math.min(y(p.open),y(p.close)),bw,Math.max(1,Math.abs(y(p.open)-y(p.close))));});}
 else{const gradient=ctx.createLinearGradient(0,pad.t,0,pad.t+ch);gradient.addColorStop(0,"#2459ed24");gradient.addColorStop(1,"#2459ed00");ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(x(i),y(p.close)):ctx.moveTo(x(i),y(p.close)));ctx.lineTo(x(points.length-1),pad.t+ch);ctx.lineTo(x(0),pad.t+ch);ctx.closePath();ctx.fillStyle=gradient;ctx.fill();ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(x(i),y(p.close)):ctx.moveTo(x(i),y(p.close)));ctx.strokeStyle="#2459ed";ctx.lineWidth=2;ctx.stroke();ctx.beginPath();ctx.arc(x(points.length-1),y(points.at(-1).close),3,0,Math.PI*2);ctx.fillStyle="#2459ed";ctx.fill();}
 const period=Number(state.settings.ma_period);if(!fx&&[10,20].includes(period)){ctx.beginPath();let started=false;for(let i=period-1;i<points.length;i++){const v=points.slice(i-period+1,i+1).reduce((n,p)=>n+Number(p.close),0)/period;if(started)ctx.lineTo(x(i),y(v));else{ctx.moveTo(x(i),y(v));started=true;}}ctx.strokeStyle="#e59827";ctx.lineWidth=1.5;ctx.stroke();}
 ctx.fillStyle="#8993a2";ctx.font="10px system-ui, sans-serif";const indices=[0,Math.floor((points.length-1)/2),points.length-1];indices.forEach((i,n)=>{ctx.textAlign=n===0?"left":n===2?"right":"center";ctx.fillText(timeLabel(points[i].time).slice(-11),x(i),h-6);});ctx.textAlign="left";
 if(chartHover!==null){let i=0,best=Infinity;points.forEach((p,k)=>{const distance=Math.abs(x(k)-chartHover);if(distance<best){best=distance;i=k;}});ctx.strokeStyle="#8b98ab";ctx.lineWidth=1;ctx.setLineDash([3,3]);ctx.beginPath();ctx.moveTo(x(i),pad.t);ctx.lineTo(x(i),pad.t+ch);ctx.stroke();ctx.setLineDash([]);text("chartTooltip",timeLabel(points[i].time)+"\n"+format(points[i].close)+" "+state.currency);$("chartTooltip").hidden=false;}
 else $("chartTooltip").hidden=true;
}
document.querySelectorAll("[data-t]").forEach(el=>{const k=el.dataset.t;if(LABELS[k])el.textContent=tr(k);});$("search").placeholder=tr("search");
for(const g of groups){const b=document.createElement("button");b.type="button";b.dataset.group=g;b.textContent=tr(g);b.onclick=()=>setBrowse(g);$("marketTabs").append(b);}
$("search").addEventListener("input",()=>{searchToken++;clearTimeout(searchTimer);searchTimer=setTimeout(startSearch,280);});
$("search").addEventListener("keydown",e=>{if(e.key==="ArrowDown"){e.preventDefault();$("results").firstElementChild?.focus();}if(e.key==="Enter"&&results.length===1){e.preventDefault();selectAsset(results[0]);}if(e.key==="Escape"){$("search").value="";startSearch();}});
document.addEventListener("keydown",e=>{if(e.key==="/"&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)){e.preventDefault();if(browse==="fx")setBrowse("all");$("search").focus();}});
$("savedOnly").onclick=()=>{onlySaved=!onlySaved;$("savedOnly").setAttribute("aria-pressed",onlySaved);startSearch();};$("loadMore").onclick=()=>loadDirectoryResults();
$("refresh").onclick=()=>command("/refresh",{},"");$("chartMode").onchange=()=>command("/set",{mode:$("chartMode").value},"");$("ma").onchange=()=>command("/set",{ma:$("ma").value},"");$("displayCurrency").onchange=()=>command("/set",{currency:$("displayCurrency").value},"");$("tilt").onchange=()=>command("/set",{tilt_enabled:$("tilt").checked});
$("swapFx").onclick=()=>{const temp=$("fxBase").value;$("fxBase").value=$("fxQuote").value;$("fxQuote").value=temp;};$("fxForm").onsubmit=e=>{e.preventDefault();try{command("/set",fxParams($("fxBase").value,$("fxQuote").value));}catch(err){toast(err.message,true);}};
$("customSource").onchange=syncCustom;$("customGroup").onchange=()=>{$("customMarket").value={ashare:"1",nasdaq:"105",metal:"101",taiwan:"178",hongkong:"116"}[$("customGroup").value];};
$("customMarket").onchange=()=>{$("customGroup").value={0:"ashare",1:"ashare",100:"nasdaq",101:"metal",105:"nasdaq",106:"nasdaq",107:"nasdaq",178:"taiwan",116:"hongkong"}[$("customMarket").value];};
$("customForm").onreset=()=>setTimeout(syncCustom,0);$("customForm").onsubmit=e=>{e.preventDefault();try{const source=$("customSource").value;const p=source==="fx"?fxParams($("customBase").value,$("customQuote").value):{source,symbol:$("customSymbol").value.trim(),name:$("customName").value.trim(),market:$("customMarket").value,group:source==="twse"?"taiwan":source==="binance"?"crypto":$("customGroup").value};command("/set",p);}catch(err){toast(err.message,true);}};
$("updateAll").onclick=()=>updateDirectory("all");$("cancelDownload").onclick=()=>command("/catalog/cancel",{},"");
$("chart").onpointermove=e=>{chartHover=e.clientX-$("chart").getBoundingClientRect().left;drawChart();};$("chart").onpointerleave=()=>{chartHover=null;drawChart();};
window.addEventListener("resize",drawChart);document.addEventListener("visibilitychange",()=>{if(!document.hidden)poll();});
for(const id of ["fxBase","fxQuote","customBase","customQuote"]){$(id).maxLength=64;$(id).onfocus=()=>$(id).select();}
syncCustom();setBrowse("all");loadCurrencies();poll();setInterval(poll,2500);
