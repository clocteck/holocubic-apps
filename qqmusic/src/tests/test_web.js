// Execute the shipped control script against a minimal DOM, no browser automation.
const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.listeners={};this.dataset={};this.hidden=false;this.scrollTop=0;this.value=0;this.attributes={};this.className='';this.textContent='';this.style={};this.classes=new Set();this.classList={toggle:(c,on)=>{if(on)this.classes.add(c);else this.classes.delete(c);}};}
 append(...c){this.children.push(...c);} replaceChildren(...c){this.children=c;} addEventListener(k,v){this.listeners[k]=v;}
 setAttribute(k,v){this.attributes[k]=v;}getAttribute(k){return this.attributes[k]||null;}removeAttribute(k){delete this.attributes[k];}
 querySelectorAll(q){return q==='.row'?this.children.filter(c=>c.className?.startsWith('row')):[];}
 showModal(){this.open=true;}close(){this.open=false;}
}
const html=fs.readFileSync(path.join(__dirname,'../../package/control.html'),'utf8');const elements={};
for(const m of html.matchAll(/\bid="([^"]+)"/g))elements[m[1]]=new Element();
const tabs=Array.from(html.matchAll(/data-tab="(\d+)"/g),m=>{const e=new Element('button');e.dataset.tab=m[1];return e;});
assert.deepStrictEqual(tabs.map(e=>e.dataset.tab),['1','2','3','4']);
assert(!html.includes('每日推荐'));
assert.strictEqual(new URL(html.match(/href="([^"]+)"[^>]*>回到主页/)[1],'http://192.168.0.226/qqmusic/').href,'http://192.168.0.226/main');
const modes=['sequence','random','single'].map(mode=>{const e=new Element('button');e.dataset.mode=mode;return e;});
const login=['qq','wx'].map(mode=>{const e=new Element('button');e.dataset.login=mode;return e;});
const document={getElementById:id=>elements[id],createElement:t=>new Element(t),createTextNode:t=>({textContent:t}),hidden:false,
 querySelectorAll:q=>q==='[data-tab]'?tabs:q==='[data-mode]'?modes:q==='[data-login]'?login:[]};
const sandbox={document,window:{addEventListener(){}},URL,AbortController,console,setTimeout:()=>1,clearTimeout(){},fetch:()=>new Promise(()=>{})};
vm.createContext(sandbox);vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],sandbox);
const base={ready:true,logged_in:false,page:'songs',tab:1,revision:1,status:'idle',message:'',error:'',song:{},list:{cursor:1,items:[{index:1,name:'甲'},{index:2,name:'乙'}]}};
sandbox.fixture=base;vm.runInContext('render(fixture)',sandbox);
assert(tabs.slice(2).every(x=>x.hidden),'guest-only columns');
const rows=elements.list.children;elements.list.scrollTop=117;
sandbox.fixture={...base,page:'player',status:'playing',song:{id:'a',name:'甲'}};vm.runInContext('render(fixture)',sandbox);
assert.strictEqual(elements.list.children,rows,'playing must retain DOM rows');assert.strictEqual(elements.list.scrollTop,117,'playing retains scroll');
sandbox.fixture={...base,logged_in:true,account:{name:'测试账户',login_type:1,membership:{name:'超级会员',active:true}},page:'player'};vm.runInContext('render(fixture)',sandbox);
assert(tabs.every(x=>!x.hidden),'login automatically reveals account columns');assert(elements.connection.textContent.includes('测试账户'));
assert(elements['account-membership'].textContent.includes('超级会员'));
sandbox.fixture={...base,logged_in:true,tab:4};vm.runInContext('render(fixture)',sandbox);
assert(elements['list-title'].textContent.includes('最近播放'));
assert(elements['list-title'].textContent.includes('本机'));
sandbox.fixture={...base,page:'login',login_mode:'wx',login_status:'waiting',login_revision:4};vm.runInContext('render(fixture)',sandbox);
assert(elements['qr-instruction'].textContent.includes('微信'));assert(elements.confirm.textContent.includes('跳过'));
assert.strictEqual(elements['qr-panel'].hidden,false);
console.log('Web regression checks passed: list retention, scroll, login transition, account, guest columns, QR mode.');
