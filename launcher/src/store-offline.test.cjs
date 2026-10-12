const assert = require("node:assert/strict");
const {createStore,deferred,response,flush} = require("./store-test-harness.cjs");
const system = {installed_apps:[
  {id:"local-game",name:"Local Game",source:"sd",version:"1"},
  {id:"local-tool",name:"Local Tool",source:"sd",version:"1"}
]};
const catalog = {items:[
  {app_id:"local-game",name:"Cloud Game",catalog_scope:"community",version:"2",manifest_url:"https://store/game/manifest",description_page_url:"https://store/game/info"},
  {app_id:"remote-only",name:"Remote",catalog_scope:"official",version:"1",manifest_url:"https://store/remote/manifest"}
]};
function metadata(url){return response(url.includes("local-tool")?"author = Bob\ncatalog_scope = official\ncategory = tool":"author = Alice\nname_zh_cn = 本地游戏\ncategory = game");}

async function main(){
  const {context:c,node,timers} = createStore();
  const slowCloud = deferred();
  c.fetch = async (url)=>url==="/api/system/state"?response(system):url.startsWith("/api/system/apps/catalog")?slowCloud.promise:metadata(url);
  const loading = c.loadCatalog(true);
  await flush();
  assert.equal(c.state.loading,true);
  assert.equal(c.state.deviceStatus,"online");
  assert.equal(c.state.cloudStatus,"loading");
  assert.equal(c.visibleApps().length,2,"local apps must appear before cloud resolves, across both scopes");
  assert.match(node("appGrid").innerHTML,/本地游戏/);
  assert.match(node("storeStatusNote").textContent,/本地应用/);
  slowCloud.reject(new Error("server unavailable"));
  await loading;
  assert.equal(c.state.cloudStatus,"offline");
  assert.equal(c.visibleApps().length,2);
  assert.equal(node("refreshPreviewBtn").disabled,false);
  assert.match(node("storeStatusNote").textContent,/商店暂时无法连接/);
  assert.equal(c.actionState(c.state.apps[0]).disabled,true);
  assert.doesNotMatch(c.cardMarkup(c.state.apps[0]),/data-action="uninstall"[^>]*disabled/);
  c.openDetail(c.state.apps.find((app)=>app.id==="local-game"));
  assert.equal(node("dialogOpenLink").hidden,true);
  assert.match(node("dialogInfoFrame").srcdoc,/本地游戏/);
  c.fetch = async (url)=>url==="/api/system/state"?response(system):url.startsWith("/api/system/apps/catalog")?response(catalog):metadata(url);
  await c.loadCatalog(true);
  await flush();
  assert.equal(c.state.cloudStatus,"online");
  assert.equal(node("storeStatusNote").hidden,true);
  const game = c.state.apps.find((app)=>app.id==="local-game");
  assert.equal(c.actionState(game).label,"更新");
  assert.equal(c.actionState(game).disabled,false);
  node("showInstalledBtn").listeners.click();
  assert.equal(c.visibleApps().length,2);
  c.state.query = "alice";
  assert.equal(c.visibleApps().length,1);
  c.state.query = "";
  c.state.filter = "game";
  c.state.cloudStatus = "offline";
  c.updateNormalizedApps();
  assert.equal(c.visibleApps().length,1,"offline metadata supports category filtering");
  c.state.filter = "all";
  c.fetch = async ()=>{throw new Error("device unreachable");};
  await c.loadCatalog(true);
  assert.equal(c.visibleApps().length,2);
  assert.match(node("storeStatusNote").textContent,/无法连接设备/);
  assert.equal(c.state.apps.find((app)=>app.id==="local-game").publisher,"Alice","failed refresh must retain last metadata");
  assert.equal(c.actionState(c.state.apps[0]).disabled,true);
  assert.match(c.cardMarkup(c.state.apps[0]),/data-action="uninstall"[^>]*disabled/);
  let mutations = 0;
  c.fetch = async ()=>{mutations++;return response({});};
  await c.installApp(game);
  await c.uninstallApp(c.state.apps[0]);
  assert.equal(mutations,0);

  const {context:first,node:firstNode} = createStore();
  first.fetch = async (url)=>{
    if(url==="/api/system/state"){throw new Error("device failure");}
    return response(catalog);
  };
  await first.loadCatalog(true);
  assert.equal(first.state.deviceStatus,"offline");
  assert.match(firstNode("storeConnectionChip").textContent,/无法连接设备/);
  assert.equal(first.actionState(first.state.apps[0]).disabled,true);

  // The opposite completion order also works: cloud fails before the device answers.
  const {context:lateDevice} = createStore();
  const deviceReply = deferred();
  lateDevice.fetch = async (url)=>{
    if(url==="/api/system/state"){return deviceReply.promise;}
    if(url.startsWith("/api/system/apps/catalog")){throw new Error("cloud failure");}
    return metadata(url);
  };
  const lateLoad = lateDevice.loadCatalog(true);
  await flush();
  assert.equal(lateDevice.state.cloudStatus,"offline");
  deviceReply.resolve(response(system));
  await lateLoad;
  await flush();
  assert.equal(lateDevice.visibleApps().length,2);
  let deleted = "";
  lateDevice.fetch = async (url,init)=>{
    if(init && init.method==="DELETE"){deleted=url;return response({ok:true});}
    if(url==="/api/system/state"){return response({installed_apps:[system.installed_apps[1]]});}
    return metadata(url);
  };
  await lateDevice.uninstallApp(lateDevice.state.apps.find((app)=>app.id==="local-game"));
  assert.equal(deleted,"/api/system/apps?id=local-game");
  assert.equal(lateDevice.visibleApps().length,1,"local uninstall must work without cloud");

  const {context:timeout,node:timeoutNode,timers:timeoutTimers} = createStore();
  timeout.fetch = async (url,init)=>{
    if(url==="/api/system/state"){return response(system);}
    if(url.startsWith("/api/system/fs/file")){return metadata(url);}
    return new Promise((resolve,reject)=>init.signal.addEventListener("abort",()=>reject(new Error("timeout"))));
  };
  const timedLoad = timeout.loadCatalog(true);
  await flush();
  assert.equal(timeout.visibleApps().length,2);
  const timer = [...timeoutTimers.values()].find((item)=>item.ms===15000);
  assert.ok(timer);
  timer.callback();
  await timedLoad;
  assert.equal(timeout.state.cloudStatus,"offline");
  assert.equal(timeoutNode("refreshPreviewBtn").disabled,false);
  const oldState = deferred();
  timeout.fetch = ()=>oldState.promise;
  const oldRequest = timeout.loadDeviceState(false);
  timeout.fetch = async ()=>response({installed_apps:[]});
  await timeout.loadDeviceState(false);
  oldState.resolve(response(system));
  await oldRequest;
  assert.equal(timeout.state.system.installed_apps.length,0);
  timeout.fetch = async (url)=>response(url==="/api/system/state"?{installed_apps:[]}:{});
  await timeout.loadCatalog(true);
  assert.equal(timeout.state.cloudStatus,"offline");
  assert.equal(timeoutNode("emptyState strong").textContent,"暂无已安装应用");
  for(const language of ["zh-CN","en","ja","zh-TW"]){
    const {context:localized,node:localizedNode} = createStore(language);
    localized.state.deviceStatus = "online";
    localized.state.cloudStatus = "offline";
    localized.render();
    assert.notEqual(localizedNode("storeStatusNote").textContent,"cloudOfflineNote");
    assert.ok(localizedNode("storeStatusNote").textContent);
  }
  assert.ok(![...timers.values()].some((item)=>item.ms===6000 || item.ms===15000));
  console.log("PASS: independent loading, cloud failure, local metadata, retry, cross-scope view, device guards, timeout, stale responses, malformed catalog, four locales");
}
main().catch((err)=>{console.error(err);process.exitCode=1;});
