const http = require('node:http');
const assert = require('node:assert/strict');

// Uses a separate smoke-test profile, a loopback model service and Chromium's fixture microphone.
async function checkWorkspace(win,speech,dataDirectory,installedModels) {
  const path=require('node:path');
  const ui=fn=>win.webContents.executeJavaScript('('+fn.toString()+')()');
  speech.models=path.join(dataDirectory,'empty-model-library');
  await ui(async()=>{
    const real=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    let microphoneRequests=0;
    navigator.mediaDevices.getUserMedia=(opts)=>{microphoneRequests++;return real(opts);};
    await requestRecording();
    if($('prepare').hidden || microphoneRequests || recorder)throw Error('Model guidance must precede microphone access');
    await $('onlyAudio').onclick();
    if(!recorder || context || microphoneRequests!==1)throw Error('Audio-only capture failed');
    await new Promise(resolve=>setTimeout(resolve,750));
    await togglePause();await togglePause();await finish();
    if($('docHint').hidden)throw Error('Document suggestion missing after recording');
    $('connectDocs').click();
    if(!$('accountDialog').open || $('service').options.length!==5)throw Error('Document setup unavailable');
    $('closeAccounts').click();$('hideDocHint').click();
    await reload();if(!$('docHint').hidden)throw Error('Dismissal lost');
    $('settings').click();if(!$('dialog').open)throw Error('Settings unavailable');$('close').click();
    const saved=current();if(saved.lines.length!==1 || saved.recordings.length!==2)throw Error('Audio-only changed the transcript');
  });

  speech.models=installedModels;
  await ui(async()=>{
    await $('models').onclick();
    if(modelPhase!=='ready' || recorder)throw Error('Model setup started recording without a click');
    await requestRecording();
    if(!recorder || !context)throw Error('Local capture did not start');
    await new Promise(resolve=>setTimeout(resolve,20000));
  });
  const panel=require('electron').BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/overlay.html'));
  assert.ok(panel?.isAlwaysOnTop(),'Floating listening panel missing');
  async function pressPause(expected){
    await panel.webContents.executeJavaScript("document.querySelector('#pause').click()");
    for(let i=0;i<30;i++){
      if(await win.webContents.executeJavaScript('paused')===expected)return;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw Error('Overlay pause/resume did not reach recording controls');
  }
  await pressPause(true);await pressPause(false);
  await panel.webContents.executeJavaScript("document.body.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}))");
  assert.ok(win.isVisible(),'Double-click did not open the main window');
  await ui(async()=>{
    await finish();
    const saved=(await api.load()).meetings[0];
    if(!saved.lines.some(line=>Number.isFinite(line.start)&&line.text))throw Error('Missing local transcript');
    $('people').click();
    if(!$('peopleList').querySelector('input'))throw Error('Speaker roster unavailable');
    $('closePeople').click();
    await api.addLine(saved.id);
    const last=(await api.load()).meetings[0].lines.at(-1);
    await api.line(saved.id,last.id,{text:'测试修订',speaker:'测试'});
    await api.line(saved.id,last.id,{remove:true});
    await reload();
    $('search').value='Synthetic';$('search').dispatchEvent(new Event('input'));
    if(!$('meetings').children.length)throw Error('Search lost the selected meeting');
    $('search').value='';render();
  });

  let submissions=0;
  const server=http.createServer((req,res)=>{
    submissions++;
    if(submissions>1){res.writeHead(503);res.end();return;}
    res.writeHead(200,{'Content-Type':'text/event-stream'});
    res.end('data: {"choices":[{"delta":{"content":"## 决策\\n保留完整段落。"}}]}\n\ndata: [DONE]\n\n');
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const base='http://127.0.0.1:'+server.address().port;
    await win.webContents.executeJavaScript(`(async()=>{
      await api.settings({kind:'compatible',base:${JSON.stringify(base)},model:'fixture',token:'synthetic',language:'zh'});
      await reload();await process('summarize');await process('summarize');
      if(!current().notes.includes('保留完整段落'))throw Error('Summary did not persist');
      if((await api.load()).config.token)throw Error('Credential exposed');
    })()`);
    assert.equal(submissions,1,'Repeated summary consumed a second model call');
    const {dialog}=require('electron');
    const saveDialog=dialog.showSaveDialog, exported=path.join(dataDirectory,'smoke.md');
    try{
      dialog.showSaveDialog=async()=>({filePath:exported,canceled:false});
      await ui(async()=>{await $('export').onclick();});
      assert.ok((await require('node:fs/promises').readFile(exported,'utf8')).includes('保留完整段落'));
    }finally{dialog.showSaveDialog=saveDialog;}
    await ui(async()=>{
      await api.edit(selected,{context:'fixture revision'});
      let rejected=false;
      try{await api.summarize(selected);}catch{rejected=true;}
      await reload();
      if(!rejected || !current().notes.includes('保留完整段落'))throw Error('Failed summary replaced existing notes');
    });
  } finally {server.close();}
}
module.exports={checkWorkspace};
