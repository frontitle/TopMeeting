const { spawn } = require('node:child_process');
const path = require('node:path');
const readline = require('node:readline');

class LocalSpeech {
  constructor(resources, data, onEvent) {
    this.python = path.join(resources, 'speech', 'python.exe');
    this.worker = path.join(resources, 'speech', 'worker.py');
    this.models = path.join(data, 'models');
    this.profiles = path.join(data, 'voice-profiles.json');
    this.onEvent = onEvent;
    this.pending = new Map();
    this.identityWrites=Promise.resolve();
  }

  launch(mode, args = []) {
    const child = spawn(this.python, ['-u', this.worker, mode, this.models, this.profiles, ...args], {
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe']
    });
    child.stderr.resume();
    child.stdin.on('error', () => {}); // Exit handler rejects all pending commands.
    return child;
  }

  check() {
    const child=this.launch('check');
    return new Promise((resolve,reject)=>{
      let ready;
      readline.createInterface({input:child.stdout}).on('line',line=>{
        try { const event=JSON.parse(line); if(event.type==='modelStatus')ready=event.ready; } catch {}
      });
      child.once('error',reject);
      child.once('close',code=>code===0 && typeof ready==='boolean' ? resolve(ready) : reject(new Error('无法检查本地语音组件，请修复安装或先只录音')));
    });
  }

  async install() {
    if (this.installing) return this.installing;
    if (this.child) throw new Error('请在会议结束后安装模型');
    const child = this.launch('install');
    this.installing = new Promise((resolve, reject) => {
      let reason = '';
      readline.createInterface({input:child.stdout}).on('line', line => {
        try { const event=JSON.parse(line); if(event.type==='error') reason=event.message; if(event.type==='modelProgress')this.onEvent(event); } catch {}
      });
      child.once('error', reject);
      child.once('close', code => code===0 ? resolve() : reject(new Error(reason || '模型安装失败，请检查网络并重试')));
    }).finally(() => { this.installing=null; });
    return this.installing;
  }

  wait(type, timeout=60000) {
    if (this.pending.has(type)) throw new Error('本地引擎正在处理上一个请求');
    return new Promise((resolve,reject) => {
      const timer=setTimeout(()=>{this.pending.delete(type);reject(new Error('本地语音引擎响应超时'));this.child?.kill();},timeout);
      this.pending.set(type,{resolve:value=>{clearTimeout(timer);resolve(value);},reject:error=>{clearTimeout(timer);reject(error);}});
    });
  }

  async start(meeting) {
    await this.identityWrites;
    if(this.child || this.installing) throw new Error('本地语音引擎正忙');
    const ready=this.wait('ready');
    const child=this.launch('listen',[meeting.id,String(meeting.duration || 0)]);
    this.child=child;
    let reason='';
    const abort=error=>{
      for(const pending of this.pending.values()) pending.reject(error);
      this.pending.clear();
      if(this.child===child) this.child=null;
    };
    child.once('error',abort);
    child.once('close',code=>{
      abort(new Error(reason || '本地引擎已结束'));
      if(code) this.onEvent({type:'error',message:reason || '本地引擎意外退出，原音仍在保存'});
    });
    readline.createInterface({input:child.stdout}).on('line', line=>{
      try {
        const event=JSON.parse(line);
        if(event.type==='identityError'){
          this.pending.get('identity')?.reject(new Error(event.message));
          this.pending.delete('identity');
          return;
        }
        if(event.type==='error') reason=event.message;
        const pending=this.pending.get(event.type);
        if(pending){this.pending.delete(event.type);pending.resolve(event);}
        this.onEvent(event);
      } catch(error) { reason=error.message; child.kill(); }
    });
    await ready;
  }

  async command(cmd, payload, reply) {
    if(!this.child) throw new Error('本地语音引擎未运行');
    const received=this.wait(reply);
    this.child.stdin.write(JSON.stringify({cmd,...payload})+'\n');
    return received;
  }

  name(meeting, source, name, target) {
    const operation=this.identityWrites.then(()=>this.writeIdentity(meeting,source,name,target));
    this.identityWrites=operation.catch(()=>{});
    return operation;
  }

  async writeIdentity(meeting, source, name, target) {
    if(this.child) return this.command('name',{source,name,target},'identity');
    const child=this.launch('name',[meeting.id,source,name,...(target?[target]:[])]);
    return new Promise((resolve,reject)=>{
      let response;
      readline.createInterface({input:child.stdout}).on('line',line=>{try{response=JSON.parse(line);}catch{}});
      child.once('error',reject);
      child.once('close',code=>code===0 && response?.type==='identity' ? resolve(response) : reject(new Error(response?.message || '声纹标记失败')));
    });
  }
}
module.exports={LocalSpeech};
