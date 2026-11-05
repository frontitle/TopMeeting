const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {EncryptedSettings}=require('../src/encrypted-settings.cjs');
test('rebind preserves unreadable bytes before replacing the optional credential file',async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'meeting-credentials-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const file=path.join(root,'credentials.bin');
  const vault={isEncryptionAvailable:()=>true,encryptString:value=>Buffer.from(value),decryptString:bytes=>bytes.toString()};
  const settings=new EncryptedSettings(file,vault);
  await fs.writeFile(file,'broken-fixture');
  await assert.rejects(settings.load());
  assert.equal(await fs.readFile(file,'utf8'),'broken-fixture');
  await settings.save({model:'new'});
  assert.deepEqual(await settings.load(),{model:'new'});
  const backup=(await fs.readdir(root)).find(name=>name.includes('unreadable'));
  assert.equal(await fs.readFile(path.join(root,backup),'utf8'),'broken-fixture');
});
