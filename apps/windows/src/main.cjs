const {app,BrowserWindow,ipcMain,session,safeStorage,dialog}=require('electron');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const {LocalSpeech}=require('./local-speech.cjs');
const {listeningPanel}=require('./overlay.cjs');
const {DocumentStore}=require('./document-store.cjs');
const {endpoint,summaryInput,readSSE}=require('./domain.cjs');
const smoke=process.argv.includes('--smoke-test');
if(smoke && process.env.TOPMEETING_SMOKE_FIXTURE){
  app.commandLine.appendSwitch('use-fake-device-for-media-stream');
  app.commandLine.appendSwitch('use-fake-ui-for-media-stream');
  app.commandLine.appendSwitch('use-file-for-fake-audio-capture',process.env.TOPMEETING_SMOKE_FIXTURE);
}
if(smoke) app.setPath('userData',path.join(os.tmpdir(),'topmeeting-smoke-'+crypto.randomUUID()));
let speech,overlay,documents,root,win,active=null,meetings=[],config={},inFlight=new Set(),saveChain=Promise.resolve();
const ui=pathToFileURL(path.join(__dirname,'index.html')).href;
async function persist(){const data=JSON.stringify(meetings);saveChain=saveChain.then(async()=>{await fs.writeFile(path.join(root,'meetings.tmp'),data);await fs.rename(path.join(root,'meetings.tmp'),path.join(root,'meetings.json'));});await saveChain;}
function meeting(id){const m=meetings.find(m=>m.id===id);if(!m)throw new Error('会议不存在');return m;}
function bind(name,handler){ipcMain.handle(name,async(event,...args)=>{if(event.sender!==win.webContents || event.senderFrame!==win.webContents.mainFrame || event.senderFrame.url!==ui)throw new Error('Invalid caller');return handler(...args);});}
function publicConfig(){return {...config,token:undefined,asrToken:undefined,hasToken:!!config.token,hasASRToken:!!config.asrToken};}
const primaryInstance=app.requestSingleInstanceLock();
if(!primaryInstance) app.quit();
app.on('second-instance',()=>{
  if(win){if(win.isMinimized())win.restore();win.show();win.focus();}
});
if(primaryInstance) app.whenReady().then(async()=>{
 root=app.getPath('userData'); await fs.mkdir(root,{recursive:true});await fs.mkdir(path.join(root,'audio'),{recursive:true});
 try{meetings=JSON.parse(await fs.readFile(path.join(root,'meetings.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
 try{config=JSON.parse(safeStorage.decryptString(await fs.readFile(path.join(root,'credentials.bin'))));}catch(e){if(e.code!=='ENOENT')throw e;}
 session.defaultSession.setPermissionRequestHandler((contents,permission,callback,details)=>callback(contents===win?.webContents && details.requestingUrl===ui && permission==='media' && !details.mediaTypes?.includes('video')));
 session.defaultSession.setPermissionCheckHandler((contents,permission)=>contents===win?.webContents && contents.getURL()===ui && permission==='media');
 win=new BrowserWindow({width:1400,height:920,minWidth:1000,minHeight:680,show:!smoke,backgroundColor:'#f5f7fc',icon:path.join(__dirname,'logo.png'),webPreferences:{preload:path.join(__dirname,'preload.cjs'),nodeIntegration:false,contextIsolation:true,sandbox:true}});
 win.setMenuBarVisibility(false);win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',e=>e.preventDefault());
 win.on('close',e=>{if(active || inFlight.size){e.preventDefault();dialog.showMessageBox(win,{message:'请先结束录音并等待保存或总结完成。',buttons:['知道了']});}});
 overlay=listeningPanel(win);
 win.on('closed',()=>overlay.destroy());
 documents=new DocumentStore(root,meeting,persist,id=>win.webContents.send('meeting-updated',id));
 await documents.load();
 speech=new LocalSpeech(process.resourcesPath,root,event=>{
   if(!active) return;
   if(event.type==='error') win.webContents.send('speech-error',event.message);
   if(event.type==='roster' || event.type==='attribution'){
     const m=meeting(active.id);
     if(event.type==='roster')m.speakers=event.speakers;
     else{
       const row=m.lines.find(line=>line.recording===active.file && line.start===event.start);
       if(!row || row.speakerLocked)return;
       Object.assign(row,{speaker:event.speaker,speakerID:event.speakerID,voices:event.voices,overlap:event.overlap});
     }
     persist().then(()=>win.webContents.send('meeting-updated',m.id)).catch(error=>win.webContents.send('speech-error',error.message));
   }
   if(event.type==='partial'||event.type==='final'){
     overlay.update({text:event.text,speaker:event.speaker});
     if(event.type==='final'){
       const m=meeting(active.id);
       m.lines.push({id:crypto.randomUUID(),text:event.text,recording:active.file,speaker:event.speaker,speakerID:event.speakerID,voices:event.voices,overlap:event.overlap,start:event.start,end:event.end});
       persist().then(()=>win.webContents.send('meeting-updated',m.id)).catch(error=>win.webContents.send('speech-error',error.message));
     }
   }
 });
 if(smoke && process.env.TOPMEETING_SMOKE_MODELS)speech.models=process.env.TOPMEETING_SMOKE_MODELS;
 bind('load',()=>({meetings,config:publicConfig(),accounts:documents.public()}));
 bind('install-models',()=>speech.install());
 bind('bind-account',(id,settings)=>documents.bind(id,settings));
 bind('configure-account',(id,action)=>documents.configure(id,action));
 bind('open-document',(id,provider)=>documents.open(id,provider));
 bind('recover-document',(id,provider,url,retry)=>documents.recover(id,provider,url,retry));
 bind('overlay-state',(paused,duration)=>{if(active) overlay.update({paused:!!paused,duration:Number(duration)||0});});
 bind('pcm',async samples=>{
   if(!active?.local || !(samples instanceof Float32Array) || !samples.length || samples.length>16000)throw new Error('无效的麦克风音频块');
   let power=0;for(const value of samples)power+=value*value;
   overlay.update({level:Math.sqrt(power/samples.length)});
   await speech.command('audio',{pcm:Buffer.from(samples.buffer,samples.byteOffset,samples.byteLength).toString('base64')},'ack');
 });
 async function renameIdentity(m,source,name){
   if(active && active.id!==m.id)throw new Error('正在处理其他会议');
   const targets=new Set();
   for(const other of meetings){
     for(const person of other.speakers||[]){
       if(person.id!==source && person.name===name && (other.id===m.id || person.named))targets.add(person.id);
     }
   }
   if(targets.size>1)throw new Error('有多个同名身份，请先赋予不同的姓名再选择');
   const update=await speech.name(m,source,name,[...targets][0]);
   function canonical(identity){
     let key=identity;const seen=new Set();
     while(update.mappings?.[key] && !seen.has(key)){seen.add(key);key=update.mappings[key];}
     return key;
   }
   const profiles=new Set(update.profiles?.map(p=>p.id));
   function relabel(people){
     const unique=new Map();
     for(const person of people||[]){
       const id=canonical(person.id);
       unique.set(id,{id,name:update.names?.[id]||person.name,named:profiles.has(id)});
     }
     return [...unique.values()];
   }
   m.speakers=relabel(m.speakers);
   for(const row of m.lines){
     if(row.voices)row.voices=relabel(row.voices);
     const key=canonical(row.speakerID);
     if(key && update.names?.[key]){row.speakerID=key;row.speaker=update.names[key];row.namedIdentity=profiles.has(key);}
   }
 }
 bind('name-speaker',async(id,source,name)=>{
   const m=meeting(id),clean=String(name).trim();
   if(!clean || clean.length>60 || !m.speakers?.some(p=>p.id===source))throw new Error('说话人或姓名无效');
   await renameIdentity(m,source,clean);await persist();return m;
 });
 bind('line',async(id,lineId,patch)=>{
   const m=meeting(id),line=m.lines.find(l=>l.id===lineId);
   if(!line)throw new Error('实录已变化');
   if(patch.remove)m.lines=m.lines.filter(l=>l.id!==lineId);
   else if(typeof patch.text==='string') line.text=patch.text.slice(0,100000);
   else if(typeof patch.speaker==='string'){
     const name=patch.speaker.trim().slice(0,60);
     if(!name)throw new Error('请填写姓名');
     const source=patch.speakerID || line.speakerID;
     if(source && source!==line.speakerID && !line.voices?.some(voice=>voice.id===source))throw new Error('说话人已更新，请重新选择');
     if(source && source!=='unknown'){
       await renameIdentity(m,source,name);
     }else line.speaker=name;
     line.speakerLocked=true;
   }
   await persist();return m;
 });
 bind('add-line',async id=>{
   const m=meeting(id);m.lines.push({id:crypto.randomUUID(),speaker:'未标记',text:''});await persist();
 });
 bind('create',async()=>{if(active)throw new Error('请先结束录音');const m={id:crypto.randomUUID(),title:'新会议',date:new Date().toISOString(),lines:[],notes:'',context:'',duration:0,recordings:[]};meetings.unshift(m);await persist();return m;});
 bind('edit',async(id,patch)=>{const m=meeting(id);if(inFlight.has(id))throw new Error('正在处理，请稍后修改');for(const key of ['title','context']) if(typeof patch[key]==='string')m[key]=patch[key].slice(0,20000);if(Array.isArray(patch.lines)){if(patch.lines.length>100000)throw new Error('实录过长');m.lines=patch.lines.map(l=>({id:typeof l.id==='string'?l.id:crypto.randomUUID(),speaker:String(l.speaker||'未标记').slice(0,100),text:String(l.text||'').slice(0,100000)}));}await persist();return m;});
 bind('trash',async(id,deleted)=>{if(active?.id===id || inFlight.has(id))throw new Error('会议正在使用中');meeting(id).deletedAt=deleted?new Date().toISOString():null;await persist();});
 bind('settings',async(next)=>{if(active||inFlight.size)throw new Error('请在会议处理结束后修改设置');const c={};for(const k of ['kind','base','model','language'])c[k]=String(next[k]||'').trim();endpoint(c.base,'chat/completions');if(!c.model)throw new Error('请填写模型或 Agent');c.token=next.token||config.token||'';if(!safeStorage.isEncryptionAvailable())throw new Error('系统凭据加密不可用，未保存');const encrypted=safeStorage.encryptString(JSON.stringify(c));await fs.writeFile(path.join(root,'credentials.tmp'),encrypted);await fs.rename(path.join(root,'credentials.tmp'),path.join(root,'credentials.bin'));config=c;return publicConfig();});
 bind('record-start',async(id,local=true)=>{
   if(active||inFlight.has(id))throw new Error('会议正在使用中');
   const m=meeting(id),file=crypto.randomUUID()+'.webm';
   const capturing={id,file,local:local!==false};
   active=capturing;
   try {
     if(capturing.local) await speech.start(m);
     await fs.writeFile(path.join(root,'audio',file),'');
     m.recordings.push(file);await persist();
     if(capturing.local) await overlay.show(m.duration);
     documents.start(id).catch(error=>win.webContents.send('speech-error',error.message));
   }catch(error){active=null;speech.child?.kill();overlay.hide();throw error;}
 });
 bind('record-chunk',async(bytes)=>{if(!active)throw new Error('没有正在进行的录音');if(!(bytes instanceof Uint8Array)||bytes.length>20*1024*1024)throw new Error('音频块无效');await fs.appendFile(path.join(root,'audio',active.file),Buffer.from(bytes));});
 bind('record-stop',async(duration)=>{
   if(!active)return;
   const m=meeting(active.id);
   try{if(active.local && speech.child)await speech.command('finish',{},'finished');}
   finally{m.duration+=Math.max(0,Math.min(Number(duration)||0,86400));active=null;overlay.hide();await persist();}
 });
 bind('audio',async(id,index)=>{const m=meeting(id);if(active?.id===id)throw new Error('请先结束录音');const file=m.recordings[index];if(!file)throw new Error('录音不存在');return new Uint8Array(await fs.readFile(path.join(root,'audio',file)));});
 bind('export',async(id)=>{const m=meeting(id);const result=await dialog.showSaveDialog(win,{defaultPath:'meeting.md',filters:[{name:'Markdown',extensions:['md']}]});if(!result.canceled)await fs.writeFile(result.filePath,`# ${m.title}\n\n${m.notes}\n\n## 实录\n\n${m.lines.map(l=>`**${l.speaker}** ${l.text}`).join('\n\n')}`);});
 await win.loadFile(path.join(__dirname,'index.html'));
 if(smoke){try{const result=await win.webContents.executeJavaScript(`(async()=>{await window.api.create();const data=await window.api.load();if(data.meetings.length!==1)throw Error('Storage failure');await window.api.edit(data.meetings[0].id,{title:'Synthetic smoke fixture',lines:[{text:'Release check',speaker:'Test'}]});await window.api.trash(data.meetings[0].id,true);await window.api.trash(data.meetings[0].id,false);await window.api.start(data.meetings[0].id,false);await window.api.chunk(new Uint8Array([1,2,3]));await window.api.stop(2);const audio=await window.api.audio(data.meetings[0].id,0);if(audio.length!==3||audio[2]!==3)throw Error('Audio persistence failed');if(!document.querySelector('#record'))throw Error('UI missing');return 'PASS';})()`);await win.webContents.executeJavaScript('reload()');
 if(process.env.TOPMEETING_SMOKE_FIXTURE){
   await win.webContents.executeJavaScript(`(async()=>{
     await begin();
     await new Promise(resolve=>setTimeout(resolve,20000));
     await togglePause();await togglePause();await finish();
     const saved=(await api.load()).meetings[0];
     if(!saved.lines.some(line=>Number.isFinite(line.start)&&line.text))throw Error('No local transcript from packaged microphone path');
     if(!saved.speakers?.length)throw Error('Speaker roster missing');
     document.querySelector('#people').click();
     if(!document.querySelector('#peopleList input'))throw Error('Speaker management not available');
     document.querySelector('#closePeople').click();
     return true;
   })()`);
 }
 await new Promise(resolve=>setTimeout(resolve,500));await fs.writeFile(path.join(os.tmpdir(),'topmeeting-windows-preview.png'),(await win.webContents.capturePage()).toPNG());console.log('WINDOWS_SMOKE_'+result);await fs.writeFile(path.join(os.tmpdir(),'topmeeting-smoke-result.txt'),result);app.exit(0);}catch(e){console.error(e);app.exit(1);}}
}).catch(e=>{console.error(e.message);app.exit(1);});
app.on('window-all-closed',()=>app.quit());
