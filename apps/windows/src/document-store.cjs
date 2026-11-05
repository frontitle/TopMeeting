const fs=require('node:fs/promises');
const path=require('node:path');
const {safeStorage,shell}=require('electron');
const {services,bindAccount,createDocument,safeLink}=require('./document-services.cjs');

class DocumentStore {
  constructor(directory,meeting,persist,notify){
    this.file=path.join(directory,'document-accounts.bin');
    this.meeting=meeting;this.persist=persist;this.notify=notify;
    this.accounts={};this.pending=new Set();this.busy=false;
  }
  async load(){
    try{this.accounts=JSON.parse(safeStorage.decryptString(await fs.readFile(this.file)));}
    catch(error){if(error.code!=='ENOENT') throw error;}
  }
  async save(){
    if(!safeStorage.isEncryptionAvailable())throw new Error('系统凭据加密不可用');
    const encrypted=safeStorage.encryptString(JSON.stringify(this.accounts));
    this.saving=(this.saving||Promise.resolve()).catch(()=>{}).then(async()=>{
      await fs.writeFile(this.file+'.tmp',encrypted);
      await fs.rename(this.file+'.tmp',this.file);
    });
    await this.saving;
  }
  public(){
    return Object.entries(services).map(([id,service])=>({id,name:service.name,label:this.accounts[id]?.label,enabled:!!this.accounts[id]?.enabled}));
  }
  async bind(id,settings){
    if(this.busy)throw new Error('请等待当前账号授权完成');
    this.busy=true;
    try{
      const account=await bindAccount(id,settings,url=>shell.openExternal(url));
      this.accounts[id]={...account,enabled:!!settings.enabled};
      await this.save();return this.public();
    }finally{this.busy=false;}
  }
  async configure(id,action){
    if(!this.accounts[id])throw new Error('请先绑定账号');
    if(action==='disconnect')delete this.accounts[id];
    else this.accounts[id].enabled=action==='enable';
    await this.save();return this.public();
  }
  async start(id){
    const m=this.meeting(id);
    await Promise.all(Object.entries(this.accounts).filter(([,account])=>account.enabled).map(async([provider,account])=>{
      m.documents ||= {};
      if(m.documents[provider])return;
      const key=id+'/'+provider;
      m.documents[provider]={status:'pending'};
      this.pending.add(key);
      try{
        await this.persist();
        const url=await createDocument(provider,account,m.title,()=>this.save());
        m.documents[provider]={status:'ready',url};
      }catch(error){
        m.documents[provider]={status:'uncertain',message:error.message};
      }finally{this.pending.delete(key);}
      await this.persist();this.notify(id);
    }));
  }
  async recover(id,provider,url,retry){
    const m=this.meeting(id);
    if(this.pending.has(id+'/'+provider)||!services[provider])throw new Error('文档操作进行中');
    if(url)m.documents[provider]={status:'ready',url:safeLink(provider,url)};
    else if(retry){delete m.documents[provider];await this.start(id);}
    await this.persist();this.notify(id);
  }
  async open(id,provider){
    const link=this.meeting(id).documents?.[provider]?.url;
    if(!link)throw new Error('没有可打开的文档');
    await shell.openExternal(safeLink(provider,link));
  }
}
module.exports={DocumentStore};
