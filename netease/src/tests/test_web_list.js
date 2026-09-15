const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'../../package/control.html'),'utf8');
const script=html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1];
new vm.Script(script);
const code=script.slice(script.indexOf('function renderLibrary(s){'),script.indexOf('function render(s){'));
class Element {
  constructor(){this.children=[];this.scrollTop=0;this.handlers={};this.className='';this.textContent='';}
  append(...children){this.children.push(...children);}
  replaceChildren(...children){this.children=children;}
  addEventListener(name,fn){this.handlers[name]=fn;}
}
const elements={list:new Element(),'list-title':new Element()};
const sent=[];
const context=vm.createContext({document:{querySelectorAll:()=>[],createElement:()=>new Element()},
  $:id=>elements[id],buttonTask:(_button,fn)=>fn(),command:(action,args)=>sent.push({action,...args})});
vm.runInContext("let listKey='',listRevision=null;const libraryNames=['','收藏','最近播放','每日推荐'];const libraryNotes=['','','',''];"+code,context);
const s={page:'songs',tab:3,revision:1,logged_in:true,list:{revision:7,tab:3,ready:true,
  items:[{index:1,name:'first'},{index:2,name:'second'},{index:3,name:'next',page:true}]}};
context.renderLibrary(s);
assert.equal(elements.list.children.length,3);
elements.list.scrollTop=121;
const first=elements.list.children[0];
s.page='player';s.revision=2;s.message='获取播放地址…';context.renderLibrary(s);
assert.equal(elements.list.children[0],first);
assert.equal(elements.list.scrollTop,121);
s.list.items[0].current=true;context.renderLibrary(s);
assert.equal(elements.list.children[0].className,'row current');
assert.equal(elements.list.scrollTop,121);
elements.list.children[1].handlers.click();
assert.deepEqual(sent.pop(),{action:'select',index:2,list_revision:7});
elements.list.children[2].handlers.click();
assert.deepEqual(sent.pop(),{action:'select',index:3,list_revision:7});
s.page='about';s.tab=1;context.renderLibrary(s);
assert.match(elements['list-title'].textContent,/每日推荐/);
assert.equal(elements.list.children.length,3);
s.list={revision:8,tab:1,ready:false,loading:true,items:[]};context.renderLibrary(s);
assert.equal(elements.list.children[0].textContent,'正在加载歌曲…');
assert.equal(elements.list.scrollTop,0);
s.list.loading=false;s.list.error=true;context.renderLibrary(s);
assert.match(elements.list.children[0].textContent,/加载失败/);
s.list.error=false;s.list.ready=true;context.renderLibrary(s);
assert.equal(elements.list.children[0].textContent,'暂无歌曲');
console.log('Web list retention, repeat selection, pagination, revision and scroll tests OK');
