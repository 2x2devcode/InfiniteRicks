#!/usr/bin/env bash
#
# Cross-compile InfiniteRicks Android wallet (APK) on Ubuntu 22.04.
# Based on the Qt-for-Android approach used by Blackcoin More
# (https://github.com/CoinBlack/blackcoin-more — doc/build-android.md).
#
# Usage:
#   ./compile-android.sh                  # build release APK (arm64-v8a)
#   ./compile-android.sh --abi armeabi-v7a
#   ./compile-android.sh --deps-only      # build Android libraries only
#   ./compile-android.sh --debug          # debug APK
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-28}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-30.0.3}"
ANDROID_SIGN_BUILD_TOOLS="${ANDROID_SIGN_BUILD_TOOLS:-34.0.0}"
ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK:-34}"
NDK_VERSION="${ANDROID_NDK_VERSION:-23.2.8568313}"
# NDK r27+ ships libc++_shared.so with 16 KB ELF alignment (required on Android 15 devices).
NDK_LIBCXX_VERSION="${ANDROID_NDK_LIBCXX_VERSION:-27.0.12077973}"
QT_VERSION="${QT_VERSION:-5.15.2}"
ABI="${ANDROID_ABI:-arm64-v8a}"

OPENSSL_VERSION="1.1.1w"
BDB_VERSION="5.3.28.NC"
BOOST_VERSION="1.83.0"

BUILD_DEPS=1
BUILD_APK=1
DEBUG_BUILD=0
JOBS="$(nproc 2>/dev/null || echo 2)"

DEPS_DIR=""
SDK_DIR=""
NDK_DIR=""
QT_ANDROID_DIR=""
QT_HOST_DIR=""
OUTPUT_DIR="${ANDROID_OUTPUT_DIR:-$REPO_ROOT/android-build}"
SOURCES_DIR=""

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
    cat <<'EOF'
Usage: ./compile-android.sh [options]

Options:
  --abi ABI          Android ABI: arm64-v8a (default), armeabi-v7a, x86_64
  --deps-only        Build/install Android dependency libraries and exit
  --skip-deps        Skip dependency build (use existing $ANDROID_DEPS_DIR)
  --debug            Build debug APK instead of release
  --jobs N           Parallel build jobs (default: nproc)
  --help             Show this help

Environment variables:
  ANDROID_DEPS_DIR   Dependency prefix (default: ~/.infinite-ricks/android-deps-<abi>)
  ANDROID_SDK_ROOT   Android SDK root (default: ~/.infinite-ricks/android-sdk)
  ANDROID_NDK_ROOT   Android NDK root (default: $ANDROID_SDK_ROOT/ndk/<version>)
  QT_ANDROID_ROOT    Qt for Android install (default: ~/.infinite-ricks/Qt/<version>/android)
  ANDROID_OUTPUT_DIR Output directory (default: ./android-build)
  ANDROID_API_LEVEL  Minimum platform API (default: 28)
  ANDROID_KEYSTORE   Keystore for APK signing (default: ~/.infinite-ricks/android-release.keystore)
  ANDROID_KEYSTORE_PASS / ANDROID_KEY_ALIAS  Keystore credentials (default: infinitericks)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --abi)
                shift
                ABI="${1:-}"
                ;;
            --deps-only)
                BUILD_APK=0
                ;;
            --skip-deps)
                BUILD_DEPS=0
                ;;
            --debug)
                DEBUG_BUILD=1
                ;;
            --jobs)
                shift
                JOBS="${1:-}"
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done

    case "$ABI" in
        arm64-v8a|armeabi-v7a|x86_64) ;;
        *) die "Unsupported ABI: $ABI" ;;
    esac
}

resolve_qt_path() {
    local kind="$1"
    shift
    local candidate
    for candidate in "$@"; do
        if [[ -x "$candidate/bin/qmake" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_paths() {
    DEPS_DIR="${ANDROID_DEPS_DIR:-$HOME/.infinite-ricks/android-deps-${ABI}}"
    SDK_DIR="${ANDROID_SDK_ROOT:-$HOME/.infinite-ricks/android-sdk}"
    NDK_DIR="${ANDROID_NDK_ROOT:-$SDK_DIR/ndk/$NDK_VERSION}"
    local qt_root="${QT_INSTALL_ROOT:-$HOME/.infinite-ricks/Qt}"
    QT_ANDROID_DIR="${QT_ANDROID_ROOT:-}"
    QT_HOST_DIR="${QT_HOST_ROOT:-}"
    if [[ -z "$QT_ANDROID_DIR" ]]; then
        QT_ANDROID_DIR="$(resolve_qt_path android \
            "$qt_root/$QT_VERSION/android" \
            "$qt_root/$QT_VERSION/$QT_VERSION/android" \
            "$qt_root/android")" || QT_ANDROID_DIR="$qt_root/$QT_VERSION/android"
    fi
    if [[ -z "$QT_HOST_DIR" ]]; then
        QT_HOST_DIR="$(resolve_qt_path host \
            "$qt_root/$QT_VERSION/gcc_64" \
            "$qt_root/$QT_VERSION/$QT_VERSION/gcc_64" \
            "$qt_root/gcc_64")" || QT_HOST_DIR="$qt_root/$QT_VERSION/gcc_64"
    fi
    SOURCES_DIR="${ANDROID_SOURCES_DIR:-$HOME/.infinite-ricks/android-sources}"
    mkdir -p "$DEPS_DIR/include" "$DEPS_DIR/lib" "$SOURCES_DIR" "$OUTPUT_DIR"
    chmod +x "$REPO_ROOT/share/genbuild.sh" 2>/dev/null || true
}

install_apt_packages() {
    log "Checking Ubuntu packages for Android cross-compilation"
    local packages=(
        build-essential
        git
        curl
        wget
        ca-certificates
        unzip
        zip
        openjdk-11-jdk
        openjdk-17-jdk
        python3
        python3-pip
        python3-venv
        pkg-config
        autoconf
        automake
        libtool
        libtool-bin
        perl
        patch
        qttools5-dev-tools
    )

    local missing=()
    for pkg in "${packages[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if ((${#missing[@]} > 0)); then
        log "Installing missing packages: ${missing[*]}"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    else
        log "All required Ubuntu packages are already installed"
    fi

    # Gradle 4.x (Qt 5.15 androiddeployqt) requires JDK 8/11, not JDK 17+.
    if [[ -z "${JAVA_HOME:-}" ]]; then
        if [[ -d /usr/lib/jvm/java-11-openjdk-amd64 ]]; then
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
        else
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
        fi
    fi
    export PATH="$JAVA_HOME/bin:$PATH"
}

ensure_aqt() {
    if ! command -v aqt >/dev/null 2>&1; then
        log "Installing aqtinstall (Qt installer)"
        python3 -m pip install --user --upgrade aqtinstall
        export PATH="$HOME/.local/bin:$PATH"
    fi
    command -v aqt >/dev/null 2>&1 || die "aqtinstall not available — run: python3 -m pip install --user aqtinstall"
}

setup_android_sdk() {
    if [[ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
        log "Android SDK already present at $SDK_DIR"
    else
        log "Installing Android SDK command-line tools"
        local tools_zip="$SOURCES_DIR/commandlinetools-linux.zip"
        download_file "https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip" "$tools_zip"
        rm -rf "$SDK_DIR/cmdline-tools"
        mkdir -p "$SDK_DIR/cmdline-tools"
        unzip -q -o "$tools_zip" -d "$SDK_DIR/cmdline-tools"
        mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
    fi

    export ANDROID_SDK_ROOT="$SDK_DIR"
    export ANDROID_HOME="$SDK_DIR"
    export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$PATH"

    yes | sdkmanager --licenses >/dev/null || true
    sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "build-tools;${ANDROID_SIGN_BUILD_TOOLS}" \
        "ndk;${NDK_VERSION}" \
        "ndk;${NDK_LIBCXX_VERSION}"

    [[ -d "$NDK_DIR" ]] || die "Android NDK not found at $NDK_DIR"
    export ANDROID_NDK_ROOT="$NDK_DIR"
    export ANDROID_NDK_HOME="$NDK_DIR"
}

install_qt_android() {
    ensure_aqt
    export PATH="$HOME/.local/bin:$PATH"

    local qt_root="${QT_INSTALL_ROOT:-$HOME/.infinite-ricks/Qt}"

    if [[ ! -x "$QT_ANDROID_DIR/bin/qmake" ]]; then
        # aqt uses architecture name "android" (multi-ABI) for Qt 5.15.x.
        log "Installing Qt ${QT_VERSION} for Android"
        aqt install-qt linux android "$QT_VERSION" android -O "$qt_root"
        QT_ANDROID_DIR="$(resolve_qt_path android \
            "$qt_root/$QT_VERSION/android" \
            "$qt_root/$QT_VERSION/$QT_VERSION/android")" || die "Qt for Android install failed"
    fi

    if [[ ! -x "$QT_HOST_DIR/bin/qmake" ]]; then
        log "Installing Qt ${QT_VERSION} host tools (gcc_64)"
        aqt install-qt linux desktop "$QT_VERSION" gcc_64 -O "$qt_root"
        QT_HOST_DIR="$(resolve_qt_path host \
            "$qt_root/$QT_VERSION/gcc_64" \
            "$qt_root/$QT_VERSION/$QT_VERSION/gcc_64")" || die "Qt host tools install failed"
    fi

    [[ -x "$QT_ANDROID_DIR/bin/qmake" ]] || die "Qt for Android qmake not found in $QT_ANDROID_DIR"
    [[ -x "$QT_ANDROID_DIR/bin/androiddeployqt" ]] || die "androiddeployqt not found in $QT_ANDROID_DIR/bin"
}

download_file() {
    local url="$1"
    local output="$2"
    if [[ -f "$output" ]]; then
        return 0
    fi
    log "Downloading $(basename "$output")"
    curl -fL --retry 3 --retry-delay 5 -o "$output" "$url" || wget -O "$output" "$url"
}

android_ndk_prebuilt() {
    echo "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"
}

android_toolchain_bin() {
    echo "$(android_ndk_prebuilt)/bin"
}

android_clang() {
    local api="$ANDROID_API_LEVEL"
    case "$ABI" in
        arm64-v8a)   echo "$(android_toolchain_bin)/aarch64-linux-android${api}-clang" ;;
        armeabi-v7a) echo "$(android_toolchain_bin)/armv7a-linux-androideabi${api}-clang" ;;
        x86_64)      echo "$(android_toolchain_bin)/x86_64-linux-android${api}-clang" ;;
    esac
}

android_clangxx() {
    local api="$ANDROID_API_LEVEL"
    case "$ABI" in
        arm64-v8a)   echo "$(android_toolchain_bin)/aarch64-linux-android${api}-clang++" ;;
        armeabi-v7a) echo "$(android_toolchain_bin)/armv7a-linux-androideabi${api}-clang++" ;;
        x86_64)      echo "$(android_toolchain_bin)/x86_64-linux-android${api}-clang++" ;;
    esac
}

android_page_size_ldflags() {
    # Android 15+ devices may use 16 KB memory pages; arm64 native code must be linked accordingly.
    case "$ABI" in
        arm64-v8a) echo "-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" ;;
        *) echo "" ;;
    esac
}

android_host_triplet() {
    # Berkeley DB 5.3 config.sub does not know *-linux-android; use GNU triplets.
    case "$ABI" in
        arm64-v8a)   echo "aarch64-linux-gnu" ;;
        armeabi-v7a) echo "arm-linux-gnueabihf" ;;
        x86_64)      echo "x86_64-linux-gnu" ;;
    esac
}

setup_android_toolchain_env() {
    local clang clangxx
    clang="$(android_clang)"
    clangxx="$(android_clangxx)"
    [[ -x "$clang" ]] || die "NDK clang not found: $clang"
    export PATH="$(android_toolchain_bin):$PATH"
    export CC="$clang"
    export CXX="$clangxx"
    export AR="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
    export RANLIB="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib"
    export STRIP="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
    local page_ldflags
    page_ldflags="$(android_page_size_ldflags)"
    export CFLAGS="-fPIC -DANDROID -D__ANDROID_API__=${ANDROID_API_LEVEL}"
    export CXXFLAGS="-fPIC -DANDROID -D__ANDROID_API__=${ANDROID_API_LEVEL} -std=c++14"
    export LDFLAGS="-fPIC ${page_ldflags}"
}

build_openssl_android() {
    [[ -f "$DEPS_DIR/lib/libssl.a" && -f "$DEPS_DIR/lib/libcrypto.a" ]] && return 0

    local tarball="$SOURCES_DIR/openssl-${OPENSSL_VERSION}.tar.gz"
    download_file "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "$tarball"

    local build_dir="$SOURCES_DIR/openssl-${OPENSSL_VERSION}-android-${ABI}"
    rm -rf "$build_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    mv "$SOURCES_DIR/openssl-${OPENSSL_VERSION}" "$build_dir"

    local openssl_target
    case "$ABI" in
        arm64-v8a)   openssl_target="android-arm64" ;;
        armeabi-v7a) openssl_target="android-arm" ;;
        x86_64)      openssl_target="android-x86_64" ;;
    esac

    log "Building OpenSSL ${OPENSSL_VERSION} for ${ABI}"
    pushd "$build_dir" >/dev/null
    export ANDROID_NDK_ROOT="$NDK_DIR"
    export PATH="$(android_toolchain_bin):$PATH"
    ./Configure "$openssl_target" \
        -D__ANDROID_API__="$ANDROID_API_LEVEL" \
        --prefix="$DEPS_DIR" \
        no-shared no-tests \
        ${LDFLAGS:+-ldflags "$LDFLAGS"}
    make -j"$JOBS" build_libs
    make install_dev
    popd >/dev/null
}

patch_berkeley_db_android_sources() {
    local src_dir="$1"
    log "Patching Berkeley DB for Android NDK / libc++"
    sed -i 's/\(__atomic_compare_exchange\)/\1_db/' "$src_dir/src/dbinc/atomic.h"
    sed -i \
        -e 's/^#define[[:space:]]*atomic_init/#define bdb_atomic_init/' \
        -e 's/^#define[[:space:]]*atomic_read/#define bdb_atomic_read/' \
        -e 's/^#define[[:space:]]*atomic_inc/#define bdb_atomic_inc/' \
        -e 's/^#define[[:space:]]*atomic_dec/#define bdb_atomic_dec/' \
        "$src_dir/src/dbinc/atomic.h"
    find "$src_dir" -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) \
        -exec sed -i \
            -e 's/\batomic_init(/bdb_atomic_init(/g' \
            -e 's/\batomic_read(/bdb_atomic_read(/g' \
            -e 's/\batomic_inc(/bdb_atomic_inc(/g' \
            -e 's/\batomic_dec(/bdb_atomic_dec(/g' \
            {} +
}

build_berkeley_db_android() {
    [[ -f "$DEPS_DIR/lib/libdb_cxx.a" ]] && return 0

    local tarball="$SOURCES_DIR/db-${BDB_VERSION}.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        download_file "https://download.oracle.com/berkeley-db/db-${BDB_VERSION}.tar.gz" "$tarball" || \
        download_file "http://download.oracle.com/berkeley-db/db-${BDB_VERSION}.tar.gz" "$tarball"
    fi

    local src_dir="$SOURCES_DIR/db-${BDB_VERSION}-android-${ABI}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    mv "$SOURCES_DIR/db-${BDB_VERSION}" "$src_dir"
    patch_berkeley_db_android_sources "$src_dir"
    # BDB 5.3 ships ancient config.sub that lacks aarch64.
    if [[ -f /usr/share/misc/config.sub ]]; then
        cp /usr/share/misc/config.sub "$src_dir/dist/config.sub"
        cp /usr/share/misc/config.guess "$src_dir/dist/config.guess"
    else
        local automake_dir
        automake_dir="$(ls -d /usr/share/automake-*/ 2>/dev/null | tail -1)"
        if [[ -n "$automake_dir" ]]; then
            cp "$automake_dir/config.sub" "$src_dir/dist/config.sub"
            cp "$automake_dir/config.guess" "$src_dir/dist/config.guess"
        fi
    fi

    log "Building Berkeley DB ${BDB_VERSION} for ${ABI}"
    pushd "$src_dir/build_unix" >/dev/null
    ../dist/configure \
        --build="$(gcc -dumpmachine)" \
        --host="$(android_host_triplet)" \
        --prefix="$DEPS_DIR" \
        --enable-cxx \
        --disable-shared \
        --enable-smallbuild \
        CC="$CC" \
        CXX="$CXX" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        CFLAGS="-fPIC -DANDROID" \
        CXXFLAGS="-fPIC -DANDROID -std=gnu++11" \
        LDFLAGS="$LDFLAGS"
    if ! grep -q '^#define HAVE_CXX_STDHEADERS' db_cxx.h 2>/dev/null; then
        sed -i '/#ifdef HAVE_CXX_STDHEADERS/i#define HAVE_CXX_STDHEADERS 1' db_cxx.h 2>/dev/null || true
    fi
    make -j"$JOBS" libdb_cxx-5.3.a
    mkdir -p "$DEPS_DIR/lib" "$DEPS_DIR/include"
    cp libdb_cxx-5.3.a "$DEPS_DIR/lib/libdb_cxx.a"
    make install_include
    popd >/dev/null
}

build_boost_android() {
    [[ -f "$DEPS_DIR/lib/libboost_system.a" ]] && return 0

    local tarball="$SOURCES_DIR/boost_${BOOST_VERSION//./_}.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        download_file "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION//./_}.tar.gz" "$tarball"
    fi

    local src_dir="$SOURCES_DIR/boost_${BOOST_VERSION//./_}-android-${ABI}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    mv "$SOURCES_DIR/boost_${BOOST_VERSION//./_}" "$src_dir"

    local arch addr_model
    case "$ABI" in
        arm64-v8a)   arch="arm"; addr_model="64" ;;
        armeabi-v7a) arch="arm"; addr_model="32" ;;
        x86_64)      arch="x86"; addr_model="64" ;;
    esac

    log "Building Boost ${BOOST_VERSION} for ${ABI}"
    pushd "$src_dir" >/dev/null
    local page_ldflags boost_linkflags=""
    page_ldflags="$(android_page_size_ldflags)"
    for flag in $page_ldflags; do
        boost_linkflags+=" <linkflags>${flag}"
    done
    cat > user-config.jam <<EOF
using clang : android
    : $(android_clangxx)
    : <compileflags>-fPIC <compileflags>-DANDROID <compileflags>-D__ANDROID_API__=${ANDROID_API_LEVEL}
      <linkflags>-fPIC <linkflags>-static-libstdc++${boost_linkflags}
    ;
EOF
    ./bootstrap.sh --prefix="$DEPS_DIR"
    ./b2 -j"$JOBS" \
        --user-config=user-config.jam \
        toolset=clang-android \
        target-os=android \
        architecture="$arch" \
        address-model="$addr_model" \
        threadapi=pthread \
        link=static \
        runtime-link=static \
        --with-system \
        --with-filesystem \
        --with-program_options \
        --with-thread \
        --with-chrono \
        install
    popd >/dev/null
}

build_android_dependencies() {
    [[ "$BUILD_DEPS" -eq 1 ]] || return 0
    if [[ "$ABI" == "arm64-v8a" && -d "$DEPS_DIR/lib" && ! -f "$DEPS_DIR/.page-size-16kb" ]]; then
        log "Removing stale arm64 dependency build (rebuild required for Android 15 / 16 KB page size)"
        rm -rf "$DEPS_DIR"
    fi
    setup_android_toolchain_env
    build_openssl_android
    build_berkeley_db_android
    build_boost_android
    [[ "$ABI" == "arm64-v8a" ]] && touch "$DEPS_DIR/.page-size-16kb"
}

ensure_android_keystore() {
    local keystore="${ANDROID_KEYSTORE:-$HOME/.infinite-ricks/android-release.keystore}"
    local ks_pass="${ANDROID_KEYSTORE_PASS:-infinitericks}"
    local key_alias="${ANDROID_KEY_ALIAS:-infinitericks}"

    if [[ -f "$keystore" ]]; then
        printf '%s' "$keystore"
        return 0
    fi

    printf '\n==> Creating Android signing keystore at %s\n' "$keystore" >&2
    mkdir -p "$(dirname "$keystore")"
    keytool -genkeypair -v \
        -keystore "$keystore" \
        -storepass "$ks_pass" \
        -alias "$key_alias" \
        -keypass "$ks_pass" \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=InfiniteRicks Wallet, OU=Mobile, O=InfiniteRicks, C=US" \
        >/dev/null 2>&1
    printf '%s' "$keystore"
}

ndk_libcxx_shared_path() {
    local ndk_libcxx_dir="$SDK_DIR/ndk/$NDK_LIBCXX_VERSION"
    case "$ABI" in
        arm64-v8a)
            echo "$ndk_libcxx_dir/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
            ;;
        armeabi-v7a)
            echo "$ndk_libcxx_dir/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so"
            ;;
        x86_64)
            echo "$ndk_libcxx_dir/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so"
            ;;
        *)
            return 1
            ;;
    esac
}

verify_apk_android15() {
    local apk="$1"
    local size libcxx_apk
    size="$(stat -c%s "$apk")"
    if (( size < 35000000 )); then
        die "APK is only $((size / 1024 / 1024)) MB ($size bytes). Expected ~40 MB with 16 KB libc++ patch. Do not install this build on Android 15."
    fi

    libcxx_apk="$(mktemp)"
    unzip -p "$apk" "lib/${ABI}/libc++_shared.so" > "$libcxx_apk" 2>/dev/null || die "APK missing lib/${ABI}/libc++_shared.so"
    if ! readelf -lW "$libcxx_apk" | grep -q '0x4000'; then
        rm -f "$libcxx_apk"
        die "libc++_shared.so in APK is not 16 KB aligned (readelf Align 0x4000). Android 15 will crash."
    fi
    rm -f "$libcxx_apk"
    log "APK verified for Android 15 ($((size / 1024 / 1024)) MB, libc++ Align 0x4000)"
}

patch_apk_libcxx_16k() {
    local apk="$1"
    local libcxx_src

    [[ "$ABI" == "arm64-v8a" ]] || return 0
    libcxx_src="$(ndk_libcxx_shared_path)"
    [[ -f "$libcxx_src" ]] || die "16 KB libc++_shared.so not found (install NDK ${NDK_LIBCXX_VERSION}): $libcxx_src"

    log "Patching APK with 16 KB aligned libc++_shared.so (NDK ${NDK_LIBCXX_VERSION})"
    local tmpdir
    tmpdir="$(mktemp -d)"
    unzip -q -o "$apk" -d "$tmpdir"
    local dest="$tmpdir/lib/${ABI}/libc++_shared.so"
    [[ -f "$dest" ]] || die "APK does not contain libc++_shared.so for ${ABI}"
    cp -f "$libcxx_src" "$dest"
    rm -f "$apk"
    (cd "$tmpdir" && zip -q -r -0 "$apk" .)
    rm -rf "$tmpdir"
}

sign_apk() {
    local unsigned_apk="$1"
    local signed_apk="$2"
    local keystore ks_pass key_alias apksigner zipalign

    keystore="$(ensure_android_keystore)"
    ks_pass="${ANDROID_KEYSTORE_PASS:-infinitericks}"
    key_alias="${ANDROID_KEY_ALIAS:-infinitericks}"
    apksigner="$SDK_DIR/build-tools/${ANDROID_SIGN_BUILD_TOOLS}/apksigner"
    zipalign="$SDK_DIR/build-tools/${ANDROID_SIGN_BUILD_TOOLS}/zipalign"
    [[ -x "$apksigner" ]] || die "apksigner not found: $apksigner (install build-tools;${ANDROID_SIGN_BUILD_TOOLS})"
    [[ -x "$zipalign" ]] || die "zipalign not found: $zipalign"

    local aligned_apk="${unsigned_apk%.apk}-aligned.apk"

    log "Aligning APK"
    rm -f "$aligned_apk"
    if [[ "$ABI" == "arm64-v8a" ]]; then
        "$zipalign" -f -p 16 "$unsigned_apk" "$aligned_apk"
    else
        "$zipalign" -f -p 4 "$unsigned_apk" "$aligned_apk"
    fi

    log "Signing APK"
    rm -f "$signed_apk"
    "$apksigner" sign \
        --ks "$keystore" \
        --ks-pass "pass:${ks_pass}" \
        --key-pass "pass:${ks_pass}" \
        --ks-key-alias "$key_alias" \
        --out "$signed_apk" \
        "$aligned_apk"

    "$apksigner" verify --verbose "$signed_apk" >/dev/null
    rm -f "$aligned_apk"
}

host_lrelease() {
    if command -v lrelease >/dev/null 2>&1; then
        command -v lrelease
        return 0
    fi
    if [[ -x "$QT_HOST_DIR/bin/lrelease" ]]; then
        echo "$QT_HOST_DIR/bin/lrelease"
        return 0
    fi
    die "lrelease not found (install qttools5-dev-tools or Qt host tools)"
}

build_apk() {
    log "Building InfiniteRicks Android wallet (${ABI})"
    setup_android_toolchain_env

    local qmake_bin="$QT_ANDROID_DIR/bin/qmake"
    local androiddeployqt_bin="$QT_ANDROID_DIR/bin/androiddeployqt"
    local ndk_host="linux-x86_64"
    local build_dir="$REPO_ROOT/build-android-${ABI}"
    local lrelease_bin clang clangxx
    lrelease_bin="$(host_lrelease)"
    clang="$(android_clang)"
    clangxx="$(android_clangxx)"

    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    pushd "$REPO_ROOT" >/dev/null
    rm -f Makefile Makefile.Debug Makefile.Release .qmake.stash
    rm -rf build release
    make -C src/leveldb clean 2>/dev/null || true
    rm -f src/leveldb/libleveldb.a src/leveldb/libmemenv.a

    export ANDROID_SDK_ROOT="$SDK_DIR"
    export ANDROID_NDK_ROOT="$NDK_DIR"
    export PATH="$QT_ANDROID_DIR/bin:$PATH"

    "$qmake_bin" \
        -spec android-clang \
        "ANDROID_ABIS=$ABI" \
        "ANDROID_API_VERSION=$ANDROID_API_LEVEL" \
        "ANDROID_SDK_ROOT=$SDK_DIR" \
        "ANDROID_NDK_ROOT=$NDK_DIR" \
        "ANDROID_NDK_HOST=$ndk_host" \
        InfiniteRicks-qt.pro \
        RELEASE=1 \
        USE_UPNP=- \
        USE_DBUS=0 \
        QMAKE_CC="$clang" \
        QMAKE_CXX="$clangxx" \
        QMAKE_LINK="$clangxx" \
        QMAKE_LINK_C="$clang" \
        OBJECTS_DIR="$build_dir" \
        MOC_DIR="$build_dir" \
        UI_DIR="$build_dir" \
        BOOST_LIB_SUFFIX= \
        BOOST_THREAD_LIB_SUFFIX= \
        BOOST_INCLUDE_PATH="$DEPS_DIR/include" \
        BOOST_LIB_PATH="$DEPS_DIR/lib" \
        BDB_INCLUDE_PATH="$DEPS_DIR/include" \
        BDB_LIB_PATH="$DEPS_DIR/lib" \
        OPENSSL_INCLUDE_PATH="$DEPS_DIR/include" \
        OPENSSL_LIB_PATH="$DEPS_DIR/lib" \
        QMAKE_LRELEASE="$lrelease_bin"

    make -j"$JOBS"

    local deploy_json=""
    for candidate in android-InfiniteRicks-qt-deployment-settings.json \
                     android-deployment-settings.json \
                     "$build_dir/android-InfiniteRicks-qt-deployment-settings.json"; do
        if [[ -f "$candidate" ]]; then
            deploy_json="$candidate"
            break
        fi
    done
    [[ -n "$deploy_json" ]] || die "android deployment settings JSON not found after qmake"

    local apk_mode="release"
    [[ "$DEBUG_BUILD" -eq 1 ]] && apk_mode="debug"

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    make INSTALL_ROOT="$OUTPUT_DIR" install

    "$androiddeployqt_bin" \
        --input "$deploy_json" \
        --output "$OUTPUT_DIR" \
        --android-platform "android-${ANDROID_COMPILE_SDK}" \
        --jdk "$JAVA_HOME" \
        --gradle \
        --"${apk_mode}"

    popd >/dev/null

    local apk_file unsigned_apk signed_apk
    apk_file="$(find "$OUTPUT_DIR/build/outputs/apk" -name '*.apk' 2>/dev/null | head -1)"
    [[ -n "$apk_file" ]] || die "APK was not generated — check $OUTPUT_DIR build logs"
    unsigned_apk="$OUTPUT_DIR/InfiniteRicks-wallet-${apk_mode}-unsigned.apk"
    signed_apk="$OUTPUT_DIR/InfiniteRicks-wallet-${apk_mode}.apk"
    cp -f "$apk_file" "$unsigned_apk"
    patch_apk_libcxx_16k "$unsigned_apk"
    sign_apk "$unsigned_apk" "$signed_apk"
    verify_apk_android15 "$signed_apk"

    local friendly_apk="$OUTPUT_DIR/InfiniteRicks-wallet-android15-v204-arm64.apk"
    cp -f "$signed_apk" "$friendly_apk"

    log "Signed APK (install this on Android 15+): $signed_apk"
    log "Same build, friendly name: $friendly_apk"
    log "Unsigned copy kept at: $unsigned_apk"
    printf '\n*** Android 15: APK must be ~40 MB. If your phone shows ~15-20 MB, you have the OLD build. ***\n'
}

print_summary() {
    log "Android build complete"
    printf '  ABI          : %s\n' "$ABI"
    printf '  Dependencies : %s\n' "$DEPS_DIR"
    printf '  Android SDK  : %s\n' "$SDK_DIR"
    printf '  Qt Android   : %s\n' "$QT_ANDROID_DIR"
    printf '  Output dir   : %s\n' "$OUTPUT_DIR"
    find "$OUTPUT_DIR" -maxdepth 1 -name '*.apk' -printf '  APK          : %p\n' 2>/dev/null || true
}

main() {
    parse_args "$@"
    resolve_paths
    install_apt_packages
    setup_android_sdk
    install_qt_android
    build_android_dependencies

    if [[ "$BUILD_APK" -eq 0 ]]; then
        print_summary
        exit 0
    fi

    build_apk
    print_summary
}

main "$@"
