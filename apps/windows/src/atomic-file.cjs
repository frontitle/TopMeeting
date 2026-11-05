const fs=require('node:fs/promises');
const {randomUUID}=require('node:crypto');

async function replace(file, data) {
  const temporary = file + '.' + randomUUID() + '.tmp';
  try {
    await fs.writeFile(temporary, data, {flag:'wx', mode:0o600, flush:true});
    await fs.rename(temporary, file);
  } finally { await fs.rm(temporary, {force:true}); }
}

module.exports={replace};
