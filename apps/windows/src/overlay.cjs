const {BrowserWindow,ipcMain}=require('electron');
const path=require('node:path');
function listeningPanel(main){
  let panel;
  let state={text:'',speaker:'',paused:false,duration:0,level:0};
  ipcMain.on('overlay-control',(event,action)=>{
    if(!panel || event.sender!==panel.webContents) return;
    if(action==='open'){if(main.isMinimized()) main.restore();main.show();main.focus();}
    if(action==='end') main.webContents.send('end-listening');
    if(action==='pause') main.webContents.send('toggle-listening-pause');
  });
  return {
    async show(duration){
      state={text:'',speaker:'',paused:false,duration,level:0};
      if(!panel || panel.isDestroyed()){
        panel=new BrowserWindow({width:380,height:126,frame:false,resizable:false,alwaysOnTop:true,
          skipTaskbar:true,show:false,backgroundColor:'#17233c',webPreferences:{
            preload:path.join(__dirname,'overlay-preload.cjs'),sandbox:true,contextIsolation:true,nodeIntegration:false
          }});
        panel.on('closed',()=>{panel=null;});
        panel.webContents.setWindowOpenHandler(()=>({action:'deny'}));
        panel.webContents.on('will-navigate',event=>event.preventDefault());
        await panel.loadFile(path.join(__dirname,'overlay.html'));
      }
      panel.webContents.send('listening-state',state);
      panel.showInactive();
    },
    update(patch){Object.assign(state,patch);if(panel&&!panel.isDestroyed()) panel.webContents.send('listening-state',state);},
    hide(){panel?.hide();},
    destroy(){panel?.destroy();}
  };
}
module.exports={listeningPanel};
