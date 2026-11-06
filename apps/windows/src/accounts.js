const providerFields={
  feishu:[['clientId','飞书 TopMeeting 应用 App ID'],['secret','App Secret','password']],
  google:[['clientId','Google 桌面应用 Client ID'],['secret','Client Secret','password']],
  notion:[['token','Notion 内部集成 Token','password'],['parent','已与集成共享的父页面 ID']],
  ding:[['clientId','钉钉组织应用 AppKey'],['secret','AppSecret','password'],['space','知识库空间 ID'],['operator','操作人 Union ID'],['parent','父节点 ID（选填）']],
  tencent:[['token','腾讯文档个人 MCP Token','password']]
};
function fields(){
  const service=state.accounts.find(a=>a.id===$('service').value);
  if(!service)return;
  $('accountFields').replaceChildren();
  $('accountStatus').textContent=service.label?'已绑定 · '+service.label:'尚未绑定';
  $('autoDoc').checked=service.label?service.enabled:true;$('saveAuto').disabled=$('unlink').disabled=!service.label;
  for(const [key,label,type] of providerFields[service.id]){
    const field=document.createElement('label'),input=document.createElement('input');
    field.textContent=label;input.type=type||'text';input.dataset.key=key;input.autocomplete='off';field.append(input);$('accountFields').append(field);
  }
  $('accountMessage').textContent=service.id==='feishu'?'请使用你注册的飞书应用，在开放平台配置回调 http://127.0.0.1:39427/callback。授权页会显示该应用名称。':service.id==='tencent'?'从 docs.qq.com/open/auth/mcp.html 获取个人授权。':'';
}
$('accounts').onclick=()=>{
  $('service').replaceChildren();for(const a of state.accounts){const option=document.createElement('option');option.value=a.id;option.textContent=a.name;$('service').append(option);}
  const active=state.accounts.find(account=>account.enabled);
  if(active)$('service').value=active.id;
  fields();$('accountDialog').showModal();
};
$('closeAccounts').onclick=()=>$('accountDialog').close();$('service').onchange=fields;
async function accountAction(action){
  const buttons=Array.from($('accountDialog').querySelectorAll('button'));
  buttons.forEach(b=>b.disabled=true);$('service').disabled=true;
  const id=$('service').value;
  try{
    if(action==='bind'){
      const values=Object.fromEntries(Array.from($('accountFields').querySelectorAll('input'),i=>[i.dataset.key,i.value]));
      $('accountMessage').textContent='正在验证账号或等待浏览器授权…';
      state.accounts=await api.bindAccount(id,{...values,enabled:$('autoDoc').checked});
    }else state.accounts=await api.configureAccount(id,action==='unlink'?'disconnect':$('autoDoc').checked?'enable':'disable');
    fields();$('accountMessage').textContent='设置已保存';
  }catch(error){$('accountMessage').textContent=error.message;}
  finally{buttons.forEach(b=>b.disabled=false);$('service').disabled=false;const bound=state.accounts.some(a=>a.id===id && a.label);$('saveAuto').disabled=$('unlink').disabled=!bound;}
}
$('bindAccount').onclick=()=>accountAction('bind');$('saveAuto').onclick=()=>accountAction('save');$('unlink').onclick=()=>accountAction('unlink');
window.renderDocLinks=m=>{
  const area=$('doclinks');area.replaceChildren();if(!m)return;
  for(const [id,doc] of Object.entries(m.documents||{})){
    const name=state.accounts.find(a=>a.id===id)?.name||id;
    if(doc.url){const button=document.createElement('button');button.textContent='↗ '+name;button.onclick=()=>action(()=>api.openDocument(m.id,id));area.append(button);continue;}
    const status=document.createElement('span');status.textContent=name+' · '+(doc.status==='pending'?'建档中或待核对':(doc.message||'待核对'));area.append(status);
    const link=document.createElement('input');link.placeholder='已创建文档的链接';const attach=document.createElement('button');attach.textContent='关联';
    attach.onclick=()=>action(()=>api.recoverDocument(m.id,id,link.value,false));
    const retry=document.createElement('button');retry.textContent='已核对未创建，重试';retry.onclick=()=>action(()=>api.recoverDocument(m.id,id,'',true));area.append(link,attach,retry);
  }
};
