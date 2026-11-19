const {chromium}=require('playwright-core');
const path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try {
 const page=await browser.newPage({viewport:{width:1380,height:880},colorScheme:'light'});
 const root=path.resolve(__dirname,'../../..');
 const output=path.join(root,'reports/ui/0.14');require('node:fs').mkdirSync(output,{recursive:true});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.fixture={meetings:[],config:{},accounts:['feishu','google','notion','ding','tencent'].map(id=>({id,name:id})),installed:false,fail:true,mic:0};
  navigator.mediaDevices.getUserMedia=async()=>{fixture.mic++;throw Object.assign(new Error('denied'),{name:'NotAllowedError'});};
  function create(){const m={id:crypto.randomUUID(),title:'产品会议',date:new Date().toISOString(),lines:[],notes:'',recordings:[],duration:0};fixture.meetings.unshift(m);return m;}
  window.api={load:async()=>structuredClone(fixture),create:async()=>create(),checkModels:async()=>fixture.installed,
    installModels:async()=>{if(fixture.fail)throw Error('network');fixture.installed=true;},onModelProgress:()=>{},onDelta:()=>{},onUpdate:()=>{},onUpdateStatus:handler=>window.notifyUpdate=handler,
    updateStatus:async()=>({phase:'idle',version:'test',action:'check'}),
    updateAction:async action=>{fixture.lastUpdateAction=action;return {phase:'ready',version:'test',action:'install'};},onEndListening:()=>{},onTogglePause:()=>{},onSpeechError:()=>{},
    trash:async(id,val)=>fixture.meetings.find(m=>m.id===id).deletedAt=val,edit:async(id,patch)=>Object.assign(fixture.meetings.find(m=>m.id===id),patch)};
 });
 await page.goto(require('node:url').pathToFileURL(path.join(root,'apps/windows/src/index.html')).href);
 await page.waitForSelector('#welcome:visible');await page.click('#create');await page.click('#record');
 await page.waitForSelector('#prepare:visible');assert.equal(await page.evaluate(()=>fixture.mic),0);
 await page.screenshot({path:path.join(output,'first-recording.png')});
 await page.click('#prepareAction');await page.waitForFunction(()=>document.querySelector('#prepareAction').textContent==='重试下载');
 await page.evaluate(()=>fixture.fail=false);await page.click('#prepareAction');await page.waitForFunction(()=>document.querySelector('#prepareTitle').textContent==='本地模型已就绪');
 assert.equal(await page.evaluate(()=>fixture.mic),0);
 await page.click('#prepareAction');await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('允许麦克风'));
 await page.evaluate(async()=>{
  notice('');const m=fixture.meetings[0];m.title='产品体验复盘';m.duration=1080;m.recordings=['fixture'];m.speakers=[{id:'a',name:'林悦'}];
  m.lines=[{id:'1',speaker:'林悦',text:'先看第一次开会的体验。点下录音时就应该知道下一步要做什么。'},{id:'2',speaker:'陈晨',text:'文档可以在会议结束后提示一次，下次需要时再绑定。'}];
  m.notes='## 核心摘要\n首次使用时，在需要操作的位置说明下一步。\n\n## 决策\n模型准备完成后由用户开始录音。';await reload();
 });
 await page.waitForSelector('#docHint:visible');await page.click('#connectDocs');await page.waitForSelector('#accountDialog[open]');await page.selectOption('#service','notion');assert.equal(await page.locator('#accountFields input').count(),2);await page.click('#closeAccounts');
 await page.screenshot({path:path.join(output,'workspace-light.png')});
 await page.emulateMedia({colorScheme:'dark'});await page.setViewportSize({width:1000,height:680});await page.evaluate(()=>new Promise(done=>requestAnimationFrame(()=>requestAnimationFrame(done))));await page.screenshot({animations:'disabled',path:path.join(output,'workspace-dark.png')});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 await page.click('#hideDocHint');await page.evaluate(()=>reload());assert.equal(await page.locator('#docHint').isVisible(),false);
 await page.click('#delete');await page.check('#trash');await page.click('#delete');await page.uncheck('#trash');await page.waitForFunction(()=>document.querySelector('#title').value==='产品体验复盘');
 await page.click('#settings');await page.waitForSelector('#dialog[open]');
 await page.waitForFunction(()=>!document.querySelector('#updateAction').disabled);
 await page.evaluate(()=>notifyUpdate({phase:'downloadFailed',version:'test',next:'0.16.0',action:'download'}));
 await page.getByRole('button',{name:'重试下载'}).click();
 assert.equal(await page.evaluate(()=>fixture.lastUpdateAction),'download');
 await page.getByRole('button',{name:'安装并重启'}).waitFor();
 await page.click('#close');
 await page.evaluate(async()=>{
  const audio=new AudioContext(), oscillator=audio.createOscillator(), destination=audio.createMediaStreamDestination();
  oscillator.connect(destination);oscillator.start();await audio.resume();
  navigator.mediaDevices.getUserMedia=async()=>destination.stream.clone();
  fixture.chunks=0;fixture.stops=0;
  api.start=async()=>{fixture.chunks=0;};api.overlay=async()=>{};
  api.chunk=async bytes=>{if(bytes.length)fixture.chunks++;};
  api.stop=async duration=>{if(!fixture.chunks || duration<=0)throw Error('Audio was not flushed before stop');fixture.stops++;};
  await begin(false);
  if(!$('trash').disabled || !recorder)throw Error('Recording library can switch mid-capture');
  await new Promise(done=>setTimeout(done,350));
  // A device failure also dispatches a stop event without a click in the app.
  recorder.stop();
  await new Promise((resolve,reject)=>{
    const deadline=Date.now()+5000;
    const interval=setInterval(()=>{
      if(!recorder && !busy && $('notice').textContent.includes('中断')){clearInterval(interval);resolve();}
      else if(Date.now()>deadline){clearInterval(interval);reject(Error('Unexpected stop left a session open'));}
    },25);
  });
  if(fixture.stops!==1 || !$('notice').textContent.includes('中断'))throw Error('Interrupted capture was not saved');
  await begin(false);await new Promise(done=>setTimeout(done,350));await togglePause();await finish();
  if(fixture.stops!==2 || $('trash').disabled)throw Error('Next recording did not finish');
  await begin(false);await new Promise(done=>setTimeout(done,350));
  // Simulate an unavailable worklet port, while the real MediaRecorder still holds its final chunk.
  source={disconnect(){}};
  context={state:'running',async close(){}};
  node={disconnect(){},port:{postMessage(){
    if(recorder.state!=='inactive')throw Error('Recorder still running during speech drain');
    throw Error('Closed worklet port');
  }}};
  await action(finish);
  if(fixture.stops!==3 || !$('notice').textContent.includes('Closed worklet port'))throw Error('Speech drain failure lost audio');
  await begin(false);
  await new Promise(done=>setTimeout(done,350));
  let receivedOffset=-1, attempts=0, stopCalls=0;
  api.chunk=async (bytes,offset)=>{
    if(receivedOffset===-1)receivedOffset=offset;
    if(receivedOffset!==offset)throw Error('Retry changed the offset');
    if(++attempts<=2)throw Error('Disk full');
  };
  api.stop=async()=>{if(++stopCalls===1)throw Error('Metadata write failed');};
  await action(finish);
  if($('record').textContent!=='重试保存' || !recorder || recorder.state!=='inactive' || stopCalls)throw Error('Unsaved audio was discarded');
  await $('record').onclick();
  if(!recorder || stopCalls!==1 || !$('notice').textContent.includes('Metadata write failed'))throw Error('Metadata retry lost');
  await $('record').onclick();
  if(recorder || attempts!==3 || stopCalls!==2)throw Error('Retry duplicated the audio or did not commit');
  await begin(false);
  await new Promise(done=>setTimeout(done,350));
  api.chunk=async()=>{};api.stop=async()=>'本地语音引擎响应超时';
  await action(finish);
  if(recorder || !$('notice').textContent.includes('录音已保存，部分字幕可能缺失'))throw Error('Speech timeout hid the audio save outcome');
  const sample = new MediaRecorder(destination.stream,{mimeType:'audio/webm;codecs=opus'});
  const sampleData = new Promise(resolve=>{sample.ondataavailable=event=>resolve(event.data);});
  sample.start();
  await new Promise(resolve=>setTimeout(resolve,1800));
  sample.stop();
  const bytes = new Uint8Array(await (await sampleData).arrayBuffer());
  const m = fixture.meetings.find(item=>item.id===selected);
  m.recordings = ['first.webm','resumed.webm'];
  m.lines = [{id:'passage',speaker:'示例',text:'短句',recording:'resumed.webm',recordingOffset:12,start:12.45,end:12.95}];
  api.audio = async(id,index)=>{if(id!==m.id || index!==1)throw Error('Wrong recording selected');return bytes;};
  await reload();
  await document.querySelector('.passage-time').onclick();
  const player = $('audio');
  if(player.hidden || $('recordings').value!=='1' || player.currentTime < 0.39)throw Error('Passage did not seek into resumed audio: '+player.currentTime);
  await new Promise(resolve=>setTimeout(resolve,850));
  if(!player.paused || player.currentTime < 0.89 || player.currentTime > 1.25)throw Error('Passage did not stop at the selected end: '+player.currentTime);
  await $('create').onclick();
  if(!player.hidden || player.hasAttribute('src'))throw Error('Playback survived a change of meeting');
  oscillator.stop();await audio.close();
 });
 assert.deepEqual(errors,[]);console.log('PASS: onboarding, library and settings, layouts, microphone interruption with final audio flush, and a subsequent paused recording.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
