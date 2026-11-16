#!/usr/bin/env bash
set -euo pipefail

app_dir=${1:?usage: $0 APP_DIR}
renderer="$app_dir/out/renderer/assets/js/pages/browserLikeWindow-DO6waaa5.js"
original='s.jsx(se,{isWin:le,userInfo:m'
patched='s.jsx(se,{isWin:!0,userInfo:m'

[[ -f "$renderer" ]] || { printf '未找到 renderer bundle：%s\n' "$renderer" >&2; exit 1; }

node - "$renderer" "$original" "$patched" <<'NODE'
const fs = require('node:fs')

const [file, original, patched] = process.argv.slice(2)
const source = fs.readFileSync(file, 'utf8')
const originals = source.split(original).length - 1
const patches = source.split(patched).length - 1

if (originals === 1) {
  fs.writeFileSync(file, source.replace(original, patched))
} else if (!(originals === 0 && patches === 1)) {
  throw new Error(`renderer controls anchor expected once, found ${originals} original and ${patches} patched`)
}
NODE
