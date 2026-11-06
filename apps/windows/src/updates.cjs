const semver=require('semver');
const repository='frontitle/TopMeeting';

function newestRelease(releases,current){
  const candidates=[];
  for(const release of releases){
    const match=/^windows-v(\d+\.\d+\.\d+)-preview\.1$/.exec(release.tag_name);
    if(release.draft || !match || !semver.valid(match[1]) || !semver.gt(match[1],current))continue;
    const version=match[1];
    const installer='TopMeeting-'+version+'-windows-x64-setup.exe';
    if(![installer,'latest.yml'].every(name=>release.assets.some(asset=>asset.name===name)))continue;
    candidates.push({version,tag:release.tag_name,installer});
  }
  return candidates.sort((a,b)=>semver.rcompare(a.version,b.version))[0];
}

function desktopUpdates({version,updater,notify,prepareInstall,releaseInstall}){
  updater.autoDownload=false;
  updater.autoInstallOnAppQuit=false;
  updater.disableDifferentialDownload=true;
  let status={phase:'idle',version}, working=false;
  function set(phase,details={}){status={...status,...details,phase};notify(status);}
  updater.on('error',()=>{releaseInstall();set('failed');});
  updater.on('download-progress',progress=>set('downloading',{percent:Math.floor(progress.percent)}));
  async function perform(){
    if(working || status.phase==='installing')return status;
    working=true;
    try{
      if(status.phase==='ready'){
        if(!await prepareInstall())return status;
        set('installing');
        updater.quitAndInstall(false,true);
      }else if(status.phase==='available'){
        set('downloading',{percent:0});
        await updater.downloadUpdate();
        set('ready');
      }else{
        set('checking');
        const response=await fetch('https://api.github.com/repos/'+repository+'/releases?per_page=100',
          {headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(20000)});
        if(!response.ok)throw Error('Release lookup failed');
        const next=newestRelease(await response.json(),version);
        if(!next){set('current');return status;}
        updater.setFeedURL({provider:'generic',url:'https://github.com/'+repository+'/releases/download/'+next.tag+'/'});
        const result=await updater.checkForUpdates();
        const file=result?.updateInfo.files?.find(f=>f.url===next.installer);
        if(!result?.isUpdateAvailable || result.updateInfo.version!==next.version ||
           result.updateInfo.files.length!==1 || !file?.sha512)throw Error('Invalid installer metadata');
        set('available',{next:next.version});
      }
    }catch{releaseInstall();set('failed');}
    finally{working=false;}
    return status;
  }
  return {perform,status:()=>status};
}
module.exports={desktopUpdates,newestRelease};
