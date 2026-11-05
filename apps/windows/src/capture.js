let context,node,source,pcmQueue,flushPCM,pcmError,queued;
function showTime(){
  const seconds=(current()?.duration||0)+elapsed+(paused?0:(Date.now()-started)/1000);
  $('time').textContent=clock(seconds);api.overlay(paused,seconds).catch(()=>{});
}
async function begin(){
  if(busy)return;
  busy=true;render();
  let opened=false;
  try{
    stream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:true},video:false});
    context=new AudioContext({sampleRate:16000});
    await context.audioWorklet.addModule('pcm-worklet.js');
    node=new AudioWorkletNode(context,'meeting-pcm');
    source=context.createMediaStreamSource(stream);
    recorder=new MediaRecorder(stream,{mimeType:'audio/webm;codecs=opus',audioBitsPerSecond:64000});
    notice('正在启动本地语音与声纹模型…');
    await api.start(selected);opened=true;
    pcmQueue=Promise.resolve();pcmError=null;queued=0;writes=Promise.resolve();recordError=null;
    node.port.onmessage=({data})=>{
      if(data==='flushed'){flushPCM?.();return;}
      if(pcmError)return;
      if(queued>80){pcmError=new Error('本机识别落后超过 20 秒，原音继续保存');notice(pcmError.message);return;}
      queued++;
      pcmQueue=pcmQueue.then(()=>api.pcm(data)).catch(error=>{pcmError=error;notice(error.message);}).finally(()=>queued--);
    };
    recorder.ondataavailable=e=>{
      if(e.data.size)writes=writes.then(async()=>api.chunk(new Uint8Array(await e.data.arrayBuffer()))).catch(error=>{recordError=error;notice(error.message);});
    };
    source.connect(node);
    node.connect(context.destination); // Worklet emits silence, preserving the microphone signal without feedback.
    await context.resume();
    recorder.start(5000);started=Date.now();elapsed=0;paused=false;
    timer=setInterval(showTime,500);
    $('record').textContent='结束录音';$('pause').hidden=false;$('pause').textContent='暂停';
    notice('正在本机转写');
  }catch(error){
    source?.disconnect();node?.disconnect();await context?.close().catch(()=>{});stream?.getTracks().forEach(t=>t.stop());recorder=null;
    if(opened)await api.stop(0);
    throw error;
  }finally{busy=false;render();}
}
async function togglePause(){
  if(!recorder||busy)return;
  if(paused){await context.resume();recorder.resume();started=Date.now();}
  else{await context.suspend();recorder.pause();elapsed+=(Date.now()-started)/1000;}
  paused=!paused;$('pause').textContent=paused?'继续':'暂停';showTime();
}
async function finish(){
  if(!recorder||busy)return;
  busy=true;render();
  if(!paused)elapsed+=(Date.now()-started)/1000;
  clearInterval(timer);
  try{
    source.disconnect();
    if(paused)await context.resume();
    const flushed=new Promise(resolve=>{flushPCM=resolve;});
    node.port.postMessage('flush');await flushed;await pcmQueue;
    await new Promise(resolve=>{recorder.onstop=resolve;recorder.stop();});
    await writes;
    await api.stop(elapsed);
  }finally{
    stream.getTracks().forEach(t=>t.stop());node.disconnect();await context.close();
    recorder=null;busy=false;elapsed=0;$('pause').hidden=true;$('record').textContent='开始录音';await reload();
  }
  if(recordError||pcmError)throw recordError||pcmError;
  notice('录音与实录已保存');
  if(state.config.base&&current()?.lines.length)await process('summarize');
}
$('record').onclick=()=>action(()=>recorder?finish():begin());
$('pause').onclick=()=>action(togglePause);api.onTogglePause(()=>action(togglePause));
api.onSpeechError(message=>notice(message));
api.onUpdate(id=>{if(id!==selected)return;if(document.activeElement?.closest('.line, .context, #title'))return;action(reload);});
$('models').onclick=async()=>{
  $('models').disabled=true;$('modelStatus').textContent='正在检查并下载模型…';
  try{await api.installModels();$('modelStatus').textContent='本地语音模型已就绪';}
  catch(error){$('modelStatus').textContent=error.message;}
  finally{$('models').disabled=false;}
};
