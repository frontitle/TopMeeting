#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
npm install --prefix .feishu-runtime --save-exact @larksuite/cli@1.0.98
.feishu-runtime/node_modules/.bin/lark-cli --version
