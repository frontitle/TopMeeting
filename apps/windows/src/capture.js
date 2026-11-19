let context,node,source,pcmQueue,flushPCM,pcmError,queued,captureWarning,recorderStopped;
let unsavedChunks=[], audioOffset=0, pendingSave=false, writeInterrupted=false;
async function writeRecordingChunks(){
  while(unsavedChunks.length){
    const chunk=unsavedChunks[0];
    await api.chunk(new Uint8Array(await chunk.arrayBuffer()),audioOffset);
    audioOffset+=chunk.size;
    unsavedChunks.shift();
  }
}
function showTime(){
  const seconds=displayedDuration(current());
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
    unsavedChunks=[];audioOffset=0;pendingSave=false;writeInterrupted=false;
    if(local)node.port.onmessage=({data})=>{
      if(data==='flushed'){flushPCM?.();return;}
      if(pcmError)return;
      if(queued>80){pcmError=new Error('本机识别落后超过 20 秒，原音继续保存');notice(pcmError.message);return;}
      queued++;
      pcmQueue=pcmQueue.then(()=>api.pcm(data)).catch(error=>{pcmError=error;notice(error.message);}).finally(()=>queued--);
    };
    recorder.ondataavailable=e=>{
      const limit=4*1024*1024;
      for(let start=0;start<e.data.size;start+=limit)unsavedChunks.push(e.data.slice(start,start+limit));
      writes=writes.then(writeRecordingChunks).catch(error=>{
        writeInterrupted=true;
        notice('原音写入失败，正在停止录音。'+error.message);
        if(!busy)action(finish);
      });
    };
    if(local){
    source.connect(node);
    node.connect(context.destination); // Worklet emits silence, preserving the microphone signal without feedback.
    await context.resume();
    }
    recorder.onerror=event=>{
      recordError=event.error||new Error('录音设备出错');
      notice(recordError.message);
    };
    recorderStopped=new Promise(resolve=>{
      recorder.onstop=()=>{
        resolve();
        if(!busy){
          captureWarning='麦克风录音已中断，已有录音已保存。';
          action(finish);
        }
      };
    });
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
let pauseChange;
function togglePause(){
  if(!recorder||busy||pendingSave||pauseChange)return pauseChange;
  pauseChange=changePause().finally(()=>{pauseChange=null;});
  return pauseChange;
}
async function changePause(){
  if(!recorder||busy)return;
  if(paused){await context?.resume();recorder.resume();started=Date.now();}
  else{await context?.suspend();recorder.pause();elapsed+=(Date.now()-started)/1000;}
  paused=!paused;$('pause').textContent=paused?'继续':'暂停';showTime();
}
async function finish(){
  if(!recorder||busy)return;
  busy=true;render();
  try{
    if(!pendingSave){
      try{await pauseChange;}catch(error){notice(error.message);}
      if(!paused)elapsed+=(Date.now()-started)/1000;
      clearInterval(timer);
      notice('正在保存会议…');
      if(recorder.state!=='inactive')recorder.stop();
      const drained=node ? drainMicrophone().catch(error=>{pcmError=error;}) : null;
      await recorderStopped;
      stream.getTracks().forEach(track=>track.stop());
      await writes;
      await drained;
      await pcmQueue;
      node?.disconnect();
      await context?.close().catch(()=>{});
      node=null;context=null;source=null;
      pendingSave=true;
      $('pause').hidden=true;
    }
    // A failed or partially acknowledged write stays at the same offset until it succeeds.
    await writeRecordingChunks();
    const speechWarning=await api.stop(elapsed);
    if(speechWarning)pcmError=new Error(speechWarning);
  }catch(error){
    if(!pendingSave)throw error;
    $('record').textContent='重试保存';
    throw new Error('本次录音待保存，请检查可用空间后重试。'+error.message);
  }finally{
    busy=false;
    render();
  }
  recorder=null;pendingSave=false;elapsed=0;
  $('record').textContent='开始录音';
  await reload();
  if(recordError)throw recordError;
  if(pcmError)throw new Error('录音已保存，部分字幕可能缺失。'+pcmError.message);
  notice(writeInterrupted?'录音因写入中断，已有录音已保存。':captureWarning||'会议已保存');
  if(state.config.base&&current()?.lines.length)await process('summarize');
}
async function drainMicrophone(){
  source.disconnect();
  let timeout;
  try{
    await new Promise((resolve,reject)=>{
      flushPCM=resolve;
      timeout=setTimeout(()=>reject(new Error('尾段语音处理超时。')),3000);
      if(context.state==='suspended')context.resume().catch(reject);
      node.port.postMessage('flush');
    });
  }finally{
    clearTimeout(timeout);
    flushPCM=null;
    node.port.onmessage=null;
  }
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
api.onEndListening(()=>action(finish));
api.onSpeechError(message=>{captureWarning=message;notice(message);});
api.onUpdate(id=>{if(id!==selected)return;if(document.activeElement?.closest('.line, .context, #title'))return;action(reload);});
$('models').onclick=()=>action(installModels);
