const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'../../package/control.html'),'utf8');
const script=html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1];new vm.Script(script);
class Element{
 constructor(){this.handlers={};this.attrs={};this.dataset={};this.open=false;}
 addEventListener(k,f){this.handlers[k]=f;}
 setAttribute(k,v){this.attrs[k]=v;}
 showModal(){this.open=true;}
 close(){this.open=false;}
 getBoundingClientRect(){return {left:10,right:100,top:10,bottom:100};}
}
const elements={};for(const id of ['account-button','refresh-library','account-name','account-id','account-vip','account-dialog','account-close','account-error','logout','library-cache-note'])elements[id]=new Element();
const buttons=['shuffle','ordered','repeat_one'].map(mode=>{const b=new Element();b.dataset.mode=mode;return b;});
const sent=[];
const context=vm.createContext({$:id=>elements[id],document:{querySelectorAll:()=>buttons},
 buttonTask:(_,f)=>f(),command:async(action,args)=>sent.push({action,...args})});
const render=script.slice(script.indexOf('function renderSession(s){'),script.indexOf('function renderLibrary(s){'));
const events=script.slice(script.indexOf("document.querySelectorAll('[data-mode]')"),script.indexOf("$('volume').addEventListener('input'"));
vm.runInContext("var state=null;const libraryNames=['','收藏','最近播放','每日推荐'];"+render+events,context);
const s={ready:true,logged_in:true,play_mode:'repeat_one',account:{id:'98765432109',nickname:'<test>',membership_label:'非会员'},list:{tab:2},libraries:[{complete:true},{ready:true,loaded:20,total:50},{}]};
context.state=s;context.renderSession(s);
assert.equal(elements['account-button'].textContent,'登录账户 · <test>');
assert.equal(elements['account-name'].textContent,'<test>');assert.equal(elements['account-vip'].textContent,'非会员');
assert.equal(buttons[2].attrs['aria-pressed'],'true');assert.equal(buttons[0].attrs['aria-pressed'],'false');
assert.match(elements['library-cache-note'].textContent,/20\/50/);
elements['account-button'].handlers.click();assert.equal(elements['account-dialog'].open,true);
elements['account-close'].handlers.click();assert.equal(elements['account-dialog'].open,false);
buttons[0].handlers.click();assert.equal(sent.pop().mode,'shuffle');
elements['refresh-library'].handlers.click();assert.deepEqual(sent.pop(),{action:'refresh_library',tab:2});
elements['account-dialog'].open=true;context.renderSession({ready:true,logged_in:false});
assert.equal(elements['account-dialog'].open,false);assert.equal(elements['account-button'].disabled,true);
assert.equal(elements['account-name'].textContent,'—');
elements.logout.handlers.click().then(()=>{assert.equal(sent.pop().action,'logout');console.log('Account dialog, mode buttons and refresh control tests OK');});
