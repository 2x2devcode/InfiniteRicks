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
4. Cross-compile OpenSSL, Berkeley DB, and Boost for the target ABI (16 KB page-size flags on arm64)
5. Build the Qt wallet, package an APK with `androiddeployqt`, align, and **sign** it

**Install this file on the device (version 204, ~40 MB):**

`./android-build/InfiniteRicks-wallet-android15-v204-arm64.apk`

Before installing, confirm the APK is **about 40 MB**. If Android reports **~15–20 MB**, you still have an old build without the 16 KB `libc++` fix and the app will crash on Android 15 (`qtMainLoopThread`).

## Android 15 compatibility

Android 15 often refuses **unsigned** APKs and devices with **16 KB memory pages** require native libraries built with 16 KB ELF alignment. This build pipeline addresses both:

- APK is signed automatically with a local keystore (`~/.infinite-ricks/android-release.keystore` by default)
- `targetSdkVersion` / `compileSdkVersion` **34**
- arm64 native code is linked with `-Wl,-z,max-page-size=16384`
- `android:extractNativeLibs="true"` for compatibility with bundled Qt 5.15 libraries

If you previously built arm64 dependencies before this update, run a full build **without** `--skip-deps` once so OpenSSL/BDB/Boost are rebuilt.

## Options

```bash
./compile-android.sh --abi arm64-v8a     # default (phones)
./compile-android.sh --abi armeabi-v7a   # older 32-bit ARM devices
./compile-android.sh --debug             # debug APK (also signed)
./compile-android.sh --deps-only         # libraries only, no APK
./compile-android.sh --skip-deps         # reuse existing dependency prefix
```

## Requirements

- Ubuntu 22.04 (x86_64)
- ~12 GB free disk space (SDK + NDK + Qt + sources)
- Internet access for first-time dependency download
- `sudo` for installing apt packages

Minimum supported Android version: **API 24** (Android 7.0).  
Target SDK: **34** (Android 14+ policy; runs on Android 15).  
Tested NDK: **r23.2**.

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
| `ANDROID_COMPILE_SDK` | `34` |
| `ANDROID_KEYSTORE` | `~/.infinite-ricks/android-release.keystore` |
| `ANDROID_KEYSTORE_PASS` | `infinitericks` |
| `ANDROID_KEY_ALIAS` | `infinitericks` |

## Install on a device

```bash
adb install -r android-build/InfiniteRicks-wallet-release.apk
```

If installation still fails, capture the exact error:

```bash
adb install -r android-build/InfiniteRicks-wallet-release.apk 2>&1
adb logcat -d | tail -50
```

## Reference

- Blackcoin More Android notes: https://github.com/CoinBlack/blackcoin-more/blob/master/doc/build-android.md
- Qt for Android deployment: https://doc.qt.io/qt-5/android-deploy-qt-tool.html
- Android 16 KB page sizes: https://developer.android.com/guide/practices/page-sizes
