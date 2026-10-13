const fs=require('node:fs'),path=require('node:path');
const folder=path.resolve(process.argv[2]);
const log=fs.readFileSync(path.join(folder,'serial.log'),'utf8');
const runs=[];let run;
for(const line of log.split(/\r?\n/)){
  const m=line.match(/\[RADIO_PROFILE\] (\S+) start_ms=([\d.]+) duration_ms=([\d.]+) end_ms=([\d.]+)\s*(.*)/);
  if(!m)continue;
  if(m[1]==='lua.entry'){run=[];runs.push(run)}
  if(run)run.push({name:m[1],start_ms:+m[2],duration_ms:+m[3],end_ms:+m[4],detail:m[5]});
}
const select=(r,name,detail='')=>r.find(e=>e.name===name&&e.detail.includes(detail));
const categories={
  station_file_read:r=>select(r,'file.read','/stations.json').duration_ms,
  station_json_decode:r=>select(r,'json.decode','bytes=116995').duration_ms,
  station_validation:r=>select(r,'storage.validate','stations').duration_ms,
  font13:r=>select(r,'font.load','ui13.bin').duration_ms,
  font24:r=>select(r,'font.load','ui24.bin').duration_ms,
  audio_module:r=>select(r,'module.require','radio.so').duration_ms,
  ui_controls_excluding_fonts_and_script:r=>select(r,'ui.create').duration_ms-select(r,'lua.dofile','ui.lua').duration_ms-select(r,'font.load','ui13.bin').duration_ms-select(r,'font.load','ui24.bin').duration_ms,
  ui_ready:r=>select(r,'ui.ready').end_ms
};
const stats=Object.fromEntries(Object.entries(categories).map(([k,fn])=>{
  const samples=runs.slice(0,3).map(fn);return [k,{samples_ms:samples,average_ms:samples.reduce((a,b)=>a+b,0)/samples.length,min_ms:Math.min(...samples),max_ms:Math.max(...samples)}];
}));
const result={baseline_runs:3,total_instrumented_runs:runs.length,stats,confirmation: runs[3],watchdog_warnings:(log.match(/Task watchdog got triggered/g)||[]).length};
fs.writeFileSync(path.join(folder,'timings.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(stats,null,2));console.log('Watchdog warnings in capture:',result.watchdog_warnings);
