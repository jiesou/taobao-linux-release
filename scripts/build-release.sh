#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
page=https://jianghu.taobao.com/detail/47301_28562306
output_dir=${OUTPUT_DIR:-$root/dist}
work_dir=${WORK_DIR:-$root/work}
better_version=${BETTER_SQLITE3_VERSION:-12.11.1}
better_abi=${BETTER_SQLITE3_ABI:-136}
vec_version=${SQLITE_VEC_VERSION:-0.1.9}

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

require 7z curl gh node npx sha256sum tar zstd
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
electron_zip="$root/downloads/electron-v$electron_version-linux-x64.zip"
fetch "https://github.com/electron/electron/releases/download/v$electron_version/electron-v$electron_version-linux-x64.zip" "$electron_zip"
(
  cd "$root/downloads"
  curl -fsSL --max-time 30 "https://github.com/electron/electron/releases/download/v$electron_version/SHASUMS256.txt" |
    grep "[ *]electron-v$electron_version-linux-x64.zip\$" | sha256sum --check --status
) || { printf 'Electron 包校验失败\n' >&2; exit 1; }
7z x -y "-o$work_dir/electron" "$electron_zip" >/dev/null
chmod +x "$work_dir/electron/electron"
"$root/patch/apply-renderer.sh" "$work_dir/app"

vec_tar="$root/downloads/sqlite-vec-linux-x64-$vec_version.tgz"
fetch "https://registry.npmjs.org/sqlite-vec-linux-x64/-/sqlite-vec-linux-x64-$vec_version.tgz" "$vec_tar"
tar -xzf "$vec_tar" -C "$work_dir/vec" --strip-components=1
mkdir -p "$work_dir/app/node_modules/sqlite-vec-linux-x64"
cp -a "$work_dir/vec/." "$work_dir/app/node_modules/sqlite-vec-linux-x64/"

better_archive="$root/downloads/better-sqlite3-v$better_version-electron-v$better_abi-linux-x64.tar.gz"
if [[ ! -f "$better_archive" ]]; then
  gh release download "v$better_version" -R WiseLibs/better-sqlite3 \
    --pattern "better-sqlite3-v$better_version-electron-v$better_abi-linux-x64.tar.gz" \
    --dir "$root/downloads" --clobber
fi
tar -xzf "$better_archive" -C "$work_dir/better-sqlite3"
better_binary="$work_dir/better-sqlite3/build/Release/better_sqlite3.node"
[[ -f "$better_binary" ]] || { printf '未找到 better-sqlite3 Electron/Linux prebuild\n' >&2; exit 1; }
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
printf 'version=%s\nelectron=%s\npayload=%s\nsha256=%s\nsize=%s\n' \
  "$taobao_version" "$electron_version" "$(basename "$payload")" \
  "$(cut -d' ' -f1 "$payload.sha256")" "$(cat "$payload.size")" \
  > "$output_dir/taobao-linux-$taobao_version.json"
printf '生成 %s\n' "$payload" >&2
