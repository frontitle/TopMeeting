const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('listening',{
  onState:callback=>ipcRenderer.on('listening-state',(_,state)=>callback(state)),
  open:()=>ipcRenderer.send('overlay-control','open'),
  pause:()=>ipcRenderer.send('overlay-control','pause')
});
