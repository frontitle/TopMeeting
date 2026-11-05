class MeetingPCM extends AudioWorkletProcessor {
  constructor() {
    super();
    this.buffer=new Float32Array(4000);
    this.length=0;
    this.port.onmessage=({data})=>{
      if(data==='flush'){
        if(this.length) this.port.postMessage(this.buffer.slice(0,this.length));
        this.length=0;
        this.port.postMessage('flushed');
      }
    };
  }
  process(inputs) {
    const samples=inputs[0]?.[0];
    if(samples) {
      for(const value of samples) {
        this.buffer[this.length++]=value;
        if(this.length===this.buffer.length){
          this.port.postMessage(this.buffer);
          this.length=0;
        }
      }
    }
    return true;
  }
}
registerProcessor('meeting-pcm',MeetingPCM);
