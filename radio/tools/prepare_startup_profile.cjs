// Instrument copies only. The normal package remains untouched.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),folder=path.resolve(process.argv[2]);
const originals=path.join(folder,'originals'),instrumented=path.join(folder,'instrumented');
fs.mkdirSync(originals,{recursive:true});fs.mkdirSync(instrumented,{recursive:true});
for(const name of ['main.lua','radio.lua','storage.lua','ui.lua']){
  const source=fs.readFileSync(path.join(root,'package',name),'utf8');
  fs.writeFileSync(path.join(originals,name),source,{flag:'wx'});
  let edited=source.replace(/\r\n/g,'\n');
  if(name==='main.lua')edited="_G.RADIO_PROFILE=dofile('/sd/apps/radio/startup_profile.lua')\n"+source+"\nRADIO_PROFILE.mark('entry.return',0);RADIO_PROFILE.flush()\n";
  if(name==='radio.lua'){
    edited=edited.replace("local DIR='/sd/apps/radio'","local RP=RADIO_PROFILE\nlocal DIR='/sd/apps/radio'");
    edited=edited.replace("A.ui=dofile(DIR..'/ui.lua')(A)","local ui_started=RP.now()\nA.ui=dofile(DIR..'/ui.lua')(A)\nRP.mark('ui.create',ui_started);RP.mark('ui.ready',0)");
    edited=edited.replace("A.net.poll()","RP.once('first.tick');A.net.poll()");
    edited=edited.replace("local network=A.net.state()","local network=A.net.state()\n  if (network.started or 0)>0 then RP.once('http.started') end\n  if (network.received_bytes or 0)>0 then RP.once('http.first_data','bytes='..network.received_bytes) end");
    edited=edited.replace("A.stats=A.audio.state()\n    if A.ack", "A.stats=A.audio.state()\n    if (A.stats.decoded_frames or 0)>0 then RP.once('audio.first_decoded') end\n    if (A.stats.written_bytes or 0)>0 then RP.once('audio.first_pcm_written','bytes='..A.stats.written_bytes) end\n    if A.stats.status==2 then RP.once('audio.playing') end\n    if A.ack");
    edited=edited.replace("A.ui.update()\nend)","A.ui.update();RP.flush()\nend)");
  }
  if(name==='storage.lua'){
    edited=edited.replace("if not decoded or not valid(kind,doc) then", "local validation_started=RADIO_PROFILE.now()\n    local validation_ok=decoded and valid(kind,doc)\n    RADIO_PROFILE.mark('storage.validate',validation_started,kind)\n    if not validation_ok then");
  }
  fs.writeFileSync(path.join(instrumented,name),edited);
}
fs.copyFileSync(path.join(__dirname,'startup_profile.lua'),path.join(instrumented,'startup_profile.lua'));
console.log(folder);
