#!/bin/zsh
set -euo pipefail
resources=$1
downloads="$PWD/.build/runtime-downloads"
mkdir -p "$downloads" "$resources/DocumentsRuntime"
case $(uname -m) in
    arm64) node_arch=arm64; digest=c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428 ;;
    x86_64) node_arch=x64; digest=efcc2b0db6f94bf53eddb038fe2b370277a042bd29e4f19b8f8e23598795b819 ;;
    *) print -u2 'Unsupported macOS architecture'; exit 1 ;;
esac
node_release="node-v22.23.4-darwin-$node_arch"
archive="$downloads/$node_release.tar.gz"
verify_node() { print -r -- "$digest  $1" | shasum -a 256 --check --status; }
if ! [[ -f "$archive" ]] || ! verify_node "$archive"; then
    partial=$(mktemp "$downloads/node.XXXXXXXX")
    trap 'rm -f "$partial"' EXIT
    curl -fLsS --retry 2 "https://nodejs.org/dist/v22.23.4/$node_release.tar.gz" -o "$partial"
    verify_node "$partial"
    mv "$partial" "$archive"
fi
tar -xOzf "$archive" "$node_release/bin/node" > "$resources/DocumentsRuntime/node"
chmod 755 "$resources/DocumentsRuntime/node"
tar -xOzf "$archive" "$node_release/LICENSE" > "$resources/DocumentsRuntime/NODE-LICENSE"

# Ship the relocatable CPython distribution, including its standard library.
export UV_PYTHON_INSTALL_DIR="$PWD/.build/portable-python"
uv python install --no-bin 3.13.13
interpreter=$(uv python find --no-project --managed-python 3.13.13)
prefix=$("$interpreter" -I -c 'import sys; print(sys.base_prefix)')
runtime="$resources/VoiceRuntime"
mkdir -p "$runtime/bin"
cp -L "$interpreter" "$runtime/bin/python3"
rsync -a --exclude site-packages --exclude __pycache__ --exclude '*.pyc' "$prefix/lib/" "$runtime/lib/"
uv pip install --python "$runtime/bin/python3" --only-binary=:all: --link-mode copy \
    --target "$runtime/lib/python3.13/site-packages" -r voice_engine/requirements.lock.txt
# Console wrappers contain build-machine shebangs. The app invokes the interpreter directly.
rm -rf "$runtime/lib/python3.13/site-packages/bin"
