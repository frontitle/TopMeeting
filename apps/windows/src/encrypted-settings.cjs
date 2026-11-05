const fs=require('node:fs/promises');
const {randomUUID}=require('node:crypto');
const {replace}=require('./atomic-file.cjs');

// A damaged optional integration must not prevent local recording or destroy previous credentials.
class EncryptedSettings {
  constructor(file,vault,validate=()=>true){
    this.file=file;this.vault=vault;this.validate=validate;this.queue=Promise.resolve();this.preserve=false;
  }
  async load(){
    let encrypted;
    try{encrypted=await fs.readFile(this.file);}
    catch(error){if(error.code==='ENOENT')return {};this.preserve=true;throw error;}
    try{
      const value=JSON.parse(this.vault.decryptString(encrypted));
      if(!value || typeof value!=='object' || Array.isArray(value) || !this.validate(value))throw Error('Invalid settings');
      return value;
    }catch(error){this.preserve=true;throw error;}
  }
  save(value){
    if(!this.vault.isEncryptionAvailable())throw Error('系统凭据加密不可用');
    const bytes=this.vault.encryptString(JSON.stringify(value));
    const operation=this.queue.then(async()=>{
      if(this.preserve){
        await fs.copyFile(this.file,this.file+'.unreadable-'+randomUUID(),fs.constants.COPYFILE_EXCL);
        this.preserve=false;
      }
      await replace(this.file,bytes);
    });
    this.queue=operation.catch(()=>{});
    return operation;
  }
}
module.exports={EncryptedSettings};
