// Offline syntax, locale and fallback tests. No browser/device mutations.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const packages=['launcher','BTC','weather','ebook','settings','NixieClock','../hidpad','../holopet','../youxia173-holocubic-apps/gold-miner'];
let scripts=0;
function checkFile(file){
  const source=fs.readFileSync(file,'utf8');
  if(file.endsWith('.js')){new vm.Script(source,{filename:file});scripts++;}
  if(/\.(html|lua)$/.test(file))for(const m of source.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)){
    const code=m[1].replace(/\]=\]\s*\.\.[\s\S]*?\.\.\s*\[=\[/g,'/api');
    if(code.trim()){new vm.Script(code,{filename:file});scripts++;}
  }
}
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory()){if(!['font','assets','vendor','books'].includes(e.name))walk(p);}else if(/\.(html|lua|js)$/.test(p))checkFile(p);}}
packages.forEach(p=>walk(path.join(root,p,'package')));
console.log(`PASS: ${scripts} standalone/embedded JS scripts parse`);
function functionCode(file,name){const source=fs.readFileSync(path.join(root,file),'utf8');const start=source.indexOf('function '+name+'(');assert.ok(start>=0,file);const end=source.indexOf('\n',start);return source.slice(start,end);}
let tests=0;
for(const [file,name]of [['launcher/package/control.js','normalizeLanguage'],['launcher/package/creator-guide.html','normalizeLanguage'],['launcher/package/store-preview.html','normalizeStoreLanguage'],['launcher/package/services/display_schedule/main.html','language'],['ebook/package/web.lua','norm'],['ebook/package/info.html','norm'],['../hidpad/package/info.html','normalize']]){
 const f=vm.runInNewContext('('+functionCode(file,name)+')',{}, {timeout:100});
 for(const [input,want]of [['en-US','en'],['DE_de','de'],['de-DE','de'],['ja-JP','ja'],['fr','en'],['zh-CN','zh-CN'],['zh-Hant','zh-TW']]){assert.equal(f(input),want,file+' '+input);tests++;}
}
console.log(`PASS: ${tests} JavaScript locale cases`);
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(path.join(root,'BTC/package/labels.js'),'utf8'),ctx);
vm.runInContext('Object.values(LABELS).forEach(row=>{if(!row[1]||!row[3]||!row[4])throw Error("missing locale");if(/[\\u3400-\\u9fff]/.test(row[1]+row[4]))throw Error("Chinese in en/de")})',ctx);
console.log('PASS: BTC English/German label columns have no Hanzi and Japanese fallback exists');
const external=fs.readFileSync(path.join(root,'launcher/package/control.js'),'utf8').trim();
const inline=fs.readFileSync(path.join(root,'launcher/package/main.html'),'utf8').match(/<script data-inline="launcher-control">([\s\S]*?)<\/script>/)[1].trim();
// These files already differ in user-owned temperature settings. Compare only
// our locale additions; never overwrite unrelated inline/external differences.
for(const marker of ['  COPY.de=','  function normalizeLanguage(','  function t(key)']) {
 const line=s=>s.split(/\r?\n/).find(x=>x.startsWith(marker));
 assert.ok(line(inline),marker);assert.equal(line(inline),line(external),marker);
}
console.log('PASS: Launcher locale additions match; existing non-locale differences preserved');
