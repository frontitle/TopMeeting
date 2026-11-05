const {EncryptedSettings}=require('./encrypted-settings.cjs');
const path=require('node:path');
const {safeStorage,shell}=require('electron');
const serviceModule=require('electron').app?.isPackaged
  ? path.join(process.resourcesPath,'document-services.cjs')
  : path.join(__dirname,'../../../packages/documents/document-services.cjs');
const {services,bindAccount,createDocument,safeLink}=require(serviceModule);

class DocumentStore {
  constructor(directory,meeting,persist,notify){
    this.settings=new EncryptedSettings(path.join(directory,'document-accounts.bin'),safeStorage,accounts=>
      Object.entries(accounts).every(([id,account])=>Object.hasOwn(services,id) && typeof account?.label==='string'));
    this.meeting=meeting;this.persist=persist;this.notify=notify;
    this.accounts={};this.pending=new Set();this.busy=false;
  }
  async load(){this.accounts=await this.settings.load();}
  save(){return this.settings.save(this.accounts);}
  async replaceAccount(id,account){
    const before=this.accounts;
    this.accounts={...before};
    if(account)this.accounts[id]=account;
    else delete this.accounts[id];
    try{await this.save();}catch(error){this.accounts=before;throw error;}
  }
  public(){
    return Object.entries(services).map(([id,service])=>({id,name:service.name,label:this.accounts[id]?.label,enabled:!!this.accounts[id]?.enabled}));
  }
  async bind(id,settings){
    if(this.busy||this.pending.size)throw new Error('请等待账号授权或文档创建完成');
    this.busy=true;
    try{
      const account=await bindAccount(id,settings,url=>shell.openExternal(url));
      await this.replaceAccount(id,{...account,enabled:!!settings.enabled});return this.public();
    }finally{this.busy=false;}
  }
  async configure(id,action){
    if(this.busy||this.pending.size)throw new Error('请等待账号授权或文档创建完成');
    if(!this.accounts[id])throw new Error('请先绑定账号');
    this.busy=true;
    try{
      const account=action==='disconnect'?null:{...this.accounts[id],enabled:action==='enable'};
      await this.replaceAccount(id,account);return this.public();
    }finally{this.busy=false;}
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
