local Web = {}
local JSON = rawget(_G, "json") or rawget(_G, "sjson")

local function escape_json(text)
  return tostring(text or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\b", "\\b"):gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function is_array(value)
  if type(value) ~= "table" then return false end
  local max, count = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    max = math.max(max, key); count = count + 1
  end
  return max == count
end

local function encode_json(value)
  if JSON and JSON.encode then
    local ok, raw = pcall(JSON.encode, value)
    if ok and type(raw) == "string" then return raw end
  end
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. escape_json(value) .. '"' end
  if kind == "table" then
    local out = {}
    if is_array(value) then for i = 1, #value do out[#out + 1] = encode_json(value[i]) end; return "[" .. table.concat(out, ",") .. "]" end
    for key, item in pairs(value) do out[#out + 1] = '"' .. escape_json(key) .. '":' .. encode_json(item) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return '"' .. escape_json(tostring(value)) .. '"'
end

local function response(status, content_type, body)
  return { status = status or "200 OK", type = content_type or "text/plain; charset=utf-8", headers = { ["cache-control"] = "no-store", ["connection"] = "close", ["access-control-allow-origin"] = "*" }, body = body or "" }
end

local function json_response(status, value)
  return response(status, "application/json; charset=utf-8", encode_json(value))
end

local function url_decode(text)
  return tostring(text or ""):gsub("+", " "):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function parse_query(query)
  local out = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then key, value = pair, "" end
    out[url_decode(key)] = url_decode(value)
  end
  return out
end

local function build_html(api, books_dir, language)
  local html = [==[
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>E-Book</title>
<style>
:root{color-scheme:dark;--bg:#050505;--panel:#0b0b0b;--line:#303030;--line2:#555;--text:#f5f5f5;--muted:#999;--accent:#fff;--danger:#ff8c8c}*{box-sizing:border-box}
body{margin:0;background:radial-gradient(circle at 50% -20%,#292929 0,transparent 38%),var(--bg);color:var(--text);font:15px/1.55 system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}button,input,select{font:inherit;color:inherit}
main{width:min(1080px,calc(100% - 24px));margin:20px auto 48px}.top{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-bottom:14px}.top-actions{display:flex;gap:8px;align-items:center}.eyebrow{font:11px Consolas,monospace;letter-spacing:1.8px;color:#aaa}h1{font-size:30px;margin:3px 0 3px}.sub{color:var(--muted);margin:0}.pill,.home{border:1px solid var(--line2);border-radius:999px;padding:7px 12px;background:#090909;white-space:nowrap}.home{color:#fff;text-decoration:none;font-weight:700}.home:hover{border-color:#fff}
.layout{display:grid;grid-template-columns:340px minmax(0,1fr);gap:14px}.card{border:1px solid var(--line);border-radius:14px;background:linear-gradient(145deg,#0e0e0e,#080808);padding:17px;box-shadow:0 18px 46px #0008}.card+ .card{margin-top:14px}h2{font-size:17px;margin:0 0 13px}.current{border:1px solid var(--line2);border-radius:12px;padding:15px;margin-bottom:12px}.current b{display:block;font-size:20px;margin-bottom:5px}.meta{display:flex;gap:10px;flex-wrap:wrap;color:var(--muted);font-size:12px}
.progress{height:7px;background:#181818;border:1px solid #333;border-radius:999px;overflow:hidden;margin:12px 0 8px}.progress i{display:block;height:100%;width:0;background:#fff;transition:width .18s}.actions{display:flex;gap:8px;flex-wrap:wrap}button{min-height:38px;border:1px solid #555;border-radius:9px;background:#0a0a0a;padding:0 13px;cursor:pointer;font-weight:700}button:hover{border-color:#fff}button.primary{background:#fff;color:#000;border-color:#fff}button.danger{color:var(--danger);border-color:#693d3d}button:disabled{opacity:.45;cursor:not-allowed}
label{display:grid;gap:6px;color:#bbb;font-size:12px;margin-bottom:10px}input[type=file],select{width:100%;min-height:42px;border:1px solid #444;border-radius:9px;background:#080808;padding:8px 10px}.appearance{display:grid;grid-template-columns:1fr 92px auto;gap:8px;align-items:end;margin-top:12px}.appearance label{margin:0}.appearance input[type=color]{width:100%;height:42px;border:1px solid #444;border-radius:9px;background:#080808;padding:4px}.upload-progress{height:9px;border:1px solid #444;border-radius:999px;overflow:hidden;margin:12px 0 7px}.upload-progress i{display:block;height:100%;width:0;background:#fff}.hint,.status{color:var(--muted);font-size:12px}.status{min-height:19px;margin-top:7px}.bad{color:var(--danger)}
.tabs{display:flex;gap:8px;margin-bottom:12px}.tabs button.active{background:#fff;color:#000;border-color:#fff}.list{display:grid;gap:8px}.item{border:1px solid var(--line);border-radius:11px;padding:11px 12px;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:12px;align-items:center;background:#090909}.item.active{border-color:#fff}.item b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.item small{display:block;color:var(--muted);margin-top:2px}.item .buttons{display:flex;gap:6px}.item button{min-height:34px;padding:0 10px}.empty{border:1px dashed #444;border-radius:11px;padding:28px;text-align:center;color:#888}.pager{display:flex;justify-content:space-between;align-items:center;margin-top:12px;color:#999;font-size:12px}
@media(max-width:780px){main{margin-top:12px}.layout{grid-template-columns:1fr}.top{align-items:flex-start;display:grid}.card{padding:14px}.item{grid-template-columns:1fr}.item .buttons{justify-content:flex-end}button,select,input{font-size:16px}}
</style></head><body><main>
<header class="top"><div><div class="eyebrow">STREAMING E-BOOK READER</div><h1 id="pageTitle">E-Book</h1><p id="subtitle" class="sub">Streaming pages · Background index · Reading progress</p></div><div class="top-actions"><div id="online" class="pill">Connecting</div><a id="home" class="home" href="/main">Home</a></div></header>
<div class="layout"><aside>
<section class="card"><h2 id="readingTitle">Reading</h2><div class="current"><b id="bookName">Not selected</b><div class="meta"><span id="bookSize">--</span><span id="chapterName">--</span><span id="readPercent">0.0%</span></div><div class="progress"><i id="readBar"></i></div><div id="indexStatus" class="hint">Waiting for a book</div></div><div class="actions"><button id="prev">Previous</button><button id="next">Next</button><button id="reindex">Rebuild index</button></div><div class="appearance"><label><span id="fontSizeLabel">Font size</span><select id="fontSize"><option value="16">16 px</option><option value="18">18 px</option></select></label><label><span id="textColorLabel">Text color</span><input id="textColor" type="color" value="#e9e4d8"></label><button id="applyAppearance">Apply</button></div></section>
<section class="card"><h2 id="importTitle">Import book</h2><label><span id="fileLabel">Choose EPUB / TXT / Markdown</span><input id="file" type="file" accept=".epub,.txt,.md,application/epub+zip,text/plain,text/markdown"></label><label><span id="encodingLabel">Source encoding (TXT only)</span><select id="encoding"><option id="encAuto" value="auto">Auto: UTF-8 / GB18030 / UTF-16</option><option value="utf-8">UTF-8</option><option value="gb18030">GB18030 / GBK</option><option value="utf-16le">UTF-16 LE</option><option value="utf-16be">UTF-16 BE</option></select></label><button id="upload" class="primary">Convert and upload</button><div class="upload-progress"><i id="uploadBar"></i></div><div id="uploadStatus" class="status">EPUB is expanded in this browser; the device reads cached chapters.</div></section>
</aside><section class="card"><div class="tabs"><button id="bookTab" class="active">Library</button><button id="tocTab">Contents</button><button id="refresh">Refresh</button></div><div id="list" class="list"></div><div id="pager" class="pager"></div></section></div>
</main><script>
const API='__API__',BOOKS='__BOOKS__',DEVICE_LANGUAGE='__LANG__';const $=id=>document.getElementById(id);let state=null,tab='books',chapterStart=1,uploading=false,locale='en';
const I={
'zh-CN':{title:'电子书',home:'回到主页',subtitle:'流式分页 · 持久目录 · 断点续读',connecting:'正在连接',online:'设备在线',failed:'连接失败',reading:'正在阅读',none:'尚未选择',waiting:'等待电子书',indexWaiting:'等待目录',prev:'上一页',next:'下一页',reindex:'重建目录',fontSize:'字号',textColor:'文字颜色',apply:'应用',import:'导入电子书',choose:'选择 EPUB / TXT / Markdown',encoding:'原文件编码（仅 TXT）',autoEncoding:'自动识别 UTF-8 / GB18030 / UTF-16',upload:'转换并上传',uploadHint:'EPUB 在当前浏览器解包并转换插图，设备只读取章节与图片缓存。',library:'书库',toc:'章节目录',refresh:'刷新',read:'阅读',del:'删除',empty:'书库为空，请先上传电子书',item:'第 {n} 项 · 偏移 {o}',jump:'跳转',building:'正在后台生成目录 {p}%',noChapter:'暂无章节',prevGroup:'上一组',nextGroup:'下一组',requestFailed:'请求失败',confirmDelete:'确定删除这本电子书？',chooseFile:'请先选择文件',checking:'正在检查文件…',corrupted:'该文件已经被错误转码，请重新选择未经转换的原始文件。',extracting:'正在解析 EPUB 和图片…',epubInvalid:'EPUB 缺少有效的 container.xml、OPF 或正文。',epubUnsupported:'当前浏览器不支持 EPUB 解压，请使用新版 Chrome 或 Edge。',uploading:'上传中 {a} / {b} · {p}%',uploadFailed:'上传失败 HTTP ',networkFailed:'网络传输失败',refreshing:'上传完成，正在刷新书库…',opened:'已上传并打开'},
'zh-TW':{title:'電子書',home:'回到主頁',subtitle:'串流分頁 · 持久目錄 · 閱讀進度',connecting:'正在連線',online:'裝置在線',failed:'連線失敗',reading:'正在閱讀',none:'尚未選擇',waiting:'等待電子書',indexWaiting:'等待目錄',prev:'上一頁',next:'下一頁',reindex:'重建目錄',fontSize:'字號',textColor:'文字顏色',apply:'套用',import:'匯入電子書',choose:'選擇 EPUB / TXT / Markdown',encoding:'原始檔案編碼（僅 TXT）',autoEncoding:'自動識別 UTF-8 / GB18030 / UTF-16',upload:'轉換並上傳',uploadHint:'EPUB 在目前瀏覽器解壓，裝置只讀取章節快取。',library:'書庫',toc:'章節目錄',refresh:'重新整理',read:'閱讀',del:'刪除',empty:'書庫為空，請先上傳電子書',item:'第 {n} 項 · 偏移 {o}',jump:'跳轉',building:'正在背景產生目錄 {p}%',noChapter:'暫無章節',prevGroup:'上一組',nextGroup:'下一組',requestFailed:'請求失敗',confirmDelete:'確定刪除這本電子書？',chooseFile:'請先選擇檔案',checking:'正在檢查檔案…',corrupted:'此檔案已被錯誤轉碼，請重新選擇未轉換的原始檔案。',extracting:'正在解析 EPUB…',epubInvalid:'EPUB 缺少有效的 container.xml、OPF 或正文。',epubUnsupported:'目前瀏覽器不支援 EPUB 解壓，請使用新版 Chrome 或 Edge。',uploading:'上傳中 {a} / {b} · {p}%',uploadFailed:'上傳失敗 HTTP ',networkFailed:'網路傳輸失敗',refreshing:'上傳完成，正在重新整理書庫…',opened:'已上傳並開啟'},
ja:{title:'電子書',home:'ホームへ戻る',subtitle:'ストリーミングページ · 永続目次 · 読書位置',connecting:'接続中',online:'デバイス接続済み',failed:'接続失敗',reading:'読書中',none:'未選択',waiting:'本を待っています',indexWaiting:'目次を待っています',prev:'前ページ',next:'次ページ',reindex:'目次を再作成',fontSize:'文字サイズ',textColor:'文字色',apply:'適用',import:'本を取り込む',choose:'EPUB / TXT / Markdown を選択',encoding:'元ファイルの文字コード（TXT のみ）',autoEncoding:'UTF-8 / GB18030 / UTF-16 を自動判定',upload:'変換して送信',uploadHint:'EPUB はブラウザーで展開し、端末は章キャッシュだけを読みます。',library:'ライブラリ',toc:'目次',refresh:'更新',read:'読む',del:'削除',empty:'ライブラリは空です。本をアップロードしてください。',item:'{n} 番 · オフセット {o}',jump:'移動',building:'目次を作成中 {p}%',noChapter:'章がありません',prevGroup:'前へ',nextGroup:'次へ',requestFailed:'要求失敗',confirmDelete:'この本を削除しますか？',chooseFile:'ファイルを選択してください',checking:'ファイルを確認中…',corrupted:'このファイルは誤って変換済みです。変換前の元ファイルを選択してください。',extracting:'EPUB を解析中…',epubInvalid:'EPUB に有効な container.xml、OPF、本文がありません。',epubUnsupported:'このブラウザーは EPUB 展開に未対応です。新しい Chrome / Edge を使用してください。',uploading:'送信中 {a} / {b} · {p}%',uploadFailed:'送信失敗 HTTP ',networkFailed:'通信失敗',refreshing:'送信完了。ライブラリを更新中…',opened:'送信して開きました'},
en:{title:'E-Book',home:'Home',subtitle:'Streaming pages · Persistent contents · Reading progress',connecting:'Connecting',online:'Device online',failed:'Connection failed',reading:'Reading',none:'Not selected',waiting:'Waiting for a book',indexWaiting:'Waiting for contents',prev:'Previous',next:'Next',reindex:'Rebuild index',fontSize:'Font size',textColor:'Text color',apply:'Apply',import:'Import book',choose:'Choose EPUB / TXT / Markdown',encoding:'Source encoding (TXT only)',autoEncoding:'Auto-detect UTF-8 / GB18030 / UTF-16',upload:'Convert and upload',uploadHint:'EPUB is expanded in this browser; the device reads cached chapters.',library:'Library',toc:'Contents',refresh:'Refresh',read:'Read',del:'Delete',empty:'Library is empty. Upload a book first.',item:'Item {n} · offset {o}',jump:'Open',building:'Building contents {p}%',noChapter:'No chapters',prevGroup:'Previous',nextGroup:'Next',requestFailed:'Request failed',confirmDelete:'Delete this book?',chooseFile:'Choose a file first',checking:'Checking file…',corrupted:'This file was already converted incorrectly. Select the untouched original file.',extracting:'Parsing EPUB…',epubInvalid:'EPUB has no valid container.xml, OPF, or readable content.',epubUnsupported:'This browser cannot expand EPUB. Use a current Chrome or Edge.',uploading:'Uploading {a} / {b} · {p}%',uploadFailed:'Upload failed HTTP ',networkFailed:'Network transfer failed',refreshing:'Uploaded. Refreshing library…',opened:'Uploaded and opened'}};
function norm(v){v=String(v||'').replaceAll('_','-');if(/^en(?:-|$)/i.test(v))return'en';if(/^ja(?:-|$)/i.test(v))return'ja';if(/^zh-(?:TW|HK|Hant)/i.test(v))return'zh-TW';return'zh-CN'}
function t(k,a={}){let s=(I[locale]||I.en)[k]||I.en[k]||k;for(const [x,v]of Object.entries(a))s=s.replaceAll('{'+x+'}',v);return s}
function applyLanguage(v){locale=norm(v);document.documentElement.lang=locale;document.title=t('title');const m={pageTitle:'title',home:'home',subtitle:'subtitle',online:'connecting',readingTitle:'reading',bookName:'none',indexStatus:'waiting',prev:'prev',next:'next',reindex:'reindex',fontSizeLabel:'fontSize',textColorLabel:'textColor',applyAppearance:'apply',importTitle:'import',fileLabel:'choose',encodingLabel:'encoding',encAuto:'autoEncoding',upload:'upload',uploadStatus:'uploadHint',bookTab:'library',tocTab:'toc',refresh:'refresh'};for(const[id,k]of Object.entries(m))if($(id))$(id).textContent=t(k)}
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const bytes=n=>{n=Number(n)||0;if(n<1024)return n+' B';if(n<1048576)return(n/1024).toFixed(1)+' KB';return(n/1048576).toFixed(2)+' MB'};
async function get(path){const r=await fetch(API+path,{cache:'no-store'});const d=await r.json();if(!r.ok||d.ok===false)throw Error(d.error||d.message||t('requestFailed'));return d}
async function action(name,data={}){const p=new URLSearchParams({action:name,...data});const d=await get('/action?'+p);await refreshState();return d}
function renderState(s){state=s;if(s.language&&norm(s.language)!==locale)applyLanguage(s.language);$('online').textContent=t('online');const c=s.current;$('bookName').textContent=c?c.name:t('none');$('bookSize').textContent=c?bytes(c.size):'--';$('chapterName').textContent=s.chapter_title||'--';$('readPercent').textContent=Number(s.progress||0).toFixed(1)+'%';$('readBar').style.width=Math.min(100,Number(s.progress||0))+'%';$('indexStatus').textContent=s.index_message||t('indexWaiting');$('prev').disabled=!s.previous_available;$('next').disabled=!s.next_available;$('reindex').disabled=!c;if(document.activeElement!==$('fontSize'))$('fontSize').value=String(s.font_size||18);if(document.activeElement!==$('textColor'))$('textColor').value=String(s.text_color||'#E9E4D8').toLowerCase();if(tab==='books')renderBooks(s.books||[])}
function renderBooks(books){$('pager').innerHTML='';$('list').innerHTML=books.length?books.map(b=>`<div class="item ${state.current&&state.current.path===b.path?'active':''}"><div><b>${esc(b.name)}</b><small>${esc(b.file_name)} · ${bytes(b.size)}</small></div><div class="buttons"><button class="open" data-path="${esc(b.path)}">${t('read')}</button><button class="danger del" data-path="${esc(b.path)}">${t('del')}</button></div></div>`).join(''):`<div class="empty">${t('empty')}</div>`}
async function renderChapters(start=1){tab='toc';chapterStart=start;$('bookTab').classList.remove('active');$('tocTab').classList.add('active');const d=await get('/chapters?start='+start+'&limit=80');$('list').innerHTML=d.items.length?d.items.map(x=>`<div class="item ${state&&state.current_chapter===x.index?'active':''}"><div><b>${esc(x.title)}</b><small>${t('item',{n:x.index,o:x.offset})}</small></div><div class="buttons"><button class="jump" data-index="${x.index}">${t('jump')}</button></div></div>`).join(''):`<div class="empty">${d.scanning?t('building',{p:d.progress}):t('noChapter')}</div>`;const prev=Math.max(1,start-80),next=start+80;$('pager').innerHTML=`<button id="pagePrev" ${start<=1?'disabled':''}>${t('prevGroup')}</button><span>${start}-${Math.min(d.total,start+79)} / ${d.total}</span><button id="pageNext" ${next>d.total?'disabled':''}>${t('nextGroup')}</button>`;$('pagePrev').onclick=()=>renderChapters(prev);$('pageNext').onclick=()=>renderChapters(next)}
async function refreshState(){try{const s=await get('/state');renderState(s);if(tab==='toc')await renderChapters(chapterStart)}catch(e){$('online').textContent=t('failed');$('uploadStatus').textContent=e.message}}
$('bookTab').onclick=()=>{tab='books';$('bookTab').classList.add('active');$('tocTab').classList.remove('active');renderBooks(state?.books||[])};$('tocTab').onclick=()=>renderChapters(1);$('refresh').onclick=()=>action('refresh');$('prev').onclick=()=>action('prev');$('next').onclick=()=>action('next');$('reindex').onclick=()=>action('reindex');
$('applyAppearance').onclick=()=>action('appearance',{size:$('fontSize').value,color:$('textColor').value});
$('list').onclick=e=>{const b=e.target.closest('button');if(!b)return;if(b.classList.contains('open'))action('open',{path:b.dataset.path});if(b.classList.contains('jump'))action('jump',{index:b.dataset.index});if(b.classList.contains('del')&&confirm(t('confirmDelete')))action('delete',{path:b.dataset.path})};
function safeName(name,ext='.txt'){let n=String(name||('book'+ext)).replace(/[\\/:*?"<>|\x00-\x1f]/g,'_').replace(/^\.+/,'').slice(0,100);if(ext&& !n.toLowerCase().endsWith(ext))n=n.replace(/\.[^.]+$/,'')+ext;return n||('book'+ext)}
function utf16Guess(bytes){const n=Math.min(bytes.length,1024);let even=0,odd=0,pairs=Math.floor(n/2);for(let i=0;i+1<n;i+=2){if(bytes[i]===0)even++;if(bytes[i+1]===0)odd++}if(pairs>8&&odd/pairs>.2&&even/pairs<.08)return'utf-16le';if(pairs>8&&even/pairs>.2&&odd/pairs<.08)return'utf-16be';return null}
async function prepare(file,encoding){if(encoding==='utf-8')return file;const buf=await file.arrayBuffer();let bytes=new Uint8Array(buf),enc=encoding;const damaged=bytes.length>7&&bytes.slice(0,6).every((v,i)=>v===[0xef,0xbf,0xbd,0xef,0xbf,0xbd][i]);if(damaged)throw Error(t('corrupted'));if(enc==='auto'){if(bytes[0]===0xff&&bytes[1]===0xfe)enc='utf-16le';else if(bytes[0]===0xfe&&bytes[1]===0xff)enc='utf-16be';else enc=utf16Guess(bytes)||'utf-8'}let text;if(enc==='utf-8'){try{text=new TextDecoder('utf-8',{fatal:true}).decode(bytes)}catch{text=new TextDecoder('gb18030').decode(bytes)}}else{text=new TextDecoder(enc).decode(bytes);if(text.charCodeAt(0)===0xfeff)text=text.slice(1)}return new Blob([text],{type:'text/plain;charset=utf-8'})}
function uploadFs(blob,path,onProgress){return new Promise((resolve,reject)=>{const x=new XMLHttpRequest();x.open('PUT','/api/system/fs/upload?path='+encodeURIComponent(path));x.upload.onprogress=e=>{if(e.lengthComputable&&onProgress)onProgress(e.loaded,e.total)};x.onload=()=>{if(x.status>=200&&x.status<300)resolve();else reject(Error(t('uploadFailed')+x.status))};x.onerror=()=>reject(Error(t('networkFailed')));x.send(blob)})}
function zipNorm(path,base=''){path=String(path||'').split('#')[0].replaceAll('\\','/');try{path=decodeURIComponent(path)}catch{}if(base&&!path.startsWith('/'))path=base+path;const out=[];for(const part of path.split('/')){if(!part||part==='.')continue;if(part==='..')out.pop();else out.push(part)}return out.join('/')}
function zipOpen(bytes){const d=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let e=-1;for(let i=Math.max(0,bytes.length-22);i>=Math.max(0,bytes.length-65557);i--)if(d.getUint32(i,true)===0x06054b50){e=i;break}if(e<0)throw Error(t('epubInvalid'));let p=d.getUint32(e+16,true),count=d.getUint16(e+10,true),files=new Map(),dec=new TextDecoder('utf-8');for(let i=0;i<count;i++){if(d.getUint32(p,true)!==0x02014b50)throw Error(t('epubInvalid'));const method=d.getUint16(p+10,true),packed=d.getUint32(p+20,true),size=d.getUint32(p+24,true),nl=d.getUint16(p+28,true),xl=d.getUint16(p+30,true),cl=d.getUint16(p+32,true),local=d.getUint32(p+42,true),name=zipNorm(dec.decode(bytes.slice(p+46,p+46+nl)));files.set(name,{method,packed,size,local});p+=46+nl+xl+cl}async function extract(path){path=zipNorm(path);const z=files.get(path);if(!z)throw Error(t('epubInvalid')+' '+path);if(d.getUint32(z.local,true)!==0x04034b50)throw Error(t('epubInvalid'));const start=z.local+30+d.getUint16(z.local+26,true)+d.getUint16(z.local+28,true),raw=bytes.slice(start,start+z.packed);if(z.method===0)return raw;if(z.method!==8||typeof DecompressionStream==='undefined')throw Error(t('epubUnsupported'));try{const stream=new Blob([raw]).stream().pipeThrough(new DecompressionStream('deflate-raw'));return new Uint8Array(await new Response(stream).arrayBuffer())}catch{throw Error(t('epubUnsupported'))}}return{files,extract}}
const xmlNodes=(doc,name)=>[...doc.getElementsByTagName('*')].filter(n=>String(n.localName||n.nodeName).toLowerCase()===name.toLowerCase());
const xmlParse=raw=>new DOMParser().parseFromString(new TextDecoder('utf-8').decode(raw),'application/xml');
function htmlBlocks(raw){
  const doc=new DOMParser().parseFromString(new TextDecoder('utf-8').decode(raw),'text/html');
  const blockTags=new Set(['address','article','aside','blockquote','div','dl','dt','dd','figcaption','figure','footer','h1','h2','h3','h4','h5','h6','header','li','main','nav','ol','p','pre','section','table','tr','ul']);
  const skipTags=new Set(['script','style','noscript','svg']);
  const out=[];
  function walk(n){
    if(n.nodeType===3){out.push({type:'text',value:n.nodeValue});return}
    if(n.nodeType!==1)return;
    const tag=n.tagName.toLowerCase();
    if(tag==='img'||tag==='image'){
      const src=n.getAttribute('src')||n.getAttribute('data-src')||n.getAttribute('href')||n.getAttribute('xlink:href');
      if(src)out.push({type:'image',src,alt:n.getAttribute('alt')||''});
      return;
    }
    if(tag==='svg'){
      for(const image of n.querySelectorAll('image'))walk(image);
      return;
    }
    if(skipTags.has(tag))return;
    if(tag==='br'||blockTags.has(tag))out.push({type:'text',value:'\n'});
    for(const child of n.childNodes)walk(child);
    if(blockTags.has(tag))out.push({type:'text',value:'\n'});
  }
  walk(doc.body||doc.documentElement);
  return{doc,blocks:out};
}
function cleanBookText(text){return String(text||'').replace(/\u00a0/g,' ').replace(/[ \t]+\n/g,'\n').replace(/\n[ \t]+/g,'\n').replace(/\n{3,}/g,'\n\n').trim()+'\n'}
async function decodeBrowserImage(blob){
  if(typeof createImageBitmap==='function'){
    try{return await createImageBitmap(blob,{imageOrientation:'from-image'})}catch{}
  }
  return await new Promise((resolve,reject)=>{const url=URL.createObjectURL(blob),img=new Image();img.onload=()=>{URL.revokeObjectURL(url);resolve(img)};img.onerror=()=>{URL.revokeObjectURL(url);reject(Error('image decode failed'))};img.src=url});
}
async function canvasBlob(canvas,type,quality){return await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('image conversion failed')),type,quality))}
function fnv(text){let h=2166136261;for(let i=0;i<text.length;i++){h^=text.charCodeAt(i);h=Math.imul(h,16777619)}return(h>>>0).toString(16).padStart(8,'0')}
async function prepareEpub(file){
  $('uploadStatus').textContent=t('extracting');
  const zip=zipOpen(new Uint8Array(await file.arrayBuffer()));
  const container=xmlParse(await zip.extract('META-INF/container.xml'));
  const root=xmlNodes(container,'rootfile')[0]?.getAttribute('full-path');
  if(!root)throw Error(t('epubInvalid'));
  const opf=xmlParse(await zip.extract(root));
  const base=root.includes('/')?root.slice(0,root.lastIndexOf('/')+1):'';
  const items=new Map(),itemsByPath=new Map();
  for(const node of xmlNodes(opf,'item')){
    const id=node.getAttribute('id'),href=node.getAttribute('href');
    if(id&&href){const item={id,path:zipNorm(href,base),media:node.getAttribute('media-type')||'',props:node.getAttribute('properties')||''};items.set(id,item);itemsByPath.set(item.path,item)}
  }
  const spine=xmlNodes(opf,'itemref').map(node=>items.get(node.getAttribute('idref'))).filter(Boolean);
  const title=(xmlNodes(opf,'title')[0]?.textContent||file.name.replace(/\.epub$/i,'')).trim();
  const author=(xmlNodes(opf,'creator')[0]?.textContent||'').trim();
  const toc=new Map(),nav=[...items.values()].find(x=>/(^|\s)nav(\s|$)/.test(x.props));
  if(nav){
    const nd=new DOMParser().parseFromString(new TextDecoder('utf-8').decode(await zip.extract(nav.path)),'text/html');
    const navBase=nav.path.includes('/')?nav.path.slice(0,nav.path.lastIndexOf('/')+1):'';
    for(const anchor of nd.querySelectorAll('a[href]')){const path=zipNorm(anchor.getAttribute('href'),navBase);if(path&&!toc.has(path))toc.set(path,anchor.textContent.trim())}
  }else{
    const ncx=[...items.values()].find(x=>x.media==='application/x-dtbncx+xml');
    if(ncx){const nd=xmlParse(await zip.extract(ncx.path)),ncxBase=ncx.path.includes('/')?ncx.path.slice(0,ncx.path.lastIndexOf('/')+1):'';for(const point of xmlNodes(nd,'navPoint')){const src=xmlNodes(point,'content')[0]?.getAttribute('src'),label=xmlNodes(point,'text')[0]?.textContent?.trim();if(src&&label)toc.set(zipNorm(src,ncxBase),label)}}
  }
  const images=[],imageMap=new Map();
  async function prepareImage(path,alt){
    path=zipNorm(path);
    if(imageMap.has(path)){const old=imageMap.get(path);if(!old.alt&&alt)old.alt=alt;return old}
    const item=itemsByPath.get(path),media=item?.media||(/\.png$/i.test(path)?'image/png':/\.svg$/i.test(path)?'image/svg+xml':/\.gif$/i.test(path)?'image/gif':'image/jpeg');
    try{
      const source=new Blob([await zip.extract(path)],{type:media});
      const bitmap=await decodeBrowserImage(source),width=bitmap.naturalWidth||bitmap.width,height=bitmap.naturalHeight||bitmap.height;
      if(!width||!height)throw Error('empty image');
      const scale=Math.min(1,296/width,174/height),targetWidth=Math.max(1,Math.round(width*scale)),targetHeight=Math.max(1,Math.round(height*scale));
      const canvas=document.createElement('canvas');canvas.width=targetWidth;canvas.height=targetHeight;
      const ctx=canvas.getContext('2d',{alpha:true});ctx.fillStyle='#000';ctx.fillRect(0,0,targetWidth,targetHeight);ctx.drawImage(bitmap,0,0,targetWidth,targetHeight);
      if(bitmap.close)bitmap.close();
      const lossless=/png|svg|gif/i.test(media),type=lossless?'image/png':'image/jpeg',blob=await canvasBlob(canvas,type,.82);
      const image={index:images.length+1,blob,width:targetWidth,height:targetHeight,ext:lossless?'png':'jpg',alt:String(alt||'').slice(0,120)};
      images.push(image);imageMap.set(path,image);return image;
    }catch{return null}
  }
  const sections=[];
  for(let i=0;i<spine.length&&sections.length<4096;i++){
    const item=spine[i];
    if(!/xhtml|html/i.test(item.media)&&!/[.]x?html?$/i.test(item.path))continue;
    const raw=await zip.extract(item.path),parsed=htmlBlocks(raw),sectionBase=item.path.includes('/')?item.path.slice(0,item.path.lastIndexOf('/')+1):'',parts=[];
    for(const block of parsed.blocks){
      if(block.type==='text'){parts.push(block.value);continue}
      const image=await prepareImage(zipNorm(block.src,sectionBase),block.alt);
      if(image)parts.push('\n[[EPUBIMG:'+image.index+']]\n');else if(block.alt)parts.push('\n'+block.alt+'\n');
    }
    const text=cleanBookText(parts.join(''));
    if(!text.trim())continue;
    const heading=parsed.doc.querySelector('h1,h2,h3,title')?.textContent?.trim(),label=toc.get(item.path)||heading||('Chapter '+(sections.length+1));
    sections.push({title:label.slice(0,120),blob:new Blob([text],{type:'text/plain;charset=utf-8'})});
  }
  if(!sections.length)throw Error(t('epubInvalid'));
  return{title,author,sections,images};
}
async function uploadEpub(file){
  const book=await prepareEpub(file),key=fnv(file.name+'|'+file.size+'|'+file.lastModified),cache=BOOKS+'/.epub/'+key,sectionDir=cache+'/sections',imageDir=cache+'/images',base=safeName(file.name.replace(/\.epub$/i,''),''),manifestPath=BOOKS+'/'+safeName(base,'.epubbook');
  await action('prepare_epub',{cache});
  const sectionData=book.sections.map((s,i)=>({title:s.title,path:sectionDir+'/'+String(i).padStart(4,'0')+'.txt',size:s.blob.size,blob:s.blob}));
  const imageData=book.images.map(image=>({...image,path:imageDir+'/'+String(image.index-1).padStart(4,'0')+'.'+image.ext,size:image.blob.size}));
  const manifest={version:2,format:'epub',title:book.title,author:book.author,source_name:file.name,cache_dir:cache,total_size:sectionData.reduce((a,x)=>a+x.size,0),sections:sectionData.map(({title,path,size})=>({title,path,size})),images:imageData.map(({path,width,height,alt})=>({path,width,height,alt}))};
  const manifestBlob=new Blob([JSON.stringify(manifest)],{type:'application/json;charset=utf-8'}),allFiles=[...imageData,...sectionData],total=allFiles.reduce((a,x)=>a+x.size,0)+manifestBlob.size;
  let done=0;const progress=loaded=>{const n=done+loaded,p=total?n*100/total:100;$('uploadBar').style.width=p+'%';$('uploadStatus').textContent=t('uploading',{a:bytes(n),b:bytes(total),p:p.toFixed(0)})};
  for(const item of allFiles){await uploadFs(item.blob,item.path,progress);done+=item.size}
  await uploadFs(manifestBlob,manifestPath,progress);return manifestPath;
}
$('file').onchange=()=>{$('encoding').disabled=/\.epub$/i.test($('file').files[0]?.name||'')};
$('upload').onclick=async()=>{const file=$('file').files[0];if(!file)return $('uploadStatus').textContent=t('chooseFile');if(uploading)return;uploading=true;$('upload').disabled=true;$('uploadStatus').className='status';$('uploadBar').style.width='0';try{$('uploadStatus').textContent=t('checking');let path;if(/\.epub$/i.test(file.name)){path=await uploadEpub(file)}else{const body=await prepare(file,$('encoding').value);path=BOOKS+'/'+safeName(file.name,/\.md$/i.test(file.name)?'.md':'.txt');await uploadFs(body,path,(loaded,total)=>{const p=total?loaded*100/total:100;$('uploadBar').style.width=p+'%';$('uploadStatus').textContent=t('uploading',{a:bytes(loaded),b:bytes(total),p:p.toFixed(0)})})}$('uploadStatus').textContent=t('refreshing');await action('refresh');await action('open',{path});$('uploadStatus').textContent=t('opened');$('uploadBar').style.width='100%'}catch(e){$('uploadStatus').className='status bad';$('uploadStatus').textContent=e.message}finally{uploading=false;$('upload').disabled=false}};
applyLanguage(DEVICE_LANGUAGE);setInterval(()=>{if(!uploading)refreshState()},1500);refreshState();
</script></body></html>
]==]
  html = html:gsub("__API__", api)
  html = html:gsub("__BOOKS__", books_dir)
  html = html:gsub("__LANG__", tostring(language or "en"))
  return html
end

function Web.new(opts)
  opts = opts or {}
  local self = { app = opts.app, route_base = opts.route_base or "/ebook", api_prefix = (opts.route_base or "/ebook") .. "/api", books_dir = opts.books_dir or "/sd/ebooks", routes = {}, started = false }

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic then return false end
    local ok = pcall(httpd.dynamic, method, route, handler)
    if ok then self.routes[#self.routes + 1] = { method = method, route = route } end
    return ok
  end

  function self:start()
    if self.started or not httpd or not httpd.start then return end
    pcall(httpd.start, { webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 256 })
    local index = build_html(self.api_prefix, self.books_dir, self.app and self.app.language)
    local function page() return response("200 OK", "text/html; charset=utf-8", index) end
    self:register(httpd.GET, self.route_base, page)
    self:register(httpd.GET, self.route_base .. "/", page)
    self:register(httpd.GET, self.api_prefix .. "/state", function() return json_response("200 OK", self.app:snapshot()) end)
    self:register(httpd.GET, self.api_prefix .. "/chapters", function(req)
      local q = parse_query(req and req.query or "")
      return json_response("200 OK", self.app:chapters_slice(q.start, q.limit))
    end)
    self:register(httpd.GET, self.api_prefix .. "/action", function(req)
      local q = parse_query(req and req.query or "")
      local action, ok, err = q.action, true, nil
      if action == "open" then ok, err = self.app:open_book(q.path, false)
      elseif action == "prev" then ok, err = self.app:prev_page()
      elseif action == "next" then ok, err = self.app:next_page()
      elseif action == "jump" then ok, err = self.app:jump_chapter(q.index)
      elseif action == "refresh" then
        self.app:refresh_library()
        if not self.app.current and #self.app.books > 0 then ok, err = self.app:open_book(self.app.books[1].path, false) end
      elseif action == "prepare_epub" then ok, err = self.app:prepare_epub_cache(q.cache)
      elseif action == "reindex" then
        if self.app.current then ok = self.app:start_index(self.app.current, true) else ok, err = false, self.app:translate("no_book") end
      elseif action == "appearance" then ok, err = self.app:apply_appearance(q.size, q.color, true)
      elseif action == "delete" then ok, err = self.app:remove_book(q.path)
      else ok, err = false, self.app:translate("unknown_action") end
      local result = self.app:snapshot(err)
      result.ok, result.error = ok ~= false, err
      return json_response(ok == false and "409 Conflict" or "200 OK", result)
    end)
    self:register(httpd.GET, self.api_prefix .. "/health", function() return response("200 OK", "text/plain; charset=utf-8", "ok") end)
    self.started = true
  end

  function self:stop()
    if httpd and httpd.unregister then for i = #self.routes, 1, -1 do local item = self.routes[i]; pcall(httpd.unregister, item.method, item.route) end end
    self.routes = {}; self.started = false
  end
  return self
end

return Web
