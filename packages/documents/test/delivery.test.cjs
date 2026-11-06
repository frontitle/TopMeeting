const test=require('node:test');
const assert=require('node:assert/strict');
const Module=require('node:module');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');

// The Windows packaged suite covers DPAPI. Here only the platform boundary is substituted.
const original=Module._load;
let opened;
Module._load=function(id,...args){
  if(id==='electron')return {
    safeStorage:{isEncryptionAvailable:()=>true,encryptString:text=>Buffer.from(text),decryptString:bytes=>bytes.toString()},
    shell:{openExternal:async link=>{opened=link;}}
  };
  return original.call(this,id,...args);
};
const {DocumentStore}=require('../../../apps/windows/src/document-store.cjs');
Module._load=original;

test('a meeting creates one document and keeps an uncertain write for user reconciliation',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'topmeeting-doc-test-'));
  t.after(()=>fs.rm(directory,{recursive:true,force:true}));
  const meetings=[{id:'a',title:'Fixture A'},{id:'b',title:'Fixture B'}];
  const saved=[];
  const store=new DocumentStore(directory,id=>meetings.find(m=>m.id===id),async()=>saved.push(structuredClone(meetings)),()=>{});
  let attempts=0;
  t.mock.method(global,'fetch',async url=>{
    if(url.endsWith('/users/me'))return Response.json({name:'Fixture workspace'});
    attempts++;
    assert.ok(saved.at(-1).some(m=>m.documents?.notion?.status==='pending'));
    if(attempts===2)throw Error('Lost provider response');
    return Response.json({url:'https://www.notion.so/fixture'});
  });
  await store.bind('notion',{token:'fixture',parent:'parent',enabled:true});
  await Promise.all([store.start('a'),store.start('a')]);
  assert.equal(attempts,1);assert.equal(meetings[0].documents.notion.status,'ready');
  await store.open('a','notion');assert.equal(opened,'https://www.notion.so/fixture');
  await store.start('b');await store.start('b');
  assert.equal(meetings[1].documents.notion.status,'uncertain');assert.equal(attempts,2);
  await store.recover('b','notion','https://www.notion.so/recovered',false);
  assert.equal(meetings[1].documents.notion.url,'https://www.notion.so/recovered');
  await store.configure('notion','disconnect');
  const restarted=new DocumentStore(directory,()=>null,()=>{},()=>{});await restarted.load();
  assert.equal(restarted.public().find(a=>a.id==='notion').enabled,false);
});

test('switching the active workspace retains credentials and legacy ambiguous settings stay local',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'topmeeting-platform-'));
  t.after(()=>fs.rm(directory,{recursive:true,force:true}));
  const store=new DocumentStore(directory,()=>null,()=>{},()=>{});
  store.accounts={feishu:{label:'F',enabled:true},ding:{label:'D',enabled:true}};
  await store.save();
  await store.load();
  assert.equal(store.public().filter(a=>a.enabled).length,0);
  await store.configure('ding','enable');
  await store.configure('feishu','enable');
  await store.load();
  assert.deepEqual(store.public().filter(a=>a.enabled).map(a=>a.id),['feishu']);
  assert.equal(store.accounts.ding.label,'D');
});
