const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {RecordingFile}=require('../src/recording-file.cjs');

test('partial writes and a lost IPC acknowledgement resume without duplicate audio',async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'topmeeting-audio-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  const target=path.join(dir,'capture.webm');
  const recording=new RecordingFile(target);
  const head=Uint8Array.of(4,5),tail=Uint8Array.of(6,7,8);
  await assert.rejects(recording.write(head,0));
  await fs.writeFile(target,'');
  await recording.write(head,0);
  // The OS wrote the first byte before returning a failure for the rest of the chunk.
  await fs.appendFile(target,tail.slice(0,1));
  await recording.write(tail,2);
  await recording.write(tail,2);
  await assert.rejects(recording.write(tail,8));
  assert.deepEqual(await fs.readFile(target),Buffer.from([4,5,6,7,8]));
});
