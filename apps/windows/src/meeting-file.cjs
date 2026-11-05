// One writer per application profile (the host also holds Electron's single-instance lock).
const fs = require('node:fs/promises');
const path = require('node:path');
const {replace}=require('./atomic-file.cjs');
const {randomUUID} = require('node:crypto');

function decode(text) {
  const meetings = JSON.parse(text);
  if (!Array.isArray(meetings) || meetings.some(m =>
    !m || typeof m.id !== 'string' || typeof m.title !== 'string' ||
    !Array.isArray(m.lines) || m.lines.some(line=>!line || typeof line.text!=='string') ||
    !Array.isArray(m.recordings) || m.recordings.some(file=>typeof file!=='string' || !/^[a-zA-Z0-9_-]+\.webm$/i.test(file)))) {
    throw new Error('会议文件格式无效');
  }
  return meetings;
}

async function read(file) {
  try { return await fs.readFile(file, 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

class MeetingFile {
  constructor(directory) {
    this.file = path.join(directory,'meetings.json');
    this.backup = path.join(directory,'meetings.previous.json');
    this.queue = Promise.resolve();
    this.last = null;
    this.ready = false;
  }

  async load() {
    const current = await read(this.file);
    let meetings;
    try { meetings = current === null ? null : decode(current); }
    catch { meetings = null; }
    if (meetings !== null) {
      this.last = current;
    } else {
      const previous = await read(this.backup);
      if (previous === null && current === null) meetings = [];
      else {
        if (previous === null) throw new Error('会议文件无法读取，已保留原件。请恢复备份后重新打开。');
        meetings = decode(previous);
        if (current !== null) await replace(this.file+'.unreadable-'+randomUUID(),current);
        await replace(this.file,previous);
        this.last = previous;
        this.recovered = true;
      }
    }
    this.ready = true;
    return meetings;
  }

  save(meetings) {
    if (!this.ready) return Promise.reject(new Error('会议资料尚未成功读取'));
    const next = JSON.stringify(meetings);
    const operation = this.queue.then(async()=>{
      if (next === this.last) return;
      if (await read(this.file) !== this.last) throw new Error('会议文件已在其他位置修改，请重新打开客户端');
      if (this.last !== null) await replace(this.backup,this.last);
      await replace(this.file,next);
      this.last = next;
    });
    // Return the failure to its caller, but let the next independent write retry.
    this.queue = operation.catch(()=>{});
    return operation;
  }
}
module.exports = {MeetingFile};
