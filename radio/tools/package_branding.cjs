// Mechanical asset export only: keep generated artwork, resize for the launcher,
// and inline the small PNG so info.html also works in store srcdoc previews.
const fs=require('node:fs');const path=require('node:path');
const sharp=require(process.env.RADIO_SHARP_MODULE||'sharp');
const root=path.resolve(__dirname,'..');
async function main(){
  const source=process.argv[2];if(!source)throw Error('Usage: node package_branding.cjs generated.png');
  const metadata=await sharp(source).metadata();
  if(!metadata.hasAlpha)throw Error('Expected the selected transparent PNG');
  const archive=path.join(root,'src/assets/radio-logo-transparent-original.png');
  if(!fs.existsSync(archive))fs.copyFileSync(source,archive);
  const target=path.join(root,'package/main.png');
  const backup=path.join(root,'src/assets/radio-logo-black-128.png');
  if(fs.existsSync(target)&&!fs.existsSync(backup))fs.copyFileSync(target,backup);
  // Replacement is user-requested. Preserve alpha; never flatten to black.
  await sharp(source).resize(128,128,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).png().toFile(target);
  const data='data:image/png;base64,'+fs.readFileSync(target).toString('base64');
  const html=fs.readFileSync(path.join(root,'src/web/info.template.html'),'utf8').replace('__RADIO_ICON_DATA__',data);
  fs.writeFileSync(path.join(root,'package/info.html'),html);
  const stats=await sharp(target).stats();
  if(stats.channels.length!==4||stats.channels[3].min!==0)throw Error('Transparent export verification failed');
  console.log('Exported transparent 128x128 main.png and self-contained info.html');
}
main().catch(e=>{console.error(e);process.exitCode=1});
