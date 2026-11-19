function paintUpdate(state) {
  const labels = {
    idle: '检查更新', checking: '检查中…', current: '重新检查', available: '下载更新',
    downloading: '正在下载', ready: '安装并重启', installing: '正在安装',
    checkFailed: '重新检查', downloadFailed: '重试下载', installFailed: '重新检查', portable: '检查更新'
  };
  const text = {
    available: '可更新至 ' + state.next, current: '当前已是最新版本',
    downloading: (state.percent || 0) + '%', ready: '更新已下载',
    checkFailed: '暂时无法检查更新', downloadFailed: '下载未完成',
    installFailed: '未能开始安装，请重新检查更新。',
    portable: '安装 setup.exe 版本后即可使用在线更新。'
  };
  $('updateInfo').textContent = 'TopMeeting ' + state.version + (text[state.phase] ? ' · ' + text[state.phase] : '');
  const button = $('updateAction');
  button.textContent = labels[state.phase];
  button.disabled = !state.action;
  button.onclick = () => action(async () => paintUpdate(await api.updateAction(state.action)));
}

api.onUpdateStatus(paintUpdate);
$('settings').addEventListener('click', () => action(async () => paintUpdate(await api.updateStatus())));
