const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createDocument,safeLink}=require('../src/document-services.cjs');

test('meeting links come from the selected provider',()=>{
  assert.throws(()=>safeLink('google','https://docs.google.com.attacker.example/x'));
  assert.throws(()=>safeLink('tencent','https://user@docs.qq.com/document/a'));
  assert.equal(safeLink('ding','https://alidocs.dingtalk.com/i/doc'),'https://alidocs.dingtalk.com/i/doc');
});

test('create a document for each verified provider; no meeting audio or transcription gets sent',async t=>{
  const responses={
    'https://docs.googleapis.com/v1/documents':{documentId:'example'},
    'https://open.feishu.cn/open-apis/docx/v1/documents':{code:0,data:{document:{document_id:'example'}}},
    'https://api.notion.com/v1/pages':{url:'https://www.notion.so/example'},
    'https://api.dingtalk.com/v1.0/oauth2/accessToken':{accessToken:'fixture'},
    'https://api.dingtalk.com/v1.0/doc/workspaces/demo/docs':{url:'https://alidocs.dingtalk.com/i/example'}
  };
  let writes=0;
  t.mock.method(global,'fetch',async(url,request)=>{
    const body=JSON.parse(request.body);
    if(url==='https://docs.qq.com/openapi/mcp'){
      const results={initialize:{protocolVersion:'2025-03-26'},'tools/list':{tools:[{name:'create_smartcanvas_by_markdown',inputSchema:{properties:{markdown:{},title:{}},required:['markdown']}}]},
        'tools/call':{content:[{text:'https://docs.qq.com/doc/example'}]}};
      if(body.method==='notifications/initialized')return new Response(null,{status:202});
      if(body.method==='tools/call'){assert.match(body.params.arguments.markdown,/Fixture/);writes++;}
      return Response.json({jsonrpc:'2.0',id:body.id,result:results[body.method]});
    }
    assert.ok(responses[url],url);
    if(url.includes('/pages'))assert.equal(body.parent.page_id,'parent');
    if(!url.endsWith('/accessToken'))writes++;
    return Response.json(responses[url]);
  });
  for(const id of ['google','notion','feishu','ding','tencent']){
    const url=await createDocument(id,{expires:Date.now()+3600000,token:'fixture',parent:'parent',space:'demo'},'Fixture',async()=>{});
    assert.equal(safeLink(id,url),url);
  }
  assert.equal(writes,5);
});
