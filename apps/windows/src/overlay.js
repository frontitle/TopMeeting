const wave=document.querySelector('#wave');
for(let i=0;i<22;i++)wave.append(document.createElement('i'));
let history=Array(22).fill(.05);
listening.onState(state=>{
  document.querySelector('#state').textContent=state.paused?'已暂停':'正在聆听';
  document.querySelector('#speaker').textContent=state.speaker||'';
  document.querySelector('#caption').textContent=Array.from(state.text||'…').slice(-41).join('');
  document.querySelector('time').textContent=[Math.floor(state.duration/60),Math.floor(state.duration%60)].map(v=>String(v).padStart(2,'0')).join(':');
  document.querySelector('button').textContent=state.paused?'▶':'Ⅱ';
  document.querySelector('button').ariaLabel=state.paused?'继续':'暂停';
  history=[...history.slice(1),state.paused?0:state.level];
  Array.from(wave.children).forEach((bar,i)=>bar.style.height=(3+19*Math.min(1,history[i]*5))+'px');
});
document.body.ondblclick=()=>listening.open();
document.querySelector('button').onclick=()=>listening.pause();
