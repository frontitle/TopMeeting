// Invoked by the native host with credentials over stdin. Only stdout returns a result.
const fs=require('node:fs');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const {bindAccount,createDocument}=require('./document-services.cjs');
async function run(){
  const request=JSON.parse(fs.readFileSync(0,'utf8'));
  let account=request.account;
  try{
    if(request.action==='bind'){
      account=await bindAccount(request.provider,request.settings,url=>promisify(execFile)('/usr/bin/open',[url]));
      return {account};
    }
    if(request.action==='create'){
      const url=await createDocument(request.provider,account,request.title,async()=>{});
      return {account,url};
    }
    throw new Error('未知文档操作');
  }catch(error){return {account,error:error.message};}
}
run().then(result=>process.stdout.write(JSON.stringify(result))).catch(()=>process.exit(1));
