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
    installModels:async()=>{if(fixture.fail)throw Error('network');fixture.installed=true;},onModelProgress:()=>{},onDelta:()=>{},onUpdate:()=>{},onUpdateStatus:()=>{},updateStatus:async()=>({phase:'idle',version:'test'}),onEndListening:()=>{},onTogglePause:()=>{},onSpeechError:()=>{},
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
 await page.click('#settings');await page.waitForSelector('#dialog[open]');await page.click('#close');
 assert.deepEqual(errors,[]);console.log('PASS: empty library, missing models before microphone, retry, ready without recording, permission denial, contextual document setup, dismissal, delete/restore, settings, dark and compact layouts.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
