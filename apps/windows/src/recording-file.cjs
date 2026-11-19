const fs=require('node:fs/promises');

class RecordingFile {
  constructor(path){
    this.path=path;
    this.offset=0;
    this.lastOffset=-1;
  }

  async write(bytes,offset){
    if(!(bytes instanceof Uint8Array) || !bytes.length || bytes.length>20*1024*1024)throw new Error('音频块无效');
    if(!Number.isSafeInteger(offset) || offset<0)throw new Error('录音文件位置无效');
    if(offset===this.lastOffset && offset+bytes.length===this.offset)return;
    if(offset!==this.offset)throw new Error('录音文件位置已变化');
    const file=await fs.open(this.path,'r+');
    try{
      let written=0;
      while(written<bytes.length){
        const {bytesWritten}=await file.write(bytes,written,bytes.length-written,offset+written);
        if(!bytesWritten)throw new Error('原音写入未完成');
        written+=bytesWritten;
      }
    }finally{await file.close();}
    this.lastOffset=offset;
    this.offset+=bytes.length;
  }
}

module.exports={RecordingFile};
