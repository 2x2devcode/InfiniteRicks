# Android build notes (InfiniteRicks Wallet)

This guide describes how to build the **InfiniteRicks** Qt wallet APK for Android on **Ubuntu 22.04**, following the same Qt-for-Android approach used by [Blackcoin More](https://github.com/CoinBlack/blackcoin-more/blob/master/doc/build-android.md).

## Quick start

```bash
chmod +x compile-android.sh
./compile-android.sh
```

The script will:

1. Install required Ubuntu packages (JDK 11 for Gradle, JDK 17, build tools, etc.)
2. Download the Android SDK/NDK (into `~/.infinite-ricks/android-sdk` by default)
3. Install Qt 5.15.2 for Android via [aqtinstall](https://github.com/miurahr/aqtinstall)
4. Cross-compile OpenSSL, Berkeley DB, and Boost for the target ABI
5. Build the Qt wallet and package an APK with `androiddeployqt`

Output APK: `./android-build/InfiniteRicks-wallet-release-unsigned.apk` (override directory with `ANDROID_OUTPUT_DIR`).

The APK is **unsigned**; sign it before publishing to a store, or install on a test device with `adb install -r` (debug builds use the debug keystore automatically).

## Options

```bash
./compile-android.sh --abi arm64-v8a     # default (phones)
./compile-android.sh --abi armeabi-v7a   # older 32-bit ARM devices
./compile-android.sh --debug             # debug APK (signed with debug key)
./compile-android.sh --deps-only         # libraries only, no APK
./compile-android.sh --skip-deps         # reuse existing dependency prefix
```

## Requirements

- Ubuntu 22.04 (x86_64)
- ~12 GB free disk space (SDK + NDK + Qt + sources)
- Internet access for first-time dependency download
- `sudo` for installing apt packages

Minimum supported Android version: **API 24** (Android 7.0).  
Tested NDK: **r23.2** (same family as Blackcoin More CI).

## Project layout

| Path | Purpose |
|------|---------|
| `compile-android.sh` | Automated build script (like `compile-windows.sh`) |
| `src/qt/android/` | Android manifest, Gradle, Java activity |
| `InfiniteRicks-qt.pro` | `android { ... }` qmake block |

Wallet data on device is stored under the app private directory (`Context.getFilesDir()/.InfiniteRicks`), configured by `InfiniteRicksQtActivity.java`.

## Environment variables

| Variable | Default |
|----------|---------|
| `ANDROID_DEPS_DIR` | `~/.infinite-ricks/android-deps-<abi>` |
| `ANDROID_SDK_ROOT` | `~/.infinite-ricks/android-sdk` |
| `ANDROID_NDK_ROOT` | `$ANDROID_SDK_ROOT/ndk/23.2.8568313` |
| `QT_ANDROID_ROOT` | `~/.infinite-ricks/Qt/5.15.2/android` |
| `ANDROID_OUTPUT_DIR` | `./android-build` |
| `ANDROID_API_LEVEL` | `28` |

## Manual build (advanced)

If you already have SDK, NDK, and Qt for Android installed:

```bash
export ANDROID_SDK_ROOT=~/Android/Sdk
export ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/23.2.8568313
export PATH=$HOME/.infinite-ricks/Qt/5.15.2/android/bin:$PATH

./compile-android.sh --skip-deps \
  --abi arm64-v8a
```

## Install on a device

```bash
adb install -r android-build/InfiniteRicks-wallet-release-unsigned.apk
```

## Reference

- Blackcoin More Android notes: https://github.com/CoinBlack/blackcoin-more/blob/master/doc/build-android.md
- Qt for Android deployment: https://doc.qt.io/qt-5/android-deploy-qt-tool.html
