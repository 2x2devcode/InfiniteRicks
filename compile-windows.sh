#!/usr/bin/env bash
#
# Cross-compile InfiniteRicks Windows binaries on Ubuntu 22.04/24.04.
# Produces InfiniteRicksd.exe (CLI) and InfiniteRicks-qt.exe (GUI).
#
# Usage:
#   ./compile-windows.sh              # build CLI + GUI
#   ./compile-windows.sh --cli-only   # daemon only
#   ./compile-windows.sh --gui-only   # wallet only (requires MXE)
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
JOBS="$(nproc 2>/dev/null || echo 2)"

OPENSSL_VERSION="1.1.1w"
BDB_VERSION="5.3.28.NC"
BOOST_VERSION="1.83.0"
MINIUPNPC_VERSION="2.2.6"
ZLIB_VERSION="1.3.1"

log()  { printf '\n==> %s\n' "$*"; }
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
  --skip-mxe       Do not build MXE/Qt (GUI build fails if Qt is missing)
  --arch x86_64    64-bit Windows target (default)
  --arch i686      32-bit Windows target (not supported: code uses __int128)
  --jobs N         Parallel build jobs (default: nproc)
  --help           Show this help

Environment variables:
  MINGW_DEPS_DIR   Dependency prefix (default: ~/.infinite-ricks/mingw-deps)
  MXE_PATH         MXE installation directory (default: $MINGW_DEPS_DIR/mxe)
  MINGW_OUTPUT_DIR Output directory (default: ./windows-build)
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
    DEPS_DIR="${MINGW_DEPS_DIR:-$HOME/.infinite-ricks/mingw-deps-${ARCH}}"
    MXE_DIR="${MXE_PATH:-$DEPS_DIR/mxe}"
    SOURCES_DIR="${MINGW_SOURCES_DIR:-$DEPS_DIR/sources}"
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
        cmake
        ninja-build
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
    [[ -f "$DEPS_DIR/lib/libssl.a" && -f "$DEPS_DIR/lib/libcrypto.a" ]] && return 0

    local tarball="$SOURCES_DIR/openssl-${OPENSSL_VERSION}.tar.gz"
    download_file "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "$tarball"

    local build_dir="$SOURCES_DIR/openssl-${OPENSSL_VERSION}-build"
    rm -rf "$build_dir"
    tar xzf "$tarball" -C "$SOURCES_DIR"
    mv "$SOURCES_DIR/openssl-${OPENSSL_VERSION}" "$build_dir"

    log "Building OpenSSL ${OPENSSL_VERSION} for ${ARCH}"
    pushd "$build_dir" >/dev/null
    # Configure applies --cross-compile-prefix; avoid exporting toolchain vars here.
    env -u CC -u CXX -u AR -u RANLIB ./Configure "$OPENSSL_TARGET" \
        --cross-compile-prefix="${MINGW_PREFIX}-" \
        --prefix="$DEPS_DIR" \
        no-shared no-tests
    make -j"$JOBS" \
        CC="${MINGW_PREFIX}-gcc" \
        CXX="${MINGW_PREFIX}-g++" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib"
    make install_sw \
        CC="${MINGW_PREFIX}-gcc" \
        CXX="${MINGW_PREFIX}-g++" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib"
    popd >/dev/null
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
        CC="${MINGW_PREFIX}-gcc" \
        CXX="${MINGW_PREFIX}-g++" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib" \
        CFLAGS="$mingw_cflags" \
        CXXFLAGS="$mingw_cflags" \
        ../dist/configure \
            --build="$(gcc -dumpmachine)" \
            --host="${MINGW_PREFIX}" \
            --prefix="$DEPS_DIR" \
            --enable-cxx \
            --disable-shared \
            --enable-mingw \
            --program-transform-name='s,.exe,,;s,\(.*\),\1.exe,'
    patch_berkeley_db_after_configure "$src_dir/build_unix"
    # Do not pass CFLAGS/CXXFLAGS to make: that replaces the generated flags
    # and drops -I../src (dbinc/win_db.h) from CPPFLAGS.
    make -j"$JOBS" \
        CC="${MINGW_PREFIX}-gcc" \
        CXX="${MINGW_PREFIX}-g++" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib"
    make install \
        CC="${MINGW_PREFIX}-gcc" \
        CXX="${MINGW_PREFIX}-g++" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib"
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
        CC="${MINGW_PREFIX}-gcc" \
        AR="${MINGW_PREFIX}-ar" \
        RANLIB="${MINGW_PREFIX}-ranlib" \
        ./configure --prefix="$DEPS_DIR" --static
    make -j"$JOBS" libz.a
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

build_leveldb() {
    log "Building LevelDB for Windows (${ARCH})"
    pushd "$SRC_DIR/leveldb" >/dev/null
    make clean >/dev/null 2>&1 || true
    CC="$CC" CXX="$CXX" TARGET_OS=OS_WINDOWS_CROSSCOMPILE \
        make -j"$JOBS" libleveldb.a libmemenv.a
    "$RANLIB" libleveldb.a
    "$RANLIB" libmemenv.a
    popd >/dev/null
}

build_cli() {
    log "Building InfiniteRicksd.exe"
    build_leveldb
    pushd "$SRC_DIR" >/dev/null
    make -f makefile.linux-mingw clean >/dev/null 2>&1 || true
    make -f makefile.linux-mingw \
        -j"$JOBS" \
        DEPSDIR="$DEPS_DIR" \
        TARGET_PLATFORM="$ARCH" \
        USE_UPNP=1
    cp InfiniteRicksd.exe "$OUTPUT_DIR/"
    popd >/dev/null
    log "CLI binary: $OUTPUT_DIR/InfiniteRicksd.exe"
}

ensure_mxe() {
  [[ "$BUILD_GUI" -eq 1 ]] || return 0
  [[ "$BUILD_MXE_QT" -eq 1 ]] || return 0

  local qmake_bin="$MXE_DIR/usr/bin/${MXE_TARGET}-qmake-qt5"
  if [[ -x "$qmake_bin" ]]; then
      log "MXE Qt already available at $MXE_DIR"
      return 0
  fi

  log "MXE/Qt for MinGW not found; setting up MXE (this can take a long time)"
  if [[ ! -d "$MXE_DIR/.git" ]]; then
      git clone https://github.com/mxe/mxe.git "$MXE_DIR"
  fi

  local settings="$MXE_DIR/settings.mk"
  cat > "$settings" <<EOF
MXE_TARGETS := ${MXE_TARGET}
JOBS := ${JOBS}
EOF

  pushd "$MXE_DIR" >/dev/null
  make qtbase -j"$JOBS" MXE_TARGETS="${MXE_TARGET}"
  popd >/dev/null

  [[ -x "$qmake_bin" ]] || die "MXE qmake not found after build: $qmake_bin"
}

build_gui() {
    log "Building InfiniteRicks-qt.exe"
    ensure_mxe

    local qmake_bin="$MXE_DIR/usr/bin/${MXE_TARGET}-qmake-qt5"
    local mxe_qt_bin="$MXE_DIR/usr/${MXE_TARGET}/qt5/bin"
    local gui_build_dir="$REPO_ROOT/build-win-qt-${ARCH}"

    build_leveldb

    rm -rf "$gui_build_dir"
    mkdir -p "$gui_build_dir"

    pushd "$gui_build_dir" >/dev/null
  "$qmake_bin" \
        -spec win32-g++ \
        "$REPO_ROOT/InfiniteRicks-qt.pro" \
        RELEASE=1 \
        USE_UPNP=1 \
        BOOST_LIB_SUFFIX= \
        BOOST_THREAD_LIB_SUFFIX= \
        BOOST_INCLUDE_PATH="$DEPS_DIR/include" \
        BOOST_LIB_PATH="$DEPS_DIR/lib" \
        BDB_INCLUDE_PATH="$DEPS_DIR/include" \
        BDB_LIB_PATH="$DEPS_DIR/lib" \
        OPENSSL_INCLUDE_PATH="$DEPS_DIR/include" \
        OPENSSL_LIB_PATH="$DEPS_DIR/lib" \
        MINIUPNPC_INCLUDE_PATH="$DEPS_DIR/include/miniupnpc" \
        MINIUPNPC_LIB_PATH="$DEPS_DIR/lib"

    make -j"$JOBS"

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

    mkdir -p "$OUTPUT_DIR/qt-runtime"
    if [[ -d "$mxe_qt_bin" ]]; then
        cp -n "$mxe_qt_bin"/Qt5*.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$mxe_qt_bin"/libgcc_s_*.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$mxe_qt_bin"/libstdc++-6.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
        cp -n "$mxe_qt_bin"/libwinpthread-1.dll "$OUTPUT_DIR/qt-runtime/" 2>/dev/null || true
    fi

    log "GUI binary: $OUTPUT_DIR/InfiniteRicks-qt.exe"
    log "Qt runtime DLLs (if any): $OUTPUT_DIR/qt-runtime/"
}

print_summary() {
    log "Build complete"
    printf '  Architecture : %s\n' "$ARCH"
    printf '  Dependencies : %s\n' "$DEPS_DIR"
    printf '  Output dir   : %s\n' "$OUTPUT_DIR"
    [[ -f "$OUTPUT_DIR/InfiniteRicksd.exe" ]] && printf '  CLI          : %s\n' "$OUTPUT_DIR/InfiniteRicksd.exe"
    [[ -f "$OUTPUT_DIR/InfiniteRicks-qt.exe" ]] && printf '  GUI          : %s\n' "$OUTPUT_DIR/InfiniteRicks-qt.exe"
}

main() {
    parse_args "$@"
    resolve_paths
    install_apt_packages
    prepare_dirs
    setup_toolchain
    build_mingw_dependencies

    if [[ "$BUILD_CLI" -eq 0 && "$BUILD_GUI" -eq 0 ]]; then
        print_summary
        exit 0
    fi

    [[ "$BUILD_CLI" -eq 1 ]] && build_cli
    [[ "$BUILD_GUI" -eq 1 ]] && build_gui
    print_summary
}

main "$@"
