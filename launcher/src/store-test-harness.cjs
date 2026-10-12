const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const html = fs.readFileSync(path.join(__dirname,"../package/store-preview.html"),"utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(script);

function createStore(language="zh-CN"){
  const nodes = new Map();
  function node(id){
    if(!nodes.has(id)){
      const classes = new Set();
      nodes.set(id,{
        style:{},dataset:{},attributes:{},listeners:{},textContent:"",innerHTML:"",hidden:false,
        classList:{add:(x)=>classes.add(x),remove:(x)=>classes.delete(x),contains:(x)=>classes.has(x),toggle:(x,on)=>on?classes.add(x):classes.delete(x)},
        querySelector:(selector)=>node(id+" "+selector),
        setAttribute(name,value){this.attributes[name]=value;},
        removeAttribute(name){delete this.attributes[name];},
        addEventListener(name,callback){this.listeners[name]=callback;},scrollIntoView(){}
      });
    }
    return nodes.get(id);
  }
  const timers = new Map();
  let timerId = 0;
  const storage = new Map();
  const context = vm.createContext({
    console,URL,URLSearchParams,AbortController,
    fetch:async()=>{throw new Error("Unexpected fetch");},
    document:{documentElement:{},getElementById:node,querySelector:node,querySelectorAll:()=>[]},
    localStorage:{getItem:(k)=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:(k)=>storage.delete(k)},
    window:{location:{search:"?lang="+language,href:"http://device/apps/launcher/store-preview.html"},
      setTimeout:(callback,ms)=>{timers.set(++timerId,{callback,ms});return timerId;},
      clearTimeout:(id)=>timers.delete(id),addEventListener(){},confirm:()=>true}
  });
  // Execute the real page and event bindings; tests control when loading starts.
  assert.equal(script.split("    loadCatalog(true);").length,2);
  vm.runInContext(script.replace("    loadCatalog(true);",""),context);
  context.state = vm.runInContext("state",context);
  return {context,node,timers};
}
function deferred(){
  let resolve,reject;
  const promise = new Promise((yes,no)=>{resolve=yes;reject=no;});
  return {promise,resolve,reject};
}
function response(data,ok=true){return {ok,status:ok?200:503,text:async()=>typeof data==="string"?data:JSON.stringify(data)};}
async function flush(){for(let i=0;i<20;i++){await Promise.resolve();}}
module.exports = {createStore,deferred,response,flush};
