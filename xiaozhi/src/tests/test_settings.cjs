// Execute the real page script against a small DOM double; no browser/network writes.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path');
const root=path.resolve(__dirname,'../../..');
for(const app of ['xiaozhi','xiaozhi-service']){
  const html=fs.readFileSync(path.join(root,app,'package/settings.html'),'utf8');
  assert.match(html,/<header>[\s\S]*<a class="home-button" id="backHome" href="\/" data-t="backHome">/);
  assert.equal(new URL('/', 'http://192.168.1.30/xiaozhi-service/').href,'http://192.168.1.30/');
  assert.equal(new URL('/', 'http://192.168.1.80:8080/xiaozhi/').href,'http://192.168.1.80:8080/');
  function element(){return {dataset:{},value:'',textContent:'',children:[],
    append(child){this.children.push(child)},replaceChildren(){this.children=[]},addEventListener(){}}}
  const elements=new Map();
  const get=id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id)};
  const home=get('#backHome');home.dataset.t='backHome';home.textContent='Back to home';
  const document={documentElement:{},hidden:false,querySelector:get,createElement:element,
    addEventListener(){},querySelectorAll(selector){
      if(selector==='[data-t]')return [home];
      if(selector==='option[data-style-id]')return [...elements.values()].flatMap(e=>e.children).filter(e=>e.dataset.styleId);
      return [];
    }};
  const context=vm.createContext({document,location:{pathname:'/xiaozhi-service/'},
    setTimeout(){},clearTimeout(){},setInterval(){throw Error('unexpected polling')},
    fetch(){throw Error('unexpected network')}});
  const js=html.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace('refresh();setInterval(refresh,3000);','');
  vm.runInContext(js,context);
  vm.runInContext("lang='zh-CN';options('#appStyle',['subtitle','wechat','custom-theme'],'wechat');options('#floatStyle',['window','subtitle','wechat','assistant'],'window');translate()",context);
  assert.deepEqual(get('#appStyle').children.map(e=>e.textContent),['字幕模式','聊天气泡','custom-theme']);
  assert.deepEqual(get('#appStyle').children.map(e=>e.value),['subtitle','wechat','custom-theme']);
  assert.equal(home.textContent,'返回主页');
  assert.deepEqual(get('#floatStyle').children.map(e=>e.textContent),['悬浮窗口','字幕模式','聊天气泡','角色助手']);
  assert.match(html,/<strong data-t="backgroundDetails">/);
  vm.runInContext("dirty.add('ui');lang='en';translate()",context);
  assert.deepEqual(get('#appStyle').children.map(e=>e.textContent),['Subtitles','Chat bubbles','custom-theme']);
  assert.equal(get('#appStyle').value,'wechat','translation must preserve unsaved selection');
  assert.equal(get('#floatStyle').value,'window');
  assert.equal(home.textContent,'Back to home');
  for(const [lang,label,back] of [['zh-TW','聊天氣泡','返回首頁'],['de','Chatblasen','Zur Startseite'],['ja','チャット吹き出し','ホームに戻る']]){
    vm.runInContext('lang='+JSON.stringify(lang)+';translate()',context);
    assert.equal(get('#appStyle').children[1].textContent,label);
    assert.equal(home.textContent,back);
    assert.equal(get('#appStyle').value,'wechat');
  }
  console.log(app+': localized style labels / stable IDs / live language changes / home URL PASS');
}
