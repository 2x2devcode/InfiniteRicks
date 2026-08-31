#!/usr/bin/env bash
#
# Cross-compile InfiniteRicks Windows binaries on Ubuntu 22.04/24.04.
# Produces InfiniteRicksd.exe (CLI) and InfiniteRicks-qt.exe (GUI).
#
# Usage:
#   ./compile-windows.sh              # build CLI + GUI
#   ./compile-windows.sh --cli-only   # daemon only
#   ./compile-windows.sh --gui-only   # wallet only (builds Schannel Qt if needed)
#   ./compile-windows.sh --arch x86_64  # 64-bit Windows targets
#   ./compile-windows.sh --deps-only    # build MinGW libraries only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SRC_DIR="$REPO_ROOT/src"

MXE_DIR=""
SOURCES_DIR=""
OUTPUT_DIR="${MINGW_OUTPUT_DIR:-$REPO_ROOT/windows-build}"
DEPS_DIR=""

ARCH="x86_64"
BUILD_CLI=1
BUILD_GUI=1
BUILD_DEPS=1
BUILD_MXE_QT=1
BUILD_VERBOSE=0
JOBS="$(nproc 2>/dev/null || echo 2)"
QT_VER="${QT_VER:-5.15.2}"
ALLOW_MXE_QT="${ALLOW_MXE_QT:-0}"

BUILD_LOG=""
BUILD_LOG_ERRORS=""
BUILD_LOG_TEE_PID=""

OPENSSL_VER="3.0.13"
BDB_VERSION="5.3.28.NC"
BOOST_VERSION="1.83.0"
MINIUPNPC_VERSION="2.2.6"
ZLIB_VERSION="1.3.1"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
    cat <<'EOF'
Usage: ./compile-windows.sh [options]

Options:
  --cli-only       Build only InfiniteRicksd.exe
  --gui-only       Build only InfiniteRicks-qt.exe
  --deps-only      Build/install MinGW dependency libraries and exit
  --skip-deps      Skip dependency build (use existing $MINGW_DEPS_DIR)
  --skip-mxe       Do not build legacy MXE Qt (only used with ALLOW_MXE_QT=1)
  --arch x86_64    64-bit Windows target (default)
  --arch i686      32-bit Windows target (not supported: code uses __int128)
  --jobs N         Parallel build jobs (default: nproc)
  --log-file PATH  Write full build log to PATH (default: windows-build/build-*.log)
  --verbose        Run make with V=1 (show compile commands)
  --help           Show this help

Environment variables:
  MINGW_DEPS_DIR   Dependency prefix (default: ~/.infinite-ricks/mingw-deps)
  MXE_PATH         MXE installation directory (default: $MINGW_DEPS_DIR/mxe)
  MINGW_OUTPUT_DIR Output directory (default: ./windows-build)
  MINGW_BUILD_LOG  Same as --log-file (overridden by --log-file)
  QT_VER            Qt source version (default: 5.15.2)
  QT_USE_OPENSSL=1  Build QtNetwork with OpenSSL (default: Schannel, no OpenSSL)
  ALLOW_MXE_QT=1    Restore the legacy MXE Qt build path (default: off)

The default GUI path builds static Qt with Windows Schannel under
$MINGW_DEPS_DIR/qt and links wallet crypto to OpenSSL 3.0.13 separately.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cli-only)  BUILD_GUI=0 ;;
            --gui-only)  BUILD_CLI=0 ;;
            --deps-only) BUILD_CLI=0; BUILD_GUI=0 ;;
            --skip-deps) BUILD_DEPS=0 ;;
            --skip-mxe)  BUILD_MXE_QT=0 ;;
            --arch)
                shift
                ARCH="${1:-}"
                [[ "$ARCH" == "i686" || "$ARCH" == "x86_64" ]] || die "Invalid --arch value: $ARCH"
                ;;
            --jobs)
                shift
                JOBS="${1:-}"
                ;;
            --log-file)
                shift
                BUILD_LOG="${1:-}"
                [[ -n "$BUILD_LOG" ]] || die "--log-file requires a path"
                ;;
            --verbose) BUILD_VERBOSE=1 ;;
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
}

resolve_paths() {
    DEPS_DIR_BASE="${MINGW_DEPS_DIR:-$HOME/.infinite-ricks/mingw-deps-${ARCH}}"
    DEPS_DIR="$DEPS_DIR_BASE"
    MXE_DIR="${MXE_PATH:-$DEPS_DIR_BASE/mxe}"
    SOURCES_DIR="${MINGW_SOURCES_DIR:-$DEPS_DIR_BASE/sources}"
}

setup_toolchain() {
    [[ "$ARCH" != "i686" ]] || die "32-bit Windows (i686) is not supported: InfiniteRicks uses __int128, which MinGW 32-bit does not provide. Use --arch x86_64 (default)."

    case "$ARCH" in
        i686)
            MINGW_PREFIX="i686-w64-mingw32"
            OPENSSL_TARGET="mingw"
            MXE_TARGET="i686-w64-mingw32.static"
            ;;
        x86_64)
            MINGW_PREFIX="x86_64-w64-mingw32"
            OPENSSL_TARGET="mingw64"
            MXE_TARGET="x86_64-w64-mingw32.static"
            ;;
    esac

    export CC="${MINGW_PREFIX}-gcc"
    export CXX="${MINGW_PREFIX}-g++"
    export AR="${MINGW_PREFIX}-ar"
    export RANLIB="${MINGW_PREFIX}-ranlib"
    export STRIP="${MINGW_PREFIX}-strip"
    MINGW_HOST="${MINGW_PREFIX}"
    OPENSSL_CROSS_PREFIX="${MINGW_PREFIX}-"

    need_cmd "$CC"
    need_cmd "$CXX"
    need_cmd "$AR"
    need_cmd "$RANLIB"
    need_cmd "$STRIP"
}

install_apt_packages() {
    log "Checking Ubuntu packages for MinGW cross-compilation"
    local packages=(
        build-essential
        git
        curl
        wget
        ca-certificates
        autoconf
        automake
        libtool
        libtool-bin
        autopoint
        pkg-config
        perl
        python3
        python-is-python3
        python3-mako
        python3-pil
        bzip2
        patch
        p7zip-full
        mingw-w64
        g++-mingw-w64
        gettext
        bison
        flex
        gperf
        intltool
        lzip
        ruby
        libgdk-pixbuf2.0-bin
        libpcre2-dev
        cmake
        ninja-build
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
}

prepare_dirs() {
    mkdir -p "$DEPS_DIR/include" "$DEPS_DIR/lib" "$SOURCES_DIR" "$OUTPUT_DIR"
    chmod +x "$REPO_ROOT/share/genbuild.sh" 2>/dev/null || true
    chmod +x "$SRC_DIR/leveldb/build_detect_platform" 2>/dev/null || true
}

default_build_log_path() {
    printf '%s/build-%s.log' "$OUTPUT_DIR" "$(date +%Y%m%d-%H%M%S)"
}

setup_build_logging() {
    BUILD_LOG="${BUILD_LOG:-${MINGW_BUILD_LOG:-$(default_build_log_path)}}"
    BUILD_LOG_ERRORS="${BUILD_LOG%.log}-errors.log"
    mkdir -p "$(dirname "$BUILD_LOG")"
    : > "$BUILD_LOG"
    : > "$BUILD_LOG_ERRORS"

    # Mirror stdout/stderr to the log file for the whole script run.
    exec > >(tee -a "$BUILD_LOG") 2>&1
    BUILD_LOG_TEE_PID=$!

    ln -sf "$(basename "$BUILD_LOG")" "$(dirname "$BUILD_LOG")/build-latest.log"
    ln -sf "$(basename "$BUILD_LOG_ERRORS")" "$(dirname "$BUILD_LOG")/build-errors-latest.log"

    log "Build log: $BUILD_LOG"
    log "Error summary (on failure): $BUILD_LOG_ERRORS"
}

extract_build_errors() {
    [[ -f "$BUILD_LOG" ]] || return 0
    grep -E -i \
        '(^|\s)(error:|fatal error:|undefined reference|collect2: error|ld: error|ninja: build stopped|make(\[[0-9]+\])?: \*\*\*|No rule to make target|FAILED:|CMake Error|Error [0-9]+|No such file or directory|cannot find|cannot create|Unknown platform|build_detect_platform|compiler not found|not found:|Directory nonexistent)' \
        "$BUILD_LOG" | tail -n 100 > "$BUILD_LOG_ERRORS" 2>/dev/null || true
}

on_build_exit() {
    local ec=$?
    if [[ $ec -ne 0 && -n "$BUILD_LOG" ]]; then
        extract_build_errors
        printf '\n' >&2
        printf 'ERROR: Windows build failed (exit %s)\n' "$ec" >&2
        printf '  Full log     : %s\n' "$BUILD_LOG" >&2
        if [[ -s "$BUILD_LOG_ERRORS" ]]; then
            printf '  Error summary: %s\n' "$BUILD_LOG_ERRORS" >&2
            printf '\n--- last build errors ---\n' >&2
            tail -n 30 "$BUILD_LOG_ERRORS" >&2
            printf '%s\n' '--- end ---' >&2
        else
            printf '  Tip: last lines of the full log:\n' >&2
            tail -n 40 "$BUILD_LOG" >&2
        fi
    fi
}

make_flags() {
    MAKE_EXTRA_ARGS=(-j"$JOBS")
    [[ "$BUILD_VERBOSE" -eq 1 ]] && MAKE_EXTRA_ARGS+=(V=1)
}

run_make() {
    make_flags
    make "${MAKE_EXTRA_ARGS[@]}" AR="$AR" RANLIB="$RANLIB" "$@"
}

run_mxe_make() {
    make_flags
    # MXE selects its own host and target tools. Inheriting the wallet's
    # cross-tool variables can make MXE stages exit without a useful error.
    env -u CC -u CXX -u AR -u RANLIB -u STRIP \
        make "${MAKE_EXTRA_ARGS[@]}" "$@"
}

run_qt_release_make() {
    make_flags
    if [[ ! -f Makefile.Release ]]; then
        die "qmake did not generate Makefile.Release (qmake may have failed)"
    fi
    # Qt top-level "make release" + -j can exit immediately with no output; build Release directly.
    make "${MAKE_EXTRA_ARGS[@]}" -f Makefile.Release
}

verify_toolchain() {
    local label="${1:-build}"
    need_cmd "$CC"
    need_cmd "$CXX"
    need_cmd "$AR"
    need_cmd "$RANLIB"
    log "Toolchain ($label): CC=$CC"
    log "Toolchain ($label): CXX=$CXX"
    log "Toolchain ($label): AR=$AR"
}

download_file() {
    local url="$1"
    local output="$2"
    if [[ -f "$output" ]]; then
        return 0
    fi
    log "Downloading $(basename "$output")"
    if ! curl -fL --retry 3 --retry-delay 5 -o "$output" "$url"; then
        wget -O "$output" "$url"
    fi
    if [[ "$output" == *.tar.gz ]] && ! gzip -t "$output" 2>/dev/null; then
        rm -f "$output"
        die "Downloaded file is not a valid gzip archive: $url"
    fi
}

build_openssl() {
    local marker="$DEPS_DIR/.openssl-${OPENSSL_VER}.ok"
    if [[ -f "$marker" && -f "$DEPS_DIR/lib/libssl.a" &&
          -f "$DEPS_DIR/lib/libcrypto.a" &&
          -f "$DEPS_DIR/include/openssl/opensslv.h" ]] &&
       grep -q "OpenSSL ${OPENSSL_VER}" "$DEPS_DIR/include/openssl/opensslv.h"; then
        log "OpenSSL ${OPENSSL_VER} already built"
        return 0
    fi

    rm -f "$DEPS_DIR"/.openssl-*.ok
    rm -f "$DEPS_DIR/lib/libssl.a" "$DEPS_DIR/lib/libcrypto.a"
    rm -f "$DEPS_DIR/lib64/libssl.a" "$DEPS_DIR/lib64/libcrypto.a"

    local tarball="$SOURCES_DIR/openssl-${OPENSSL_VER}.tar.gz"
    if ! download_file "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz" "$tarball"; then
        download_file "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz" "$tarball"
    fi

    local build_dir="$SOURCES_DIR/openssl-${OPENSSL_VER}-build"
    rm -rf "$build_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    mv "$SOURCES_DIR/openssl-${OPENSSL_VER}" "$build_dir"

    log "Building OpenSSL ${OPENSSL_VER} for ${ARCH}"
    pushd "$build_dir" >/dev/null
    # Configure applies --cross-compile-prefix; avoid exporting toolchain vars here.
    env -u CC -u CXX -u AR -u RANLIB ./Configure "$OPENSSL_TARGET" \
        --cross-compile-prefix="${OPENSSL_CROSS_PREFIX}" \
        --prefix="$DEPS_DIR" \
        --libdir=lib \
        no-shared no-tests no-module
    run_make CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB"
    make install_sw CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB"
    popd >/dev/null

    [[ -f "$DEPS_DIR/lib/libssl.a" ]] || die "OpenSSL install did not produce libssl.a"
    [[ -f "$DEPS_DIR/lib/libcrypto.a" ]] || die "OpenSSL install did not produce libcrypto.a"
    grep -q "OpenSSL ${OPENSSL_VER}" "$DEPS_DIR/include/openssl/opensslv.h" ||
        die "OpenSSL headers do not report ${OPENSSL_VER}"
    touch "$marker"
}

verify_openssl() {
    [[ -f "$DEPS_DIR/include/openssl/opensslv.h" ]] ||
        die "OpenSSL headers are missing from $DEPS_DIR"
    [[ -f "$DEPS_DIR/lib/libssl.a" && -f "$DEPS_DIR/lib/libcrypto.a" ]] ||
        die "OpenSSL static libraries are missing from $DEPS_DIR"
    grep -q "OpenSSL ${OPENSSL_VER}" "$DEPS_DIR/include/openssl/opensslv.h" ||
        die "OpenSSL in $DEPS_DIR is not ${OPENSSL_VER}; rebuild without --skip-deps"
    log "Using OpenSSL ${OPENSSL_VER} from $DEPS_DIR"
}

mingw_header_compat_dir() {
    local fix_dir="$DEPS_DIR/include-winfix"
    local mingw_include="/usr/${MINGW_PREFIX}/include"
    mkdir -p "$fix_dir"
    # Berkeley DB includes several Windows headers with legacy casing.
    local headers=(
        WinIoCtl.h:winioctl.h
        Windows.h:windows.h
        WinDef.h:windef.h
        WinBase.h:winbase.h
        WinNT.h:winnt.h
    )
    local pair want have
    for pair in "${headers[@]}"; do
        want="${pair%%:*}"
        have="${pair##*:}"
        if [[ -f "$mingw_include/$have" ]]; then
            ln -sf "$mingw_include/$have" "$fix_dir/$want"
        fi
    done
    printf '%s\n' "$fix_dir"
}

patch_berkeley_db_sources() {
    local src_dir="$1"
    log "Patching Berkeley DB sources for modern MinGW/g++"
    sed -i 's/\(__atomic_compare_exchange\)/\1_db/' "$src_dir/src/dbinc/atomic.h"
    sed -i 's/WinIoCtl.h/winioctl.h/g' "$src_dir/src/dbinc/win_db.h"
}

patch_berkeley_db_after_configure() {
    local build_dir="$1"
    # Cross configure often misses C++ standard headers on MinGW.
    if ! grep -q '^#define HAVE_CXX_STDHEADERS' "$build_dir/db_cxx.h"; then
        sed -i '/#ifdef HAVE_CXX_STDHEADERS/i#define HAVE_CXX_STDHEADERS 1' "$build_dir/db_cxx.h"
    fi
}

build_berkeley_db() {
    [[ -f "$DEPS_DIR/lib/libdb_cxx.a" ]] && return 0

    local tarball="$SOURCES_DIR/db-${BDB_VERSION}.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        download_file "https://download.oracle.com/berkeley-db/db-${BDB_VERSION}.tar.gz" "$tarball" || \
        download_file "http://download.oracle.com/berkeley-db/db-${BDB_VERSION}.tar.gz" "$tarball"
    fi

    local src_dir="$SOURCES_DIR/db-${BDB_VERSION}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    patch_berkeley_db_sources "$src_dir"

    local winfix
    winfix="$(mingw_header_compat_dir)"
    # Do not pass -isystem for the MinGW sysroot: it breaks g++ #include_next.
    local mingw_cflags="-I. -I${winfix}"

    log "Building Berkeley DB ${BDB_VERSION} for ${ARCH}"
    pushd "$src_dir/build_unix" >/dev/null
    env -u CC -u CXX -u AR -u RANLIB \
        CC="$CC" \
        CXX="$CXX" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        CFLAGS="$mingw_cflags" \
        CXXFLAGS="$mingw_cflags" \
        ../dist/configure \
            --build="$(gcc -dumpmachine)" \
            --host="${MINGW_HOST}" \
            --prefix="$DEPS_DIR" \
            --enable-cxx \
            --disable-shared \
            --enable-mingw \
            --program-transform-name='s,.exe,,;s,\(.*\),\1.exe,'
    patch_berkeley_db_after_configure "$src_dir/build_unix"
    # Do not pass CFLAGS/CXXFLAGS to make: that replaces the generated flags
    # and drops -I../src (dbinc/win_db.h) from CPPFLAGS.
    run_make CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB"
    make install CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB"
    popd >/dev/null
}

build_boost() {
    [[ -f "$DEPS_DIR/lib/libboost_system.a" ]] && return 0

    local tarball="$SOURCES_DIR/boost_${BOOST_VERSION//./_}.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        download_file "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION//./_}.tar.gz" "$tarball" || \
        download_file "https://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION//./_}.tar.gz/download" "$tarball"
    fi

    local src_dir="$SOURCES_DIR/boost_${BOOST_VERSION//./_}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"

    log "Building Boost ${BOOST_VERSION} for ${ARCH}"
    pushd "$src_dir" >/dev/null
    cat > user-config.jam <<EOF
using gcc : mingw : ${CXX} ;
EOF
    ./bootstrap.sh
    local address_model="32"
    [[ "$ARCH" == "x86_64" ]] && address_model="64"

    ./b2 \
        --user-config=user-config.jam \
        toolset=gcc-mingw \
        target-os=windows \
        address-model="$address_model" \
        threading=multi \
        link=static \
        runtime-link=static \
        variant=release \
        --prefix="$DEPS_DIR" \
        --layout=system \
        -j"$JOBS" \
        --with-system \
        --with-filesystem \
        --with-program_options \
        --with-thread \
        --with-chrono \
        install
    popd >/dev/null
}

build_zlib() {
    [[ -f "$DEPS_DIR/lib/libz.a" ]] && return 0

    local tarball="$SOURCES_DIR/zlib-${ZLIB_VERSION}.tar.gz"
    download_file "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" "$tarball"

    local src_dir="$SOURCES_DIR/zlib-${ZLIB_VERSION}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"

    log "Building zlib ${ZLIB_VERSION} for ${ARCH}"
    pushd "$src_dir" >/dev/null
    env -u CC -u CXX -u AR -u RANLIB \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        ./configure --prefix="$DEPS_DIR" --static
    run_make libz.a
    make install
    popd >/dev/null
}

build_miniupnpc() {
    [[ -f "$DEPS_DIR/lib/libminiupnpc.a" ]] && return 0

    local tarball="$SOURCES_DIR/miniupnpc-${MINIUPNPC_VERSION}.tar.gz"
    download_file "https://miniupnp.tuxfamily.org/files/miniupnpc-${MINIUPNPC_VERSION}.tar.gz" "$tarball"

    local src_dir="$SOURCES_DIR/miniupnpc-${MINIUPNPC_VERSION}"
    rm -rf "$src_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"

    log "Building miniupnpc ${MINIUPNPC_VERSION} for ${ARCH}"
    pushd "$src_dir" >/dev/null
    make -f Makefile.mingw libminiupnpc.a CC="$CC" AR="$AR" \
        CFLAGS="-I${DEPS_DIR}/include" \
        LDFLAGS="-L${DEPS_DIR}/lib"
    mkdir -p "$DEPS_DIR/include/miniupnpc"
    cp libminiupnpc.a "$DEPS_DIR/lib/"
    cp include/*.h "$DEPS_DIR/include/miniupnpc/"
    cp miniupnpcstrings.h "$DEPS_DIR/include/miniupnpc/" 2>/dev/null || true
    popd >/dev/null
}

build_mingw_dependencies() {
    [[ "$BUILD_DEPS" -eq 1 ]] || return 0
    build_openssl
    build_zlib
    build_berkeley_db
    build_boost
    build_miniupnpc
    log "MinGW dependencies are ready in $DEPS_DIR"
}

# Qt 5.15.2 needs explicit <limits> includes when built with GCC 11+.
qtbase_has_limits_patch() {
    local src="$1"
    local header="$src/src/corelib/global/qfloat16.h"
    [[ -f "$header" ]] &&
        grep -qE '^[[:space:]]*#include[[:space:]]*<limits>' "$header"
}

ensure_qt_include_limits() {
    local file="$1"
    local after="${2:-}"
    [[ -f "$file" ]] || return 0
    if grep -qE '^[[:space:]]*#include[[:space:]]*<limits>' "$file"; then
        return 0
    fi

    if [[ -n "$after" ]] && grep -qF "$after" "$file"; then
        awk -v after="$after" '
            !done && index($0, after) {
                print
                print "#include <limits>"
                done=1
                next
            }
            { print }
        ' "$file" > "${file}.infinite-ricks.tmp"
        mv "${file}.infinite-ricks.tmp" "$file"
    elif grep -q '#include <QtCore/qmetatype.h>' "$file"; then
        sed -i '/#include <QtCore\/qmetatype.h>/a #include <limits>' "$file"
    elif grep -q '#include <QtCore/qglobal.h>' "$file"; then
        sed -i '/#include <QtCore\/qglobal.h>/a #include <limits>' "$file"
    elif grep -q '#include <array>' "$file"; then
        sed -i '/#include <array>/a #include <limits>' "$file"
    elif grep -q '#include <QtCore/qbytearray.h>' "$file"; then
        sed -i '/#include <QtCore\/qbytearray.h>/a #include <limits>' "$file"
    else
        sed -i '0,/#include /s//#include <limits>\n&/' "$file"
    fi

    grep -qE '^[[:space:]]*#include[[:space:]]*<limits>' "$file" ||
        die "Failed to add #include <limits> to $file"
    log "Patched Qt header: $(basename "$file")"
}

patch_qtbase_for_gcc11() {
    local src="$1"
    local patch_file="$REPO_ROOT/patches/qtbase-5.15.2-gcc11-limits.diff"

    if qtbase_has_limits_patch "$src"; then
        log "Qt GCC 11+ <limits> patch already present in $src"
        return 0
    fi

    log "Applying GCC 11+ Qt <limits> patch under $src"
    if [[ -f "$patch_file" ]]; then
        if (cd "$src" && patch -p1 --forward --batch < "$patch_file"); then
            log "Applied $patch_file"
        else
            warn "Could not apply $patch_file cleanly; applying includes directly"
        fi
    else
        die "Missing Qt compatibility patch: $patch_file"
    fi

    ensure_qt_include_limits \
        "$src/src/corelib/global/qfloat16.h" \
        '#include <QtCore/qmetatype.h>'
    ensure_qt_include_limits \
        "$src/src/corelib/global/qendian.h" \
        '#include <QtCore/qglobal.h>'
    ensure_qt_include_limits \
        "$src/src/corelib/text/qbytearraymatcher.h" \
        '#include <QtCore/qbytearray.h>'
    ensure_qt_include_limits \
        "$src/src/corelib/tools/qoffsetstringarray_p.h" \
        '#include <array>'

    qtbase_has_limits_patch "$src" ||
        die "Qt qfloat16.h still lacks #include <limits> after patching"
}

build_qt_from_source() {
    local qt_backend="schannel"
    [[ "${QT_USE_OPENSSL:-0}" == "1" ]] && qt_backend="openssl"
    local marker="$DEPS_DIR/.qt-${QT_VER}-${qt_backend}.ok"
    if [[ -f "$marker" && -x "$DEPS_DIR/qt/bin/qmake" ]]; then
        log "Qt ${QT_VER} (${qt_backend}) already built at $DEPS_DIR/qt"
        return 0
    fi

    log "Building Qt ${QT_VER} (qtbase) for ${MINGW_PREFIX} with ${qt_backend}"
    local qt_tarball="$SOURCES_DIR/qtbase-everywhere-src-${QT_VER}.tar.xz"
    download_file \
        "https://download.qt.io/archive/qt/5.15/${QT_VER}/submodules/qtbase-everywhere-src-${QT_VER}.tar.xz" \
        "$qt_tarball"

    local qt_src="$SOURCES_DIR/qtbase-everywhere-src-${QT_VER}"
    local qt_build="$SOURCES_DIR/qt-${QT_VER}-${qt_backend}-build"
    rm -rf "$qt_src" "$qt_build" "$DEPS_DIR/qt"
    rm -f "$DEPS_DIR"/.qt-*.ok "$DEPS_DIR/.qt.ok"
    tar xf "$qt_tarball" -C "$SOURCES_DIR"
    patch_qtbase_for_gcc11 "$qt_src"
    mkdir -p "$qt_build"

    local qt_ssl_args=()
    if [[ "$qt_backend" == "openssl" ]]; then
        [[ -f "$DEPS_DIR/include/openssl/ssl.h" ]] ||
            die "Qt OpenSSL mode requires headers under $DEPS_DIR/include"
        [[ -f "$DEPS_DIR/lib/libssl.a" && -f "$DEPS_DIR/lib/libcrypto.a" ]] ||
            die "Qt OpenSSL mode requires static libraries under $DEPS_DIR/lib"
        qt_ssl_args=(
            -openssl-linked
            "OPENSSL_INCDIR=$DEPS_DIR/include"
            "OPENSSL_LIBDIR=$DEPS_DIR/lib"
            "OPENSSL_LIBS=-lssl -lcrypto -lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32"
        )
        log "Configuring QtNetwork with linked OpenSSL from $DEPS_DIR"
    else
        qt_ssl_args=(-schannel -no-openssl)
        log "Configuring QtNetwork with Windows Schannel (-schannel -no-openssl)"
    fi

    local qt_log="$OUTPUT_DIR/qt-${QT_VER}-${qt_backend}.log"
    ln -sf "$(basename "$qt_log")" "$OUTPUT_DIR/qt-latest.log"
    : > "$qt_log"
    log "Qt stage log: $qt_log"

    pushd "$qt_build" >/dev/null
    set +e
    "$qt_src/configure" \
        -prefix "$DEPS_DIR/qt" \
        -release -static -opensource -confirm-license \
        -xplatform win32-g++ \
        -device-option "CROSS_COMPILE=${MINGW_PREFIX}-" \
        -nomake examples -nomake tests \
        -no-opengl -no-cups -no-pch -no-dbus -no-icu \
        -no-feature-sql -no-feature-testlib \
        -qt-zlib -qt-libpng -qt-libjpeg -qt-freetype -qt-pcre -qt-harfbuzz \
        "${qt_ssl_args[@]}" \
        -I "$DEPS_DIR/include" -L "$DEPS_DIR/lib" \
        -verbose 2>&1 | tee -a "$qt_log"
    local qt_rc=${PIPESTATUS[0]}
    set -e
    if [[ "$qt_rc" -ne 0 ]]; then
        printf '%s\n' '--- last 80 lines of Qt configure log ---' >&2
        tail -n 80 "$qt_log" >&2 || true
        popd >/dev/null
        die "Qt configure failed (exit $qt_rc); see $qt_log"
    fi

    if [[ "$qt_backend" == "openssl" && -f config.summary ]] &&
       ! grep -E '[[:space:]]OpenSSL[[:space:].]+yes' config.summary >/dev/null; then
        grep -E 'OpenSSL|Schannel' config.summary >&2 || true
        popd >/dev/null
        die "Qt did not detect OpenSSL; use the default QT_USE_OPENSSL=0 for Schannel"
    fi

    set +e
    make -j"$JOBS" 2>&1 | tee -a "$qt_log"
    qt_rc=${PIPESTATUS[0]}
    set -e
    if [[ "$qt_rc" -ne 0 ]]; then
        printf '%s\n' '--- last 80 lines of Qt make log ---' >&2
        tail -n 80 "$qt_log" >&2 || true
        popd >/dev/null
        die "Qt make failed (exit $qt_rc); see $qt_log"
    fi

    set +e
    make install 2>&1 | tee -a "$qt_log"
    qt_rc=${PIPESTATUS[0]}
    set -e
    popd >/dev/null
    if [[ "$qt_rc" -ne 0 ]]; then
        printf '%s\n' '--- last 80 lines of Qt install log ---' >&2
        tail -n 80 "$qt_log" >&2 || true
        die "Qt make install failed (exit $qt_rc); see $qt_log"
    fi

    [[ -x "$DEPS_DIR/qt/bin/qmake" ]] ||
        die "Qt install did not produce $DEPS_DIR/qt/bin/qmake"
    fix_mingw_schannel_lib_case
    touch "$marker"
}

# MinGW ld on Linux is case-sensitive, while Qt's Schannel metadata can emit
# -lSecur32/-lCrypt32 for lowercase MinGW import library filenames.
fix_mingw_schannel_lib_case() {
    local case_dir="$DEPS_DIR/lib/win32-case"
    mkdir -p "$case_dir"

    resolve_mingw_lib() {
        local name="$1"
        local path=""
        path="$("${MINGW_PREFIX}-g++" -print-file-name="lib${name}.a" 2>/dev/null || true)"
        if [[ -z "$path" || "$path" == "lib${name}.a" || ! -f "$path" ]]; then
            local dir
            for dir in \
                "/usr/${MINGW_PREFIX}/lib" \
                "/usr/lib/gcc/${MINGW_PREFIX}"/*/ \
                "$MXE_DIR/usr/${MXE_TARGET}/lib"
            do
                if [[ -f "${dir}/lib${name}.a" ]]; then
                    path="${dir}/lib${name}.a"
                    break
                fi
            done
        fi
        [[ -n "$path" && -f "$path" ]] || return 1
        printf '%s\n' "$path"
    }

    local lower upper src
    for lower in secur32 crypt32 ncrypt bcrypt; do
        case "$lower" in
            secur32) upper=Secur32 ;;
            crypt32) upper=Crypt32 ;;
            ncrypt)  upper=Ncrypt ;;
            bcrypt)  upper=Bcrypt ;;
        esac
        src="$(resolve_mingw_lib "$lower" || true)"
        if [[ -z "$src" ]]; then
            warn "MinGW lib${lower}.a not found; Schannel may fail to link -l${upper}"
            continue
        fi
        ln -sfn "$src" "$case_dir/lib${upper}.a"
        ln -sfn "$src" "$case_dir/lib${lower}.a"
        ln -sfn "$src" "$DEPS_DIR/lib/lib${upper}.a"
        log "win32-case: lib${upper}.a -> $src"
    done

    local metadata
    shopt -s nullglob
    for metadata in \
        "$DEPS_DIR/qt/lib"/libQt5Network*.prl \
        "$DEPS_DIR/qt/lib/pkgconfig"/Qt5Network*.pc \
        "$DEPS_DIR/qt/mkspecs/modules"/qt_lib_network*.pri
    do
        [[ -f "$metadata" ]] || continue
        if grep -qE -- '-l(Secur32|Crypt32|Ncrypt|Bcrypt)' "$metadata"; then
            sed -i \
                -e 's/-lSecur32/-lsecur32/g' \
                -e 's/-lCrypt32/-lcrypt32/g' \
                -e 's/-lNcrypt/-lncrypt/g' \
                -e 's/-lBcrypt/-lbcrypt/g' \
                "$metadata"
            log "Normalized Schannel library case in $(basename "$metadata")"
        fi
    done
    shopt -u nullglob
}

find_mingw_qmake() {
    if [[ -n "${QT_MINGW_QMAKE:-}" && -x "$QT_MINGW_QMAKE" ]]; then
        printf '%s\n' "$QT_MINGW_QMAKE"
        return 0
    fi

    local candidate
    for candidate in \
        "$DEPS_DIR/qt/bin/qmake" \
        "$MXE_DIR/usr/bin/${MXE_TARGET}-qmake-qt5" \
        "$MXE_DIR/usr/${MXE_TARGET}/qt5/bin/qmake"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_schannel_qt() {
    local qt_backend="schannel"
    [[ "${QT_USE_OPENSSL:-0}" == "1" ]] && qt_backend="openssl"
    local marker="$DEPS_DIR/.qt-${QT_VER}-${qt_backend}.ok"
    if [[ -f "$marker" && -x "$DEPS_DIR/qt/bin/qmake" ]]; then
        log "Using Qt ${QT_VER} (${qt_backend}) from $DEPS_DIR/qt/bin/qmake"
        return 0
    fi

    if [[ "$qt_backend" == "schannel" ]]; then
        log "Provisioning Schannel Qt so wallet crypto uses OpenSSL ${OPENSSL_VER}"
    else
        warn "QT_USE_OPENSSL=1 links OpenSSL into QtNetwork; Schannel is the default"
    fi
    build_qt_from_source
}

ensure_qt() {
    [[ "$BUILD_GUI" -eq 1 ]] || return 0
    if [[ "$ALLOW_MXE_QT" == "1" ]]; then
        ensure_mxe
        local mxe_qmake="$MXE_DIR/usr/bin/${MXE_TARGET}-qmake-qt5"
        [[ -x "$mxe_qmake" ]] || die "Legacy MXE qmake is missing: $mxe_qmake"
        log "ALLOW_MXE_QT=1: using legacy MXE Qt at $mxe_qmake"
        return 0
    fi
    ensure_schannel_qt
}

build_leveldb() {
    local skip_if_built="${1:-0}"
    if [[ "$skip_if_built" -eq 1 && -f "$SRC_DIR/leveldb/libleveldb.a" && -f "$SRC_DIR/leveldb/libmemenv.a" ]]; then
        log "LevelDB already built, skipping ($SRC_DIR/leveldb/libleveldb.a)"
        return 0
    fi

    log "Building LevelDB for Windows (${ARCH})"
    verify_toolchain "LevelDB"

    pushd "$SRC_DIR/leveldb" >/dev/null
    chmod +x ./build_detect_platform

    export TARGET_OS=OS_WINDOWS_CROSSCOMPILE
    rm -f build_config.mk libleveldb.a libmemenv.a

    log "Generating LevelDB build_config.mk (TARGET_OS=$TARGET_OS)"
    CC="$CC" CXX="$CXX" TARGET_OS="$TARGET_OS" ./build_detect_platform build_config.mk ./ \
        || die "LevelDB build_detect_platform failed"

    run_make clean || true
    CC="$CC" CXX="$CXX" TARGET_OS="$TARGET_OS" \
        run_make libleveldb.a libmemenv.a \
        || die "LevelDB make failed (see lines above in the build log)"

    "$RANLIB" libleveldb.a
    "$RANLIB" libmemenv.a
    popd >/dev/null
    log "LevelDB built: $SRC_DIR/leveldb/libleveldb.a"
}

copy_cli_runtime_dlls() {
    # Fallback: if winpthread was linked dynamically, ship the DLL beside the exe.
    local mingw_lib="/usr/${MINGW_PREFIX}/lib"
    local dll="$mingw_lib/libwinpthread-1.dll"
    [[ -f "$dll" ]] || return 0
    if x86_64-w64-mingw32-objdump -p "$OUTPUT_DIR/InfiniteRicksd.exe" 2>/dev/null | grep -qi 'libwinpthread-1.dll'; then
        cp -f "$dll" "$OUTPUT_DIR/"
        log "Copied libwinpthread-1.dll next to InfiniteRicksd.exe (runtime dependency)"
    fi
}

build_cli() {
    log "Building InfiniteRicksd.exe"
    verify_toolchain "CLI"
    verify_openssl
    build_leveldb
    pushd "$SRC_DIR" >/dev/null
    mkdir -p obj obj/zerocoin
    # Do not run makefile clean here: it wipes LevelDB we just built and removes obj/build.h.
    log "Compiling InfiniteRicksd.exe (makefile.linux-mingw)"
    run_make -f makefile.linux-mingw \
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
        DEPSDIR="$DEPS_DIR" \
        TARGET_PLATFORM="$ARCH" \
        USE_UPNP=1 \
        || die "InfiniteRicksd.exe build failed (see errors above in the build log)"
    [[ -f InfiniteRicksd.exe ]] || die "InfiniteRicksd.exe was not produced after make"
    cp InfiniteRicksd.exe "$OUTPUT_DIR/"
    popd >/dev/null
    copy_cli_runtime_dlls
    log "CLI binary: $OUTPUT_DIR/InfiniteRicksd.exe"
}

host_pkg_config_path() {
    local paths=()
    local triplet
    triplet="$(gcc -dumpmachine 2>/dev/null || true)"
    [[ -n "$triplet" && -d "/usr/lib/${triplet}/pkgconfig" ]] && paths+=("/usr/lib/${triplet}/pkgconfig")
    [[ -d /usr/lib/pkgconfig ]] && paths+=("/usr/lib/pkgconfig")
    [[ -d /usr/share/pkgconfig ]] && paths+=("/usr/share/pkgconfig")
    local IFS=:
    printf '%s' "${paths[*]}"
}

prefetch_glib_pcre2_for_mxe() {
    local pcre2_tar="$MXE_DIR/pkg/pcre2-10.46.tar.bz2"
    local primary="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.46/pcre2-10.46.tar.bz2"
    local fallback="https://github.com/mesonbuild/wrapdb/releases/download/pcre2_10.46-1/pcre2-10.46.tar.bz2"
    [[ -f "$pcre2_tar" ]] && return 0
    mkdir -p "$MXE_DIR/pkg"
    log "Downloading pcre2 10.46 for MXE glib (offline subproject)"
    if ! curl -fL --retry 5 --retry-delay 10 -o "$pcre2_tar" "$primary"; then
        curl -fL --retry 5 --retry-delay 10 -o "$pcre2_tar" "$fallback" || \
            die "Could not download pcre2 for MXE glib. Check internet access to github.com."
    fi
}

patch_mxe_glib_native_build() {
    local glib_mk="$MXE_DIR/src/glib.mk"
    [[ -f "$glib_mk" ]] || return 0
    grep -q 'infinite-ricks-glib-pcre2-fix' "$glib_mk" && return 0

    local host_pc
    host_pc="$(host_pkg_config_path)"
    python3 - "$glib_mk" "$host_pc" <<'PY'
import sys
path, host_pc = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
needle = "    '$(MXE_MESON_NATIVE_WRAPPER)' \\\n        --buildtype=release \\\n        -Dtests=false \\"
inject = f"""    # infinite-ricks-glib-pcre2-fix
    test -f '$(SOURCE_DIR)/subprojects/pcre2-10.46/meson.build' || (mkdir -p '$(SOURCE_DIR)/subprojects' && tar xjf '$(PWD)/pkg/pcre2-10.46.tar.bz2' -C '$(SOURCE_DIR)/subprojects')
    PKG_CONFIG_PATH='{host_pc}:$(PREFIX)/$(BUILD)/lib/pkgconfig' \\
    '$(MXE_MESON_NATIVE_WRAPPER)' \\
        --buildtype=release \\
        -Dtests=false \\"""
if needle not in text:
    raise SystemExit(f"Could not patch {path}: MXE glib.mk layout changed")
open(path, "w", encoding="utf-8").write(text.replace(needle, inject, 1))
PY
    log "Patched MXE glib build to use local/system pcre2"
}

ensure_mxe_host_ninja() {
    local host_bin="$MXE_DIR/usr/x86_64-pc-linux-gnu/bin"
    local host_installed="$MXE_DIR/usr/x86_64-pc-linux-gnu/installed/ninja"
    [[ -f "$host_installed" ]] && return 0
    command -v ninja >/dev/null 2>&1 || return 0
    log "Using system ninja for MXE host tools"
    mkdir -p "$host_bin" "$(dirname "$host_installed")"
    ln -sf "$(command -v ninja)" "$host_bin/ninja"
    touch "$host_installed"
}

dump_mxe_failure() {
    local stage="$1"
    printf '\n%s\n' "--- last 80 lines of $BUILD_LOG ---" >&2
    tail -n 80 "$BUILD_LOG" >&2 2>/dev/null || true

    local candidates=()
    local mxe_log=""
    shopt -s nullglob globstar
    candidates=(
        "$MXE_DIR"/log/**/*"${stage}"*.log
        "$MXE_DIR"/log/*"${stage}"*.log
        "$MXE_DIR"/tmp-"${stage}"-*/**/*.log
    )
    shopt -u nullglob globstar
    if ((${#candidates[@]} > 0)); then
        mxe_log="$(ls -1t "${candidates[@]}" 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -n "$mxe_log" ]]; then
        printf '\n%s\n' "--- last 80 lines of MXE log $mxe_log ---" >&2
        tail -n 80 "$mxe_log" >&2 2>/dev/null || true
    else
        printf 'No separate MXE %s log was found under %s.\n' "$stage" "$MXE_DIR" >&2
    fi
}

ensure_mxe() {
  [[ "$BUILD_GUI" -eq 1 ]] || return 0

  local qmake_bin="$MXE_DIR/usr/bin/${MXE_TARGET}-qmake-qt5"
  if [[ -x "$qmake_bin" ]]; then
      log "MXE Qt already available at $MXE_DIR"
      return 0
  fi

  [[ "$BUILD_MXE_QT" -eq 1 ]] ||
      die "Legacy MXE Qt not found at $MXE_DIR (remove --skip-mxe or unset ALLOW_MXE_QT)"

  log "MXE/Qt for MinGW not found; setting up MXE (this can take a long time)"
  if [[ ! -d "$MXE_DIR/.git" ]]; then
      git clone https://github.com/mxe/mxe.git "$MXE_DIR"
  fi

  local settings="$MXE_DIR/settings.mk"
  cat > "$settings" <<EOF
MXE_TARGETS := ${MXE_TARGET}
JOBS := ${JOBS}
EOF

  # Some minimal Ubuntu images lack default -lstdc++ search paths for MXE host tools.
  export LIBRARY_PATH="/usr/lib/gcc/$(gcc -dumpmachine)/$(gcc -dumpversion)${LIBRARY_PATH:+:$LIBRARY_PATH}"
  ensure_mxe_host_ninja
  prefetch_glib_pcre2_for_mxe
  patch_mxe_glib_native_build

  pushd "$MXE_DIR" >/dev/null
  # Host glib is required before Qt; meson may fail to download pcre2 from wrapdb.
  if [[ ! -f "usr/x86_64-pc-linux-gnu/installed/glib" ]]; then
      log "Building MXE host glib (one-time step before Qt)..."
      rm -rf "tmp-glib-x86_64-pc-linux-gnu"
      export PKG_CONFIG_PATH="$(host_pkg_config_path):${PKG_CONFIG_PATH:-}"
      local mxe_rc=0
      run_mxe_make glib MXE_TARGETS=x86_64-pc-linux-gnu || mxe_rc=$?
      if [[ "$mxe_rc" -ne 0 ]]; then
          dump_mxe_failure glib
          popd >/dev/null
          die "MXE host glib failed (exit $mxe_rc). Install libpcre2-dev and check the logs above."
      fi
  fi
  log "Building legacy MXE qtbase for ${MXE_TARGET} without inherited AR/RANLIB"
  local mxe_rc=0
  run_mxe_make qtbase MXE_TARGETS="${MXE_TARGET}" || mxe_rc=$?
  if [[ "$mxe_rc" -ne 0 ]]; then
      dump_mxe_failure qtbase
      popd >/dev/null
      die "MXE qtbase failed (exit $mxe_rc). See the final 80 log lines above."
  fi
  popd >/dev/null

  [[ -x "$qmake_bin" ]] || die "MXE qmake not found after build: $qmake_bin"
}

verify_mxe_toolchain() {
    local mxe_bin="$MXE_DIR/usr/bin"
    local cxx="$mxe_bin/${MXE_TARGET}-g++"
    [[ -x "$cxx" ]] || die "MXE compiler not found: $cxx (run ./compile-windows.sh and wait for qtbase)"
    if ! "$cxx" -dumpversion >/dev/null 2>&1; then
        die "MXE compiler cannot run: $cxx — check that MXE gcc/qtbase finished building"
    fi
    # qmake's win32-g++ spec probes ${MXE_TARGET}-g++ by name (must be on PATH).
    if ! command -v "${MXE_TARGET}-g++" >/dev/null 2>&1; then
        die "MXE compiler is not on PATH: ${MXE_TARGET}-g++ — qmake will fail with 'Cannot run target compiler'"
    fi
}

setup_mxe_toolchain_env() {
    local mxe_bin="$MXE_DIR/usr/bin"
    local mxe_qt_bin="$MXE_DIR/usr/${MXE_TARGET}/qt5/bin"
    export PATH="$mxe_bin:$mxe_qt_bin:$PATH"
    export LIBRARY_PATH="/usr/lib/gcc/$(gcc -dumpmachine)/$(gcc -dumpversion)${LIBRARY_PATH:+:$LIBRARY_PATH}"
}

use_mxe_compiler_for_deps() {
    # MXE Qt must link with the MXE toolchain; match Boost/BDB/OpenSSL to the same compiler.
    local mxe_bin="$MXE_DIR/usr/bin"
    export CC="${mxe_bin}/${MXE_TARGET}-gcc"
    export CXX="${mxe_bin}/${MXE_TARGET}-g++"
    export AR="${mxe_bin}/${MXE_TARGET}-ar"
    export RANLIB="${mxe_bin}/${MXE_TARGET}-ranlib"
    export STRIP="${mxe_bin}/${MXE_TARGET}-strip"
    MINGW_HOST="${MXE_TARGET}"
    OPENSSL_CROSS_PREFIX="${MXE_TARGET}-"
    DEPS_DIR="${DEPS_DIR_BASE}-mxe"
    mkdir -p "$DEPS_DIR/include" "$DEPS_DIR/lib"
}

host_lrelease() {
    if command -v lrelease >/dev/null 2>&1; then
        command -v lrelease
        return 0
    fi
    die "Host lrelease not found (install qttools5-dev-tools). MXE does not ship a Linux lrelease binary."
}

qrc_resource_paths() {
    local qrc="$REPO_ROOT/src/qt/bitcoin.qrc"
    [[ -f "$qrc" ]] || die "Missing Qt resource file: $qrc"
    sed -n 's:.*<file[^>]*>\([^<]*\)</file>.*:\1:p' "$qrc" | while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        printf '%s\n' "$REPO_ROOT/src/qt/$rel"
    done
}

list_missing_qt_resources() {
    local path
    while IFS= read -r path; do
        [[ -f "$path" ]] || printf '%s\n' "$path"
    done < <(qrc_resource_paths)
}

ensure_qt_translations() {
    local lrelease_bin qm_file ts_file base compiled=0
    lrelease_bin="$(host_lrelease)"
    mkdir -p "$REPO_ROOT/src/qt/locale"

    while IFS= read -r qm_file; do
        [[ -f "$qm_file" ]] && continue
        [[ "$qm_file" == */locale/*.qm ]] || continue
        base="$(basename "$qm_file" .qm)"
        ts_file="$REPO_ROOT/src/qt/locale/${base}.ts"
        [[ -f "$ts_file" ]] || die "Missing translation source: $ts_file (needed for $(basename "$qm_file"))"
        log "Compiling translation: ${base}.ts -> ${base}.qm"
        "$lrelease_bin" "$ts_file" -qm "$qm_file" || die "lrelease failed for $ts_file"
        compiled=1
    done < <(qrc_resource_paths)

    [[ "$compiled" -eq 1 ]] && log "Qt translations compiled with $lrelease_bin"
}

ensure_qt_icons() {
    local missing=() generator path
    while IFS= read -r path; do
        [[ "$path" == */res/icons/* ]] || continue
        [[ -f "$path" ]] || missing+=("$path")
    done < <(qrc_resource_paths)
    ((${#missing[@]} == 0)) && return 0

    log "Missing ${#missing[@]} Qt icon file(s) under src/qt/res/icons"
    printf '  %s\n' "${missing[@]:0:8}"
    ((${#missing[@]} > 8)) && printf '  ... and %s more\n' "$((${#missing[@]} - 8))"

    generator="$REPO_ROOT/share/qt/generate_modern_icons.py"
    [[ -f "$generator" ]] || die "Missing icon generator: $generator"
    log "Regenerating Qt/Android icons with $generator"
    need_cmd python3
    if ! python3 -c 'import PIL' 2>/dev/null; then
        log "Installing python3-pil for icon generation"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pil
    fi
    python3 "$generator" || die "Icon generation failed ($generator)"
}

ensure_qt_resources() {
    local path
    ensure_qt_translations
    ensure_qt_icons

    mapfile -t missing < <(list_missing_qt_resources)
    ((${#missing[@]} == 0)) && return 0

    log "Still missing ${#missing[@]} Qt resource file(s) referenced by src/qt/bitcoin.qrc"
    printf '  %s\n' "${missing[@]:0:12}"
    ((${#missing[@]} > 12)) && printf '  ... and %s more\n' "$((${#missing[@]} - 12))"
    die "Restore missing files under src/qt/ or update the repository (git pull)"
}

build_gui() {
    log "Building InfiniteRicks-qt.exe"
    ensure_qt
    ensure_qt_resources
    verify_openssl

    local qmake_bin=""
    local qt_runtime_bin=""
    local qmake_path=""
    local qmake_cc=""
    local qmake_cxx=""
    local qmake_rc=""
    local qmake_ranlib=""

    if [[ "$ALLOW_MXE_QT" == "1" ]]; then
        verify_mxe_toolchain
        setup_mxe_toolchain_env
        local mxe_bin="$MXE_DIR/usr/bin"
        qmake_bin="$mxe_bin/${MXE_TARGET}-qmake-qt5"
        qt_runtime_bin="$MXE_DIR/usr/${MXE_TARGET}/qt5/bin"
        qmake_path="$mxe_bin:$qt_runtime_bin:$PATH"
        qmake_cc="$mxe_bin/${MXE_TARGET}-gcc"
        qmake_cxx="$mxe_bin/${MXE_TARGET}-g++"
        qmake_rc="$mxe_bin/${MXE_TARGET}-windres"
        qmake_ranlib="$mxe_bin/${MXE_TARGET}-ranlib"
        warn "ALLOW_MXE_QT=1: using legacy MXE Qt; QtNetwork may pull OpenSSL 1.1"
    else
        qmake_bin="$DEPS_DIR/qt/bin/qmake"
        qt_runtime_bin="$DEPS_DIR/qt/bin"
        qmake_path="$qt_runtime_bin:$PATH"
        qmake_cc="${MINGW_PREFIX}-gcc"
        qmake_cxx="${MINGW_PREFIX}-g++"
        qmake_rc="${MINGW_PREFIX}-windres"
        qmake_ranlib="${MINGW_PREFIX}-ranlib"
        [[ -x "$qmake_bin" ]] ||
            die "Schannel Qt qmake is missing: $qmake_bin"
        verify_toolchain "GUI"
    fi

    log "GUI qmake: $qmake_bin"
    log "GUI compiler: $qmake_cxx"
    fix_mingw_schannel_lib_case

    local gui_obj_dir="build-mingw-${ARCH}"
    local legacy_gui_dir="$REPO_ROOT/build-win-qt-${ARCH}"

    build_leveldb 1

    # qmake from a subdir breaks .moc paths and may omit MinGW C++14 byte fixes.
    pushd "$REPO_ROOT" >/dev/null
    if [[ -d "$legacy_gui_dir" ]]; then
        log "Removing obsolete $legacy_gui_dir (do not build inside this directory)"
        rm -rf "$legacy_gui_dir"
    fi
    rm -f Makefile Makefile.Debug Makefile.Release .qmake.stash
    rm -rf "$gui_obj_dir" build
    mkdir -p build "$gui_obj_dir" release

    local host_lrelease_bin
    host_lrelease_bin="$(host_lrelease)"

    local schannel_lib_args=()
    if [[ -d "$DEPS_DIR/lib/win32-case" ]]; then
        schannel_lib_args+=("LIBS+=-L$DEPS_DIR/lib/win32-case")
    fi

    env PATH="$qmake_path" \
        "$qmake_bin" \
        -spec win32-g++ \
        InfiniteRicks-qt.pro \
        RELEASE=1 \
        USE_UPNP=1 \
        USE_BUILD_INFO=1 \
        OBJECTS_DIR="$gui_obj_dir" \
        MOC_DIR="$gui_obj_dir" \
        UI_DIR="$gui_obj_dir" \
        BOOST_LIB_SUFFIX= \
        BOOST_THREAD_LIB_SUFFIX= \
        BOOST_INCLUDE_PATH="$DEPS_DIR/include" \
        BOOST_LIB_PATH="$DEPS_DIR/lib" \
        BDB_INCLUDE_PATH="$DEPS_DIR/include" \
        BDB_LIB_PATH="$DEPS_DIR/lib" \
        OPENSSL_INCLUDE_PATH="$DEPS_DIR/include" \
        OPENSSL_LIB_PATH="$DEPS_DIR/lib" \
        MINIUPNPC_INCLUDE_PATH="$DEPS_DIR/include/miniupnpc" \
        MINIUPNPC_LIB_PATH="$DEPS_DIR/lib" \
        QMAKE_CC="$qmake_cc" \
        QMAKE_CXX="$qmake_cxx" \
        QMAKE_LINK="$qmake_cxx" \
        QMAKE_LINK_C="$qmake_cc" \
        QMAKE_RC="$qmake_rc" \
        QMAKE_RANLIB="$qmake_ranlib" \
        QMAKE_LRELEASE="$host_lrelease_bin" \
        "QMAKE_CXXFLAGS+=-std=gnu++14 -include $REPO_ROOT/src/qt/mingw-preinclude.h" \
        "QMAKE_CXXFLAGS_RELEASE+=-std=gnu++14" \
        "QMAKE_CXXFLAGS_DEBUG+=-std=gnu++14" \
        "${schannel_lib_args[@]}" \
        || die "qmake failed for InfiniteRicks-qt.pro"

    log "Compiling GUI (make -f Makefile.Release) — errors will be saved to $BUILD_LOG"
    PATH="$qmake_path" run_qt_release_make \
        || die "GUI build failed — search the log for 'error:' or 'undefined reference'"

    local exe_path=""
    if [[ -f release/InfiniteRicks-qt.exe ]]; then
        exe_path="release/InfiniteRicks-qt.exe"
    elif [[ -f InfiniteRicks-qt.exe ]]; then
        exe_path="InfiniteRicks-qt.exe"
    else
        die "GUI build finished but InfiniteRicks-qt.exe was not found"
    fi

    cp "$exe_path" "$OUTPUT_DIR/InfiniteRicks-qt.exe"
    popd >/dev/null

    if command -v strings >/dev/null 2>&1; then
        if strings "$OUTPUT_DIR/InfiniteRicks-qt.exe" | grep -q "OpenSSL ${OPENSSL_VER}"; then
            log "Verified InfiniteRicks-qt.exe embeds OpenSSL ${OPENSSL_VER}"
        elif strings "$OUTPUT_DIR/InfiniteRicks-qt.exe" | grep -qE 'OpenSSL 1\.1\.'; then
            die "InfiniteRicks-qt.exe still embeds OpenSSL 1.1.x instead of ${OPENSSL_VER}"
        else
            die "InfiniteRicks-qt.exe does not embed the expected OpenSSL ${OPENSSL_VER} version string"
        fi
    fi

    mkdir -p "$OUTPUT_DIR/qt-runtime"
    if [[ -d "$qt_runtime_bin" ]]; then
        cp -n "$qt_runtime_bin"/Qt5*.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$qt_runtime_bin"/libgcc_s_*.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$qt_runtime_bin"/libstdc++-6.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$qt_runtime_bin"/libwinpthread-1.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
    fi

    log "GUI binary: $OUTPUT_DIR/InfiniteRicks-qt.exe"
    log "Qt runtime DLLs (if any): $OUTPUT_DIR/qt-runtime/"
}

print_summary() {
    log "Build complete"
    printf '  Architecture : %s\n' "$ARCH"
    printf '  Dependencies : %s\n' "$DEPS_DIR"
    printf '  Output dir   : %s\n' "$OUTPUT_DIR"
    [[ -n "$BUILD_LOG" ]] && printf '  Build log    : %s\n' "$BUILD_LOG"
    [[ -f "$OUTPUT_DIR/InfiniteRicksd.exe" ]] && printf '  CLI          : %s\n' "$OUTPUT_DIR/InfiniteRicksd.exe"
    [[ -f "$OUTPUT_DIR/InfiniteRicks-qt.exe" ]] && printf '  GUI          : %s\n' "$OUTPUT_DIR/InfiniteRicks-qt.exe"
}

main() {
    parse_args "$@"
    resolve_paths
    prepare_dirs
    setup_build_logging
    trap on_build_exit EXIT
    install_apt_packages
    setup_toolchain

    if [[ "$BUILD_GUI" -eq 1 && "$ALLOW_MXE_QT" == "1" ]]; then
        ensure_mxe
        setup_mxe_toolchain_env
        use_mxe_compiler_for_deps
        verify_mxe_toolchain
        log "ALLOW_MXE_QT=1: dependencies use the legacy MXE toolchain in $DEPS_DIR"
    fi

    build_mingw_dependencies

    if [[ "$BUILD_CLI" -eq 0 && "$BUILD_GUI" -eq 0 ]]; then
        print_summary
        exit 0
    fi

    [[ "$BUILD_GUI" -eq 1 ]] && ensure_qt
    [[ "$BUILD_CLI" -eq 1 ]] && build_cli
    [[ "$BUILD_GUI" -eq 1 ]] && build_gui
    print_summary
}

main "$@"
