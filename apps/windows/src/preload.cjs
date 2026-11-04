const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('api',{
 audio:(id,index)=>ipcRenderer.invoke('audio',id,index),
 load:()=>ipcRenderer.invoke('load'),create:()=>ipcRenderer.invoke('create'),edit:(id,patch)=>ipcRenderer.invoke('edit',id,patch),trash:(id,value)=>ipcRenderer.invoke('trash',id,value),settings:config=>ipcRenderer.invoke('settings',config),
 start:id=>ipcRenderer.invoke('record-start',id),chunk:bytes=>ipcRenderer.invoke('record-chunk',bytes),stop:duration=>ipcRenderer.invoke('record-stop',duration),transcribe:id=>ipcRenderer.invoke('transcribe',id),summarize:id=>ipcRenderer.invoke('summarize',id),export:id=>ipcRenderer.invoke('export',id),
 onDelta:handler=>ipcRenderer.on('summary-delta',(_,data)=>handler(data))
});
