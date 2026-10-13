// Convert the supplied numbered favorites file without dropping or deduplicating entries.
const fs=require('node:fs');const path=require('node:path');
const [source,destination]=process.argv.slice(2);
if(!source||!destination)throw Error('Usage: node convert_favorites.cjs favorites.txt stations.json');
if(fs.existsSync(destination))throw Error('Output exists; choose a new destination');
const text=new TextDecoder('utf-8',{fatal:true}).decode(fs.readFileSync(source));
const ids=new Set();const urls=new Set();const names=new Set();let duplicateUrls=0,duplicateNames=0;
const stations=text.split(/\r?\n/).filter(line=>line.trim()).map((line,index)=>{
  const m=line.match(/^\s*(\d+)\s*[.、．]\s*(.+?)\s*[（(]\s*(https?:\/\/.+?)\s*[）)]\s*$/);
  if(!m)throw Error(`Unrecognized line ${index+1}`);
  const id=Number(m[1]),name=m[2].trim(),url=m[3].trim();
  if(!Number.isSafeInteger(id)||id<1||ids.has(id))throw Error(`Invalid/duplicate ID on line ${index+1}`);
  if(/[\s\x00-\x1f\x7f]/.test(url))throw Error(`Whitespace/control character in URL on line ${index+1}`);
  const parsed=new URL(url);if(!['http:','https:'].includes(parsed.protocol)||!parsed.hostname)throw Error(`Invalid URL on line ${index+1}`);
  const suffix=parsed.pathname.toLowerCase();
  const codec=suffix.endsWith('.m3u8')?'hls':suffix.endsWith('.mp3')?'mp3':suffix.endsWith('.aac')?'aac':suffix.endsWith('.flac')?'flac':'auto';
  ids.add(id);if(urls.has(url))duplicateUrls++;if(names.has(name))duplicateNames++;
  urls.add(url);names.add(name);
  return {id,name,url,codec};
});
if(stations.length<1||stations.length>2000)throw Error('Catalog exceeds App limits');
fs.mkdirSync(path.dirname(path.resolve(destination)),{recursive:true});
// Keep compact: the device's bounded JSON allocator doubles its initial
// capacity and can skip the final allowed capacity for larger pretty JSON.
const encoded=JSON.stringify({stations})+'\n';
fs.writeFileSync(destination,encoded,{encoding:'utf8',flag:'wx'});
const verified=JSON.parse(fs.readFileSync(destination,'utf8'));
if(JSON.stringify(verified.stations)!==JSON.stringify(stations))throw Error('Local JSON verification failed');
console.log(JSON.stringify({count:stations.length,bytes:Buffer.byteLength(encoded),duplicateUrls,duplicateNames,formats:stations.reduce((a,s)=>(a[s.codec]=(a[s.codec]||0)+1,a),{}),output:path.resolve(destination)},null,2));
