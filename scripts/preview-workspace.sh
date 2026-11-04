#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/ui-preview
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/TopMeeting/App.swift').read_text()
a=s.index('@main struct TopMeetingApp:'); b=s.index('struct Workspace:',a)
Path('.build/ui-preview/Workspace.swift').write_text(s[:a]+s[b:])
PY
sources=(Sources/TopMeeting/*.swift)
sources=(${sources:#Sources/TopMeeting/App.swift})
swiftc -parse-as-library "${sources[@]}" .build/ui-preview/Workspace.swift Tests/TopMeetingTests/WorkspacePreview.swift -o .build/ui-preview/render
.build/ui-preview/render "$@"
