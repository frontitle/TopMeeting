const test=require('node:test');
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const {desktopUpdates,newestRelease}=require('../src/updates.cjs');

const installer='TopMeeting-0.16.0-windows-x64-setup.exe';
const release={tag_name:'windows-v0.16.0-preview.1',assets:[{name:installer},{name:'latest.yml'}]};
test('only complete newer Windows preview installers are eligible',()=>{
  for(const candidate of [{...release,draft:true},{...release,assets:[]},{...release,tag_name:'macos-v0.16.0'}])
    assert.equal(newestRelease([candidate],'0.15.0'),undefined);
  assert.equal(newestRelease([release],'0.17.0'),undefined);
  assert.equal(newestRelease([release],'0.15.0').installer,installer);
});
test('update download and restart require separate actions and an idle saved meeting',async t=>{
  t.mock.method(global,'fetch',async()=>Response.json([release]));
  let idle=false,installs=0,downloads=0;
  const updater=Object.assign(new EventEmitter(),{
    setFeedURL(){},checkForUpdates:async()=>({isUpdateAvailable:true,updateInfo:{version:'0.16.0',files:[{url:installer,sha512:'fixture'}]}}),
    downloadUpdate:async()=>{downloads++;},quitAndInstall(){installs++;}
  });
  const updates=desktopUpdates({version:'0.15.0',updater,notify(){},prepareInstall:async()=>idle,releaseInstall(){}});
  assert.equal((await updates.perform()).phase,'available');assert.equal(downloads,0);
  assert.equal((await updates.perform()).phase,'ready');
  assert.equal((await updates.perform()).phase,'ready');assert.equal(installs,0);
  idle=true;await updates.perform();await updates.perform();
  assert.equal(downloads,1);assert.equal(installs,1);assert.equal(updater.autoInstallOnAppQuit,false);
});
