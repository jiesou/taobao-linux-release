# Taobao Linux release builder

This repository builds the Linux payload used by the FlatPark package for Taobao Desktop.

The source application is the official Taobao Windows installer. The build downloads the official Linux Electron runtime, applies the Linux renderer/runtime patches in this repository, and replaces Windows native modules with Linux binaries:

- `sqlite-vec-linux-x64` `0.1.9`
- the official `better-sqlite3` Electron ABI 136 prebuild

The build does not compile Electron or native modules and does not run npm during Flatpak installation.

## Build

```bash
./scripts/build-release.sh
```

The script writes a versioned payload and checksum metadata under `dist/`. GitHub Actions runs the same script and publishes a versioned Release named `taobao-<taobao-version>`.

## FlatPark

The FlatPark registry package downloads the payload as one `extra-data` archive. Its `apply_extra.sh` only verifies and unpacks the already-built payload offline.

References:

- [FlatPark build repositories](https://github.com/flatpark/flatpark/blob/main/docs/packagers/basics.md#build-repositories)
- [FlatPark extra-data format](https://github.com/flatpark/flatpark/blob/main/docs/packagers/basics.md)
- [Electron releases](https://github.com/electron/electron/releases)
- [better-sqlite3 Electron prebuilds](https://github.com/WiseLibs/better-sqlite3/releases/tag/v12.11.1)
- [sqlite-vec releases](https://github.com/asg017/sqlite-vec/releases/tag/v0.1.9)
