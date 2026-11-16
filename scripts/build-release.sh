#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
page=https://jianghu.taobao.com/detail/47301_28562306
output_dir=${OUTPUT_DIR:-$root/dist}
work_dir=${WORK_DIR:-$root/work}

resolve_taobao_release() {
  curl -fsSL --max-time 30 "$page" |
    grep -oE 'https://tblifecdn\.taobao\.com/taobaopc/shop/win10/taobao-setup-win-x64-[0-9.]+\.exe' | head -1
}

if [[ "${1:-}" == --version-only ]]; then
  taobao_url=$(resolve_taobao_release)
  [[ -n "$taobao_url" ]] || { printf '无法从官方更新记录页解析出客户端安装包\n' >&2; exit 1; }
  taobao_version=${taobao_url##*-}
  printf '%s\n' "${taobao_version%.exe}"
  exit 0
fi

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || { printf '缺少工具：%s\n' "$cmd" >&2; exit 1; }
  done
}

fetch() {
  [[ -f "$2" ]] && return
  mkdir -p "$(dirname "$2")"
  printf '下载 %s\n' "$1" >&2
  curl -fL --retry 3 --max-time 600 -o "$2.part" "$1"
  mv "$2.part" "$2"
}

require 7z curl jq node npx sha256sum tar zstd
mkdir -p "$root/downloads" "$work_dir" "$output_dir"

taobao_url=$(curl -fsSL --max-time 30 "$page" |
  grep -oE 'https://tblifecdn\.taobao\.com/taobaopc/shop/win10/taobao-setup-win-x64-[0-9.]+\.exe' | head -1)
[[ -n "$taobao_url" ]] || { printf '无法从官方更新记录页解析出客户端安装包\n' >&2; exit 1; }
taobao_version=${taobao_url##*-}
taobao_version=${taobao_version%.exe}
installer="$root/downloads/taobao-setup-win-x64-$taobao_version.exe"
fetch "$taobao_url" "$installer"

rm -rf "$work_dir/installer" "$work_dir/windows" "$work_dir/electron" "$work_dir/app" "$work_dir/better-sqlite3" "$work_dir/vec"
mkdir -p "$work_dir/installer" "$work_dir/windows" "$work_dir/electron" "$work_dir/app" "$work_dir/better-sqlite3" "$work_dir/vec"
7z x -y "-o$work_dir/installer" "$installer" '$PLUGINSDIR/app-64.7z' >/dev/null
7z x -y "-o$work_dir/windows" "$work_dir/installer/\$PLUGINSDIR/app-64.7z" >/dev/null
npx --yes @electron/asar@4.3.2 extract "$work_dir/windows/resources/app.asar" "$work_dir/app"
electron_version=$(node -p "require('$work_dir/app/package.json').electronVersions.default")
electron_version=${electron_version#v}
better_version=$(node -p "require('$work_dir/app/node_modules/better-sqlite3/package.json').version")
vec_version=$(node -p "require('$work_dir/app/node_modules/sqlite-vec/package.json').optionalDependencies['sqlite-vec-linux-x64']")
[[ -n "$electron_version" && -n "$better_version" && -n "$vec_version" ]] || { printf '无法从官方客户端包解析 Electron 或 native 依赖版本\n' >&2; exit 1; }

electron_zip="$root/downloads/electron-v$electron_version-linux-x64.zip"
fetch "https://github.com/electron/electron/releases/download/v$electron_version/electron-v$electron_version-linux-x64.zip" "$electron_zip"
(
  cd "$root/downloads"
  curl -fsSL --max-time 30 "https://github.com/electron/electron/releases/download/v$electron_version/SHASUMS256.txt" |
    grep "[ *]electron-v$electron_version-linux-x64.zip\$" | sha256sum --check --status
) || { printf 'Electron 包校验失败\n' >&2; exit 1; }
7z x -y "-o$work_dir/electron" "$electron_zip" >/dev/null
chmod +x "$work_dir/electron/electron"

headers="$root/downloads/electron-v$electron_version-headers.tar.gz"
fetch "https://artifacts.electronjs.org/headers/dist/v$electron_version/node-v$electron_version-headers.tar.gz" "$headers"
abi=$(tar -xOzf "$headers" node_headers/include/node/node_version.h | tr -d '\r' |
  sed -nE 's/^#define NODE_MODULE_VERSION ([0-9]+)$/\1/p' | head -1)
[[ -n "$abi" ]] || { printf '无法从 Electron %s 官方 headers 解析 NODE_MODULE_VERSION\n' "$electron_version" >&2; exit 1; }
printf '客户端 %s，Electron %s (ABI %s)，better-sqlite3 %s，sqlite-vec %s\n' \
  "$taobao_version" "$electron_version" "$abi" "$better_version" "$vec_version" >&2

"$root/patch/apply-renderer.sh" "$work_dir/app"

vec_tar="$root/downloads/sqlite-vec-linux-x64-$vec_version.tgz"
fetch "https://registry.npmjs.org/sqlite-vec-linux-x64/-/sqlite-vec-linux-x64-$vec_version.tgz" "$vec_tar"
tar -xzf "$vec_tar" -C "$work_dir/vec" --strip-components=1
mkdir -p "$work_dir/app/node_modules/sqlite-vec-linux-x64"
cp -a "$work_dir/vec/." "$work_dir/app/node_modules/sqlite-vec-linux-x64/"

better_archive="$root/downloads/better-sqlite3-v$better_version-electron-v$abi-linux-x64.tar.gz"
fetch "https://github.com/WiseLibs/better-sqlite3/releases/download/v$better_version/$(basename "$better_archive")" "$better_archive"
tar -xzf "$better_archive" -C "$work_dir/better-sqlite3"
better_binary="$work_dir/better-sqlite3/build/Release/better_sqlite3.node"
[[ -f "$better_binary" ]] || { printf '未找到 better-sqlite3 %s 的 Electron ABI %s Linux prebuild\n' "$better_version" "$abi" >&2; exit 1; }
mkdir -p "$work_dir/app/node_modules/better-sqlite3/build/Release"
cp "$better_binary" "$work_dir/app/node_modules/better-sqlite3/build/Release/better_sqlite3.node"

npx --yes @electron/asar@4.3.2 pack "$work_dir/app" "$work_dir/windows/resources/linux-app.asar" --unpack-dir node_modules/sqlite-vec-linux-x64
rm -f "$work_dir/windows/resources/app.asar"
mv "$work_dir/windows/resources/linux-app.asar" "$work_dir/windows/resources/app.asar"
rm -rf "$work_dir/windows/resources/app.asar.unpacked"
cp -a "$work_dir/windows/resources/linux-app.asar.unpacked" "$work_dir/windows/resources/app.asar.unpacked"

payload="$output_dir/taobao-linux-$taobao_version-electron-$electron_version-x86_64.tar.zst"
rm -f "$payload" "$payload.sha256" "$payload.size"
mkdir -p "$work_dir/payload/electron"
cp -a "$work_dir/electron/." "$work_dir/payload/electron/"
cp "$work_dir/windows/resources/app.asar" "$work_dir/payload/app.asar"
cp -a "$work_dir/windows/resources/app.asar.unpacked" "$work_dir/payload/app.asar.unpacked"
tar -C "$work_dir/payload" -cf - electron app.asar app.asar.unpacked |
  zstd -T0 -19 -o "$payload"
sha256sum "$payload" > "$payload.sha256"
stat -c '%s' "$payload" > "$payload.size"
jq -n \
  --arg version "$taobao_version" \
  --arg electron "$electron_version" \
  --arg payload "$(basename "$payload")" \
  --arg sha256 "$(cut -d' ' -f1 "$payload.sha256")" \
  --argjson size "$(cat "$payload.size")" \
  '{version:$version,electron:$electron,payload:$payload,sha256:$sha256,size:$size}' \
  > "$output_dir/taobao-linux-$taobao_version.json"
printf '生成 %s\n' "$payload" >&2
