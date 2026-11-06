#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP="$PWD/dist/TopMeeting.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/DocumentsRuntime"
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)'
cp -L "$(command -v node)" "$APP/Contents/Resources/DocumentsRuntime/node"
NODE_PREFIX=$(node -p 'require("node:path").resolve(require("node:fs").realpathSync(process.execPath),"../..")')
if [[ -f "$NODE_PREFIX/LICENSE" ]]; then
    cp "$NODE_PREFIX/LICENSE" "$APP/Contents/Resources/DocumentsRuntime/NODE-LICENSE"
else
    curl -fsSL --retry 2 "https://raw.githubusercontent.com/nodejs/node/$(node -p 'process.version')/LICENSE" -o "$APP/Contents/Resources/DocumentsRuntime/NODE-LICENSE"
fi
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
rsync -a .voice-runtime/ "$APP/Contents/Resources/VoiceRuntime/"
# Materialize the interpreter: an absolute symlink outside an app bundle fails
# strict signature verification. Python's standard library/framework are still
# a documented local-development dependency.
cp -L .voice-runtime/bin/python3.13 .build/voice-python3.13
rm "$APP/Contents/Resources/VoiceRuntime/bin/python3.13"
cp .build/voice-python3.13 "$APP/Contents/Resources/VoiceRuntime/bin/python3.13"
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
<key>CFBundleShortVersionString</key><string>0.14.0</string>
<key>CFBundleVersion</key><string>20</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSMicrophoneUsageDescription</key><string>录制会议声音，并在本机生成会议实录。</string>
<key>NSSpeechRecognitionUsageDescription</key><string>使用本机语音识别生成实时字幕。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built: $APP"
