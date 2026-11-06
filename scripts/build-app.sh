#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
sparkle="$PWD/.build/sparkle-2.10.1"
mkdir -p "$sparkle"
archive="$sparkle/Sparkle-2.10.1.tar.xz"
if [[ ! -f "$archive" ]]; then
    curl -fLsS --retry 2 https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$archive.partial"
    mv "$archive.partial" "$archive"
fi
print -r -- "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  $archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$sparkle"
swift build -c release -Xswiftc -F -Xswiftc "$sparkle" -Xlinker -F -Xlinker "$sparkle" \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'
mkdir -p "$PWD/dist"
stage=$(mktemp -d "$PWD/dist/.build-XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
APP="$stage/TopMeeting.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
ditto "$sparkle/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
./scripts/bundle-macos-runtimes.sh "$APP/Contents/Resources"
cp packages/documents/macos-bridge.cjs packages/documents/document-services.cjs "$APP/Contents/Resources/DocumentsRuntime/"
ICONSET="$PWD/.build/TopMeeting.iconset"
mkdir -p "$ICONSET"
swift scripts/build-icon.swift "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    if [[ "$size" != 512 ]]; then
        sips -z "$double" "$double" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/TopMeeting.icns"
mkdir -p "$APP/Contents/Resources/voice_engine/models"
cp voice_engine/THIRD_PARTY.md voice_engine/model-checksums.txt "$APP/Contents/Resources/voice_engine/"
rsync -a --exclude '__pycache__' voice_engine/engine.py "$APP/Contents/Resources/voice_engine/"
cp voice_engine/models/embedding.onnx "$APP/Contents/Resources/voice_engine/models/"
mkdir -p "$APP/Contents/Resources/voice_engine/models/sherpa-onnx-pyannote-segmentation-3-0"
cp voice_engine/models/sherpa-onnx-pyannote-segmentation-3-0/model.onnx voice_engine/models/sherpa-onnx-pyannote-segmentation-3-0/LICENSE "$APP/Contents/Resources/voice_engine/models/sherpa-onnx-pyannote-segmentation-3-0/"
mkdir -p "$APP/Contents/Resources/Feishu"
cp .feishu-runtime/node_modules/@larksuite/cli/bin/lark-cli "$APP/Contents/Resources/Feishu/"
cp .feishu-runtime/node_modules/@larksuite/cli/LICENSE "$APP/Contents/Resources/Feishu/"
cp .build/release/TopMeeting "$APP/Contents/MacOS/TopMeeting"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>TopMeeting.icns</string>
<key>CFBundleName</key><string>TopMeeting</string>
<key>CFBundleDisplayName</key><string>TopMeeting</string>
<key>CFBundleIdentifier</key><string>com.topmeeting.mac</string>
<key>CFBundleExecutable</key><string>TopMeeting</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.15.0</string>
<key>CFBundleVersion</key><string>22</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/frontitle/TopMeeting/main/docs/updates/macos-ARCH.xml</string>
<key>SUPublicEDKey</key><string>59Q0D6Qo1KWQKN5dGg+OZDk83WHDlX4p6FGm00oFBbc=</string>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSMicrophoneUsageDescription</key><string>录制会议声音，并在本机生成会议实录。</string>
<key>NSSpeechRecognitionUsageDescription</key><string>使用本机语音识别生成实时字幕。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
sed -i '' "s/macos-ARCH.xml/macos-$(uname -m).xml/" "$APP/Contents/Info.plist"
python3 scripts/check-macos-runtime.py "$APP" --strip-build-rpaths
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
# Atomically exchange complete bundles so a failed build preserves the working app.
python3 - "$APP" "$PWD/dist/TopMeeting.app" <<'PYTHON'
import ctypes, os, sys
source, target = map(os.fsencode, sys.argv[1:])
if os.path.exists(target):
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(source, target, 2):  # RENAME_SWAP on Darwin
        raise OSError(ctypes.get_errno(), "Could not replace application")
else:
    os.rename(source, target)
PYTHON
APP="$PWD/dist/TopMeeting.app"
# In-place builds replace files inside Contents without changing the bundle
# directory timestamp that Spotlight and IconServices use for invalidation.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
mdimport -i "$APP"
print "Built: $APP"
