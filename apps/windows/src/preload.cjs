const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('api',{
 installModels:()=>ipcRenderer.invoke('install-models'), pcm:samples=>ipcRenderer.invoke('pcm',samples),
 overlay:(paused,duration)=>ipcRenderer.invoke('overlay-state',paused,duration),
 nameSpeaker:(id,source,name)=>ipcRenderer.invoke('name-speaker',id,source,name),
 line:(id,lineId,patch)=>ipcRenderer.invoke('line',id,lineId,patch),addLine:id=>ipcRenderer.invoke('add-line',id),
 bindAccount:(id,settings)=>ipcRenderer.invoke('bind-account',id,settings),
 configureAccount:(id,action)=>ipcRenderer.invoke('configure-account',id,action),
 openDocument:(id,provider)=>ipcRenderer.invoke('open-document',id,provider),
 recoverDocument:(id,provider,url,retry)=>ipcRenderer.invoke('recover-document',id,provider,url,retry),
 onUpdate:handler=>ipcRenderer.on('meeting-updated',(_,id)=>handler(id)),
 onSpeechError:handler=>ipcRenderer.on('speech-error',(_,message)=>handler(message)),
 onTogglePause:handler=>ipcRenderer.on('toggle-listening-pause',()=>handler()),
 audio:(id,index)=>ipcRenderer.invoke('audio',id,index),
 load:()=>ipcRenderer.invoke('load'),create:()=>ipcRenderer.invoke('create'),edit:(id,patch)=>ipcRenderer.invoke('edit',id,patch),trash:(id,value)=>ipcRenderer.invoke('trash',id,value),settings:config=>ipcRenderer.invoke('settings',config),
 start:(id,local=true)=>ipcRenderer.invoke('record-start',id,local),chunk:bytes=>ipcRenderer.invoke('record-chunk',bytes),stop:duration=>ipcRenderer.invoke('record-stop',duration),summarize:id=>ipcRenderer.invoke('summarize',id),export:id=>ipcRenderer.invoke('export',id),
 onDelta:handler=>ipcRenderer.on('summary-delta',(_,data)=>handler(data))
});
