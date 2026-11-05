const test = require('node:test');
const assert = require('node:assert/strict');
const {bindAccount,createDocument} = require('../document-services.cjs');

for(const provider of ['google','feishu']){
  test(provider+' desktop authorization verifies callback state, identity and token refresh',async t=>{
    const network=global.fetch;
    let refreshes=0,saves=0;
    t.mock.method(global,'fetch',async(url,options)=>{
      if(String(url).includes('/userinfo'))return Response.json({email:'fixture@example.invalid'});
      if(String(url).includes('/user_info'))return Response.json({data:{name:'Fixture user'}});
      if(String(url).includes('/documents'))return Response.json(provider==='google'?{documentId:'fixture'}:{data:{document:{document_id:'fixture'}}});
      const values=provider==='google'?Object.fromEntries(options.body):JSON.parse(options.body);
      if(values.grant_type==='refresh_token'){
        assert.equal(values.refresh_token,'old-refresh');refreshes++;
        return Response.json({access_token:'renewed',refresh_token:'new-refresh',expires_in:3600});
      }
      assert.equal(values.code,'fixture-code');assert.ok(values.code_verifier);
      return Response.json({access_token:'fixture',refresh_token:'old-refresh',expires_in:3600});
    });
    const account=await bindAccount(provider,{clientId:'client',secret:'fixture'},async authorization=>{
      const params=new URL(authorization).searchParams;
      const callback=new URL(params.get('redirect_uri'));
      callback.searchParams.set('code','fixture-code');callback.searchParams.set('state','wrong');
      assert.equal((await network(callback)).status,400);
      callback.searchParams.set('state',params.get('state'));
      assert.equal((await network(callback)).status,200);
      assert.equal(params.get('code_challenge_method'),'S256');
    });
    assert.equal(account.label,provider==='google'?'fixture@example.invalid':'Fixture user');
    account.expires=0;
    const link=await createDocument(provider,account,'Fixture',async()=>saves++);
    assert.match(link,/fixture/);assert.equal(refreshes,1);assert.equal(saves,1);assert.equal(account.refresh,'new-refresh');
  });
}
test('an unsuccessful workspace binding never becomes a connected account',async t=>{
  t.mock.method(global,'fetch',async()=>new Response('',{status:401}));
  for(const provider of ['notion','ding','tencent']){
    await assert.rejects(()=>bindAccount(provider,{token:'invalid',space:'space',operator:'user',parent:'page'},()=>{}));
  }
});
