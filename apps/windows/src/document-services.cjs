const crypto = require('node:crypto');
const http = require('node:http');

const services = {
  feishu: { name: '飞书文档', hosts:['feishu.cn','larksuite.com'] },
  google: { name: 'Google Docs', hosts:['docs.google.com'] },
  notion: { name:'Notion', hosts:['notion.so','notion.site'] },
  ding: { name:'钉钉文档', hosts:['dingtalk.com','alidocs.com'] },
  tencent: { name:'腾讯文档', hosts:['docs.qq.com'] }
};
const oauth = {
  google:{authorize:'https://accounts.google.com/o/oauth2/v2/auth',token:'https://oauth2.googleapis.com/token',scope:'https://www.googleapis.com/auth/drive.file'},
  feishu:{authorize:'https://accounts.feishu.cn/open-apis/authen/v1/authorize',token:'https://open.feishu.cn/open-apis/authen/v2/oauth/token',scope:'docx:document offline_access'}
};
function safeLink(provider, value){
  const url=new URL(value);
  if(url.protocol!=='https:'||url.username||url.password||!services[provider]?.hosts.some(h=>url.hostname===h||url.hostname.endsWith('.'+h))) throw new Error('文档服务返回了未知域名');
  return url.href;
}
async function json(url,options={}){
  const response=await fetch(url,{...options,redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!response.ok) throw new Error('文档服务 HTTP '+response.status);
  const result=await response.json();
  if(result.code && result.code!==0 || result.error) throw new Error('文档服务未确认请求，请检查应用权限和账号');
  return result;
}
const post=(body,headers={})=>({method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
const bearer=token=>({Authorization:'Bearer '+token});
async function exchange(id, values){
  const token = await json(oauth[id].token,id==='google'?{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(values)
  }:post(values));
  if(!token.access_token)throw new Error('授权未返回用户令牌');
  return {token:token.access_token,refresh:token.refresh_token,expires:Date.now()+1000*(token.expires_in||3600)};
}
async function authorize(id, account, open){
  const spec=oauth[id], state=crypto.randomBytes(24).toString('hex'),verifier=crypto.randomBytes(48).toString('base64url');
  let receive;
  const code=new Promise((resolve,reject)=>{receive={resolve,reject};});
  const server=http.createServer((req,res)=>{
    const callback=new URL(req.url,'http://127.0.0.1');
    if(callback.pathname!=='/callback'||callback.searchParams.get('state')!==state){
      res.writeHead(400).end('Invalid callback');return;
    }
    const authCode=callback.searchParams.get('code');
    res.writeHead(200,{'Content-Type':'text/plain; charset=utf-8'}).end('请返回 TopMeeting 查看连接结果。');
    if(authCode)receive.resolve(authCode);else receive.reject(new Error('用户取消授权'));
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(id==='feishu'?39427:0,'127.0.0.1',resolve);});
  const redirect='http://127.0.0.1:'+server.address().port+'/callback';
  const timer=setTimeout(()=>receive.reject(new Error('授权等待超时')),180000);
  try {
    const params={client_id:account.clientId,response_type:'code',redirect_uri:redirect,state,scope:spec.scope,
      code_challenge:crypto.createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256'};
    if(id==='google')Object.assign(params,{access_type:'offline',prompt:'consent'});
    await open(spec.authorize+'?'+new URLSearchParams(params));
    return await exchange(id,{client_id:account.clientId,client_secret:account.secret||'',grant_type:'authorization_code',
      code:await code,redirect_uri:redirect,code_verifier:verifier});
  }finally{clearTimeout(timer);server.close();}
}
async function tokenFor(id, account, save){
  if(!oauth[id] || Date.now()<account.expires-60000)return account.token;
  if(!account.refresh)throw new Error('授权已到期，请重新绑定账号');
  const result=await exchange(id,{grant_type:'refresh_token',refresh_token:account.refresh,client_id:account.clientId,client_secret:account.secret||''});
  Object.assign(account,{...result,refresh:result.refresh||account.refresh});await save();return account.token;
}
async function dingToken(account){
  const response=await json('https://api.dingtalk.com/v1.0/oauth2/accessToken',post({appKey:account.clientId,appSecret:account.secret}));
  if(!response.accessToken)throw new Error('钉钉应用授权失败');
  return response.accessToken;
}
async function tencentSession(token){
  const headers={Authorization:token,'Content-Type':'application/json',Accept:'application/json, text/event-stream'};
  let nextId=0;
  async function rpc(method,params={},notify=false){
    const packet={jsonrpc:'2.0',method,params};
    if(!notify)packet.id=++nextId;
    const res=await fetch('https://docs.qq.com/openapi/mcp',{method:'POST',headers,body:JSON.stringify(packet),redirect:'error',signal:AbortSignal.timeout(30000)});
    if(!res.ok)throw new Error('腾讯文档 HTTP '+res.status);
    if(res.headers.get('mcp-session-id'))headers['Mcp-Session-Id']=res.headers.get('mcp-session-id');
    if(notify){await res.body?.cancel();return;}
    const text=await res.text();
    const reply=res.headers.get('content-type')?.includes('event-stream')?
      text.split(/\r?\n/).filter(l=>l.startsWith('data:')).map(l=>JSON.parse(l.slice(5))).find(v=>v.id===packet.id):JSON.parse(text);
    if(!reply || reply.error || reply.result?.isError)throw new Error('腾讯文档接口未确认操作');
    return reply.result;
  }
  const init=await rpc('initialize',{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'TopMeeting',version:'0.13.0'}});
  headers['MCP-Protocol-Version']=init.protocolVersion;
  await rpc('notifications/initialized',{},true);
  let cursor, tools=[];
  do {const page=await rpc('tools/list',cursor?{cursor}:{});tools.push(...page.tools);cursor=page.nextCursor;}while(cursor);
  const tool=tools.find(t=>['create_smartcanvas_by_markdown','create_smartcanvas_by_mdx'].includes(t.name));
  if(!tool)throw new Error('腾讯账号未开放智能文档创建工具');
  return async title=>{
    const properties=tool.inputSchema.properties||{},args={};
    for(const key of Object.keys(properties)){
      if(/^(title|name|doc_name|file_name)$/.test(key))args[key]=title;
      if(/^(markdown|mdx|content|markdown_content)$/.test(key))args[key]='# '+title+'\n';
    }
    if(!Object.keys(args).length||(tool.inputSchema.required||[]).some(k=>!(k in args)))throw new Error('腾讯文档工具参数已变化，请更新客户端');
    const result=await rpc('tools/call',{name:tool.name,arguments:args});
    const link=JSON.stringify(result).match(/https:\/\/docs\.qq\.com\/[\w/?=.%&-]+/i)?.[0];
    if(!link)throw new Error('腾讯文档未返回可打开的链接');
    return link;
  };
}
async function bindAccount(id,settings,open){
  if(!services[id])throw new Error('未知文档服务');
  const account={};for(const key of ['clientId','secret','token','space','parent','operator'])account[key]=String(settings[key]||'').trim();
  if(oauth[id]){
    if(!account.clientId)throw new Error('请填写已注册的桌面应用 Client ID');
    Object.assign(account,await authorize(id,account,open));
    if(id==='feishu'){
      const user=await json('https://open.feishu.cn/open-apis/authen/v1/user_info',{headers:bearer(account.token)});
      account.label=user.data?.name||account.clientId;
    }else account.label=account.clientId;
  }else if(id==='notion'){
    if(!account.parent)throw new Error('请填写已共享给集成的父页面 ID');
    const me=await json('https://api.notion.com/v1/users/me',{headers:{...bearer(account.token),'Notion-Version':'2022-06-28'}});
    account.label=me.name||'Notion 集成';
  }else if(id==='ding'){
    if(!account.space||!account.operator)throw new Error('请填写空间 ID 和操作人 Union ID');
    await dingToken(account);account.label=account.clientId;
  }else{await tencentSession(account.token);account.label='腾讯文档个人授权';}
  return account;
}
async function createDocument(id,account,title,save){
  let url;
  if(id==='feishu'){
    const token=await tokenFor(id,account,save);
    const result=await json('https://open.feishu.cn/open-apis/docx/v1/documents',post({title},bearer(token)));
    const doc=result.data?.document?.document_id;
    if(!doc)throw new Error('飞书未返回文档 ID');
    url='https://www.feishu.cn/docx/'+encodeURIComponent(doc);
  }else if(id==='google'){
    const token=await tokenFor(id,account,save);
    const doc=await json('https://docs.googleapis.com/v1/documents',post({title},bearer(token)));
    if(!doc.documentId)throw new Error('Google Docs 未返回文档 ID');
    url='https://docs.google.com/document/d/'+encodeURIComponent(doc.documentId)+'/edit';
  }else if(id==='notion'){
    const doc=await json('https://api.notion.com/v1/pages',post({parent:{page_id:account.parent},properties:{title:{type:'title',title:[{type:'text',text:{content:title}}]}}},{...bearer(account.token),'Notion-Version':'2022-06-28'}));
    url=doc.url;
  }else if(id==='ding'){
    const token=await dingToken(account);
    const doc=await json('https://api.dingtalk.com/v1.0/doc/workspaces/'+encodeURIComponent(account.space)+'/docs',post({name:title,docType:'alidoc',operatorId:account.operator,...(account.parent?{parentNodeId:account.parent}:{})},{'x-acs-dingtalk-access-token':token}));
    url=doc.url;
  }else{url=await (await tencentSession(account.token))(title);}
  return safeLink(id,url);
}
module.exports={services,safeLink,bindAccount,createDocument};
