const crypto = require('node:crypto');
function endpoint(base, suffix) {
  const url = new URL(base);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('请输入不带凭据、查询参数的 HTTP(S) 服务地址');
  url.pathname = url.pathname.replace(/\/+$/, '').replace(/\/(chat\/completions|audio\/transcriptions)$/, '');
  if (!url.pathname.endsWith('/v1')) url.pathname += '/v1';
  url.pathname += '/' + suffix; return url.href;
}
function summaryInput(meeting, config) {
  const content = meeting.lines.map(l=>`${l.speaker || '未标记'}：${l.text}`).join('\n');
  if (!content.trim()) throw new Error('请先转写录音或添加实录');
  const system = config.language === 'en' ? 'Write meeting notes in English with sections Summary, Topics, Decisions, Action items, Open questions. Distinguish suggestions from decisions. Never invent owners, deadlines or facts.' : '请用中文生成结构化会议纪要，包含核心摘要、议题、明确决策、待办、待确认问题。区分建议与决定，不编造责任人、日期或事实。';
  const body = {model:config.model,stream:true,messages:[{role:'system',content:system},{role:'user',content:JSON.stringify({title:meeting.title,transcript:content,context:meeting.context || ''})}]};
  if (config.kind === 'openclaw') body.user = `topmeeting:${meeting.id}:notes`;
  const signature = crypto.createHash('sha256').update(JSON.stringify([config.base,body])).digest('hex');
  return {body,signature};
}
async function readSSE(response, delta) {
  if (!response.ok) throw new Error(`模型服务 HTTP ${response.status}`);
  let pending='',result='',done=false; const decoder=new TextDecoder();
  function line(value) {
    if (!value.startsWith('data:')) return;
    const data=value.slice(5).trim();
    if(data==='[DONE]'){done=true;return;}
    if(!data) return;
    const parsed=JSON.parse(data); if(parsed.error) throw new Error('模型服务返回错误');
    const text=parsed.choices?.[0]?.delta?.content;
    if(typeof text==='string'){result+=text;delta(text);}
  }
  for await (const chunk of response.body) {
    pending+=decoder.decode(chunk,{stream:true});
    let i; while((i=pending.indexOf('\n'))>=0){line(pending.slice(0,i).replace(/\r$/,''));pending=pending.slice(i+1);}
  }
  pending+=decoder.decode(); if(pending.trim()) line(pending);
  if(!done || !result.trim()) throw new Error('模型输出未完整结束，原纪要已保留');
  return result;
}
module.exports={endpoint,summaryInput,readSSE};
