# Taobao Linux release builder

This repository builds the Linux payload used by the FlatPark package for Taobao Desktop.

The source application is the official Taobao Windows installer. The build downloads the official Linux Electron runtime, applies the Linux renderer/runtime patches in this repository, and replaces Windows native modules with Linux binaries.

The build reads Electron, `better-sqlite3`, and `sqlite-vec` versions from the unpacked Taobao app. It reads Electron's `NODE_MODULE_VERSION` from the matching official Electron headers, then downloads the corresponding official Linux prebuilds. If a matching prebuild is unavailable, the build fails clearly rather than guessing or compiling a different ABI. It does not compile Electron or native modules and does not run npm during Flatpak installation. The Taobao version is resolved from the official update page on every CI run; unchanged versions are skipped unless a manual run sets `force=true`. No generated payload or installer is committed to this repository.

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
