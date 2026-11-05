let context,node,source,pcmQueue,flushPCM,pcmError,queued,captureWarning;
function showTime(){
  const seconds=(current()?.duration||0)+elapsed+(paused?0:(Date.now()-started)/1000);
  $('time').textContent=clock(seconds);api.overlay(paused,seconds).catch(()=>{});
}
async function begin(local=true){
  if(busy)return;
  busy=true;captureWarning="";render();
  let opened=false;
  try{
    stream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:true},video:false});
    if(local){
    context=new AudioContext({sampleRate:16000});
    await context.audioWorklet.addModule('pcm-worklet.js');
    node=new AudioWorkletNode(context,'meeting-pcm');
    source=context.createMediaStreamSource(stream);
    }
    recorder=new MediaRecorder(stream,{mimeType:'audio/webm;codecs=opus',audioBitsPerSecond:64000});
    notice('正在启动本地语音与声纹模型…');
    await api.start(selected,local);opened=true;
    pcmQueue=Promise.resolve();pcmError=null;queued=0;writes=Promise.resolve();recordError=null;
    if(local)node.port.onmessage=({data})=>{
      if(data==='flushed'){flushPCM?.();return;}
      if(pcmError)return;
      if(queued>80){pcmError=new Error('本机识别落后超过 20 秒，原音继续保存');notice(pcmError.message);return;}
      queued++;
      pcmQueue=pcmQueue.then(()=>api.pcm(data)).catch(error=>{pcmError=error;notice(error.message);}).finally(()=>queued--);
    };
    recorder.ondataavailable=e=>{
      if(e.data.size)writes=writes.then(async()=>api.chunk(new Uint8Array(await e.data.arrayBuffer()))).catch(error=>{recordError=error;notice(error.message);});
    };
    if(local){
    source.connect(node);
    node.connect(context.destination); // Worklet emits silence, preserving the microphone signal without feedback.
    await context.resume();
    }
    recorder.start(5000);started=Date.now();elapsed=0;paused=false;
    timer=setInterval(showTime,500);
    $('record').textContent='结束录音';$('pause').hidden=false;$('pause').textContent='暂停';
    notice(local?captureWarning:'仅录音，本场不生成实时字幕。');
  }catch(error){
    source?.disconnect();node?.disconnect();await context?.close().catch(()=>{});stream?.getTracks().forEach(t=>t.stop());recorder=null;
    node=null;context=null;source=null;if(opened)await api.stop(0);
    if(error.name==='NotAllowedError')throw new Error('请在 Windows 隐私设置中允许麦克风访问，然后再开始录音。');
    throw error;
  }finally{busy=false;render();}
}
async function togglePause(){
  if(!recorder||busy)return;
  if(paused){await context?.resume();recorder.resume();started=Date.now();}
  else{await context?.suspend();recorder.pause();elapsed+=(Date.now()-started)/1000;}
  paused=!paused;$('pause').textContent=paused?'继续':'暂停';showTime();
}
async function finish(){
  if(!recorder||busy)return;
  busy=true;render();
  if(!paused)elapsed+=(Date.now()-started)/1000;
  clearInterval(timer);
  try{
    if(node){
    source.disconnect();
    if(paused)await context.resume();
    const flushed=new Promise(resolve=>{flushPCM=resolve;});
    node.port.postMessage('flush');await flushed;await pcmQueue;
    }
    await new Promise(resolve=>{recorder.onstop=resolve;recorder.stop();});
    await writes;
    await api.stop(elapsed);
  }finally{
    stream.getTracks().forEach(t=>t.stop());node?.disconnect();await context?.close();node=null;context=null;source=null;
    recorder=null;busy=false;elapsed=0;$('pause').hidden=true;$('record').textContent='开始录音';await reload();
  }
  if(recordError||pcmError)throw recordError||pcmError;
  notice('会议已保存');
  if(state.config.base&&current()?.lines.length)await process('summarize');
}
let guideMeeting=null, modelPhase='missing', modelDetail='', installingModels=false;
const missingDetail='首次需下载约 220 MB 模型，用于离线字幕和说话人识别。';
function paintPreparation(){
  const ready=modelPhase==='ready';
  $('prepareTitle').textContent=ready?'本地模型已就绪':installingModels?'正在准备语音模型':modelPhase==='failed'?'模型准备未完成':'准备本地转写';
  $('prepareInfo').textContent=modelDetail||(ready?'可以开始录音，本机将实时转写。':missingDetail);
  $('prepareAction').textContent=ready?'开始录音':installingModels?'下载中…':modelPhase==='failed'?'重试下载':'下载模型';
  $('prepareAction').disabled=installingModels;
  $('onlyAudio').hidden=ready;
  $('models').disabled=installingModels;
}
window.refreshGuidance=m=>{
  $('prepare').hidden=!m || m.id!==guideMeeting || !!recorder || !!m.deletedAt;
  $('record').hidden=!$('prepare').hidden;
  const suggest=m && !m.deletedAt && m.recordings.length && !recorder && !busy && !state.accounts?.some(a=>a.label)
    && !Object.keys(m.documents||{}).length && !localStorage.getItem('documentHintDismissed');
  $('docHint').hidden=!suggest;
};
async function requestRecording(){
  if(recorder)return finish();
  if(busy || !current())return;
  const id=selected;
  busy=true;render();
  let ready=false;
  try{ready=!installingModels && await api.checkModels();}
  catch{modelPhase='failed';modelDetail='无法检查语音组件。可以重试，或先只录音。';}
  finally{busy=false;render();}
  if(id!==selected)return;
  if(ready){guideMeeting=null;return begin(true);}
  if(modelPhase==="ready"){modelPhase="missing";modelDetail="";}
  guideMeeting=id;paintPreparation();render();
  $('prepareAction').focus();
}
async function installModels(){
  if(installingModels)return;
  installingModels=true;modelPhase='loading';modelDetail='已下载的文件会先校验。';
  paintPreparation();$('modelStatus').textContent=modelDetail;
  try{
    await api.installModels();
    modelPhase='ready';modelDetail='已就绪，点击开始录音即可实时转写。';
  }catch{
    modelPhase='failed';modelDetail='检查网络后重试，已校验的模型文件会保留。';
  }finally{
    installingModels=false;paintPreparation();$('modelStatus').textContent=modelDetail;
  }
}
api.onModelProgress((count,total)=>{
  modelDetail=`已校验 ${count} / ${total} 个模型文件`;
  paintPreparation();$('modelStatus').textContent=modelDetail;
});
$('record').onclick=()=>action(requestRecording);
$('prepareAction').onclick=()=>action(()=>modelPhase==='ready'?requestRecording():installModels());
$('onlyAudio').onclick=()=>action(async()=>{guideMeeting=null;await begin(false);});
$('hidePrepare').onclick=()=>{guideMeeting=null;render();$('record').focus();};
$('connectDocs').onclick=()=>$('accounts').click();
$('hideDocHint').onclick=()=>{localStorage.setItem('documentHintDismissed','1');render();};
$('pause').onclick=()=>action(togglePause);api.onTogglePause(()=>action(togglePause));
api.onSpeechError(message=>{captureWarning=message;notice(message);});
api.onUpdate(id=>{if(id!==selected)return;if(document.activeElement?.closest('.line, .context, #title'))return;action(reload);});
$('models').onclick=()=>action(installModels);
