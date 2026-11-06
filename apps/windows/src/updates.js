function paintUpdate(state){
  const labels={idle:'检查更新',checking:'检查中…',current:'重新检查',available:'下载更新',
    downloading:'正在下载',ready:'安装并重启',installing:'正在安装',failed:'重试',portable:'检查更新'};
  const text={available:'可更新至 '+state.next,ready:'更新已下载',failed:'更新失败，请检查网络后重试。',
    portable:'安装 setup.exe 版本后即可使用在线更新。',current:'当前已是最新版本',downloading:(state.percent||0)+'%'};
  $('updateInfo').textContent='TopMeeting '+state.version+(text[state.phase]?' · '+text[state.phase]:'');
  $('updateAction').textContent=labels[state.phase];
  $('updateAction').disabled=['checking','downloading','installing','portable'].includes(state.phase);
}
api.onUpdateStatus(paintUpdate);
$('settings').addEventListener('click',()=>action(async()=>paintUpdate(await api.updateStatus())));
$('updateAction').onclick=()=>action(async()=>paintUpdate(await api.updateAction()));
