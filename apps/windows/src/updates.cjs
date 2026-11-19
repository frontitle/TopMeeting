const semver=require('semver');
const repository='frontitle/TopMeeting';

function newestRelease(releases,current){
  const candidates=[];
  for(const release of releases){
    const match=/^windows-v(\d+\.\d+\.\d+)-preview\.1$/.exec(release.tag_name);
    if(release.draft || !match || !semver.valid(match[1]) || !semver.gt(match[1],current))continue;
    const version=match[1];
    const installer='TopMeeting-'+version+'-windows-x64-setup.exe';
    if(![installer,'latest.yml'].every(name=>release.assets.some(asset=>asset.name===name)))continue;
    candidates.push({version,tag:release.tag_name,installer});
  }
  return candidates.sort((a,b)=>semver.rcompare(a.version,b.version))[0];
}

function desktopUpdates({version, updater, notify, prepareInstall, releaseInstall}) {
  updater.autoDownload = false;
  updater.autoInstallOnAppQuit = false;
  updater.disableDifferentialDownload = true;
  let status = {phase: 'idle', version, action: 'check'};
  let working = false;

  function set(phase, action, details = {}) {
    status = {phase, action, version, ...details};
    notify(status);
  }

  function installFailed() {
    releaseInstall();
    set('installFailed', 'check');
  }

  updater.on('error', () => {
    // Check and download reject their promises. Launch failures arrive as events.
    if (status.phase === 'installing') installFailed();
  });
  updater.on('download-progress', ({percent}) => {
    if (status.phase === 'downloading') {
      set('downloading', null, {next: status.next, percent: Math.floor(percent)});
    }
  });

  async function check() {
    set('checking', null);
    const response = await fetch('https://api.github.com/repos/' + repository + '/releases?per_page=100', {
      headers: {Accept: 'application/vnd.github+json'},
      signal: AbortSignal.timeout(20000)
    });
    if (!response.ok) throw Error('Release lookup failed');
    const next = newestRelease(await response.json(), version);
    if (!next) {
      set('current', 'check');
      return;
    }

    updater.setFeedURL({provider: 'generic', url: 'https://github.com/' + repository + '/releases/download/' + next.tag + '/'});
    const result = await updater.checkForUpdates();
    const files = result?.updateInfo?.files;
    if (!result?.isUpdateAvailable || result.updateInfo.version !== next.version ||
        files?.length !== 1 || files[0].url !== next.installer || !files[0].sha512) {
      throw Error('Invalid installer metadata');
    }
    set('available', 'download', {next: next.version});
  }

  async function perform(action) {
    if (working || !action || status.action !== action) return status;
    working = true;
    const next = status.next;
    try {
      if (action === 'check') {
        await check();
      } else if (action === 'download') {
        set('downloading', null, {next, percent: 0});
        await updater.downloadUpdate();
        set('ready', 'install', {next});
      } else if (action === 'install' && await prepareInstall()) {
        set('installing', null, {next});
        updater.quitAndInstall(false, true);
      }
    } catch {
      if (action === 'download') set('downloadFailed', 'download', {next});
      else if (action === 'install') installFailed();
      else set('checkFailed', 'check');
    } finally {
      working = false;
    }
    return status;
  }
  return {perform, status: () => status};
}
module.exports = {desktopUpdates, newestRelease};
