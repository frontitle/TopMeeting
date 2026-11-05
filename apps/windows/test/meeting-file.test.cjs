const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const {MeetingFile}=require('../src/meeting-file.cjs');
const meeting=title=>[{id:'fixture',title,lines:[],recordings:[]}];
async function library(t){
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'topmeeting-file-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const file=new MeetingFile(root);await file.load();return file;
}
test('failed writes propagate to their caller and later queued saves can recover',async t=>{
  const file=await library(t);await file.save(meeting('one'));
  await fs.mkdir(file.backup);
  await assert.rejects(file.save(meeting('failed')));
  assert.equal(JSON.parse(await fs.readFile(file.file))[0].title,'one');
  await fs.rm(file.backup,{recursive:true});
  await Promise.all([file.save(meeting('two')),file.save(meeting('three'))]);
  assert.equal(JSON.parse(await fs.readFile(file.file))[0].title,'three');
  assert.equal(JSON.parse(await fs.readFile(file.backup))[0].title,'two');
});
test('invalid history is preserved and only a valid backup can restore it',async t=>{
  const file=await library(t);
  await file.save(meeting('older'));await file.save(meeting('newer'));
  await fs.writeFile(file.file,'broken');
  await assert.rejects(file.save(meeting('stale')));
  const recovered=new MeetingFile(path.dirname(file.file));
  assert.equal((await recovered.load())[0].title,'older');assert.ok(recovered.recovered);
  const retained=(await fs.readdir(path.dirname(file.file))).find(name=>name.includes('unreadable'));
  assert.equal(await fs.readFile(path.join(path.dirname(file.file),retained),'utf8'),'broken');
  await fs.rm(file.backup);await fs.writeFile(file.file,'broken again');
  const unavailable=new MeetingFile(path.dirname(file.file));
  await assert.rejects(unavailable.load());await assert.rejects(unavailable.save(meeting('empty')));
  assert.equal(await fs.readFile(file.file,'utf8'),'broken again');
});
