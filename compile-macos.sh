#!/usr/bin/env bash
# Build InfiniteRicks macOS CLI and GUI binaries on a local Mac.
# Requires macOS, Xcode Command Line Tools, and Homebrew. Produces:
#   release/macos/InfiniteRicksd
#   release/macos/InfiniteRicks-cli
#   release/macos/InfiniteRicks-qt.app
#
# Usage:
#   ./compile-macos.sh
#   BUILD_CLI=0 ./compile-macos.sh
#   BUILD_GUI=0 ./compile-macos.sh
#   USE_UPNP=- ./compile-macos.sh
#   MACOSX_DEPLOYMENT_TARGET=11.0 ./compile-macos.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 2)}"
RELEASE_DIR="$ROOT/release/macos"
LOG_DIR="${LOG_DIR:-$RELEASE_DIR/logs}"
BUILD_STAMP="${BUILD_STAMP:-$(date +%Y%m%d-%H%M%S)}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/compile-macos-${BUILD_STAMP}.log}"
ERRORS_FILE="${ERRORS_FILE:-$LOG_DIR/compile-macos-${BUILD_STAMP}.errors.txt}"
BUILD_GUI="${BUILD_GUI:-1}"
BUILD_CLI="${BUILD_CLI:-1}"
USE_UPNP="${USE_UPNP:--}"
USE_QRCODE="${USE_QRCODE:-0}"
DEPLOY_APP="${DEPLOY_APP:-1}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '\n[%s] ==> %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(ts)" "$*" >&2; }
die() {
    printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        printf '[%s] ERROR: %s\n' "$(ts)" "$*" >> "$LOG_FILE" 2>/dev/null || true
        printf '[%s] Full build log: %s\n' "$(ts)" "$LOG_FILE" >&2
        printf '[%s] Error extract: %s\n' "$(ts)" "${ERRORS_FILE:-}" >&2
    fi
    exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

verify_file() {
    local file="$1" message="${2:-missing file: $1}"
    [[ -e "$file" ]] || die "$message"
}

write_error_extract() {
    local source="${1:-$LOG_FILE}"
    local destination="${2:-$ERRORS_FILE}"
    [[ -f "$source" ]] || return 0
    mkdir -p "$(dirname "$destination")"
    {
        echo "=== InfiniteRicks macOS build error extract ==="
        echo "Generated: $(date -Is)"
        echo "Source log: $source"
        echo
        echo "--- matching lines ---"
        grep -nE \
            'error:|undefined reference|ld:|fatal error:|cannot find -l|^\[.*\] ERROR:|make(\[[0-9]+\])?: \*\*\*' \
            "$source" 2>/dev/null | tail -n 200 || echo "(no matching error lines found)"
        echo
        echo "--- last 80 lines ---"
        tail -n 80 "$source" 2>/dev/null || true
    } > "$destination"
}

setup_logging() {
    mkdir -p "$LOG_DIR" "$RELEASE_DIR"
    : > "$LOG_FILE"
    ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/compile-macos-latest.log"
    ln -sfn "$(basename "$ERRORS_FILE")" "$LOG_DIR/compile-macos-latest.errors.txt"
    {
        echo "================================================================"
        echo " InfiniteRicks compile-macos.sh"
        echo " Started:     $(date -Is)"
        echo " Log file:    $LOG_FILE"
        echo " Errors file: $ERRORS_FILE"
        echo " ROOT:        $ROOT"
        echo " JOBS:        $JOBS"
        echo " BUILD_CLI:   $BUILD_CLI"
        echo " BUILD_GUI:   $BUILD_GUI"
        echo " USE_UPNP:    $USE_UPNP"
        echo " DEPLOY_APP:  $DEPLOY_APP"
        echo " Deploy tgt:  $MACOSX_DEPLOYMENT_TARGET"
        echo " Host:        $(uname -a 2>/dev/null || true)"
        echo " Arch:        $(uname -m 2>/dev/null || true)"
        echo "================================================================"
        echo
    } | tee -a "$LOG_FILE"
}

check_macos() {
    [[ "$(uname -s)" == "Darwin" ]] ||
        die "This script must run on macOS. Use compile-windows.sh on Ubuntu for Windows builds."
    xcode-select -p >/dev/null 2>&1 ||
        die "Xcode Command Line Tools are missing. Install them with: xcode-select --install"
    log "macOS $(sw_vers -productVersion 2>/dev/null || echo '?') ($(uname -m))"
}

find_brew() {
    if [[ -n "${HOMEBREW_PREFIX:-}" && -x "${HOMEBREW_PREFIX}/bin/brew" ]]; then
        echo "${HOMEBREW_PREFIX}/bin/brew"
    elif [[ -x /opt/homebrew/bin/brew ]]; then
        echo /opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        echo /usr/local/bin/brew
    elif need_cmd brew; then
        command -v brew
    else
        return 1
    fi
}

ensure_homebrew() {
    BREW="$(find_brew)" || die "Homebrew not found. Install it from https://brew.sh and rerun."
    export HOMEBREW_PREFIX="$("$BREW" --prefix)"
    export PATH="$HOMEBREW_PREFIX/bin:$PATH"
    log "Homebrew: $BREW (prefix=$HOMEBREW_PREFIX)"
}

brew_pkg_installed() {
    "$BREW" list --versions "$1" >/dev/null 2>&1
}

install_brew_deps() {
    local packages=(boost openssl@3 berkeley-db@4 qt@5 pkg-config)
    [[ "$USE_UPNP" == "-" ]] || packages+=(miniupnpc)
    [[ "$USE_QRCODE" == "1" ]] && packages+=(qrencode)

    local missing=()
    local package
    for package in "${packages[@]}"; do
        if brew_pkg_installed "$package"; then
            log "Homebrew package present: $package"
        else
            missing+=("$package")
        fi
    done
    if ((${#missing[@]})); then
        log "Installing Homebrew packages: ${missing[*]}"
        "$BREW" install "${missing[@]}"
    else
        log "All required Homebrew packages are installed"
    fi
}

brew_prefix() {
    "$BREW" --prefix "$1" 2>/dev/null
}

detect_boost_suffix() {
    local libdir="$1"
    if compgen -G "$libdir/libboost_system-mt.*" >/dev/null; then
        echo "-mt"
    elif compgen -G "$libdir/libboost_system.*" >/dev/null; then
        echo ""
    else
        die "Could not find libboost_system in $libdir"
    fi
}

detect_bdb_suffix() {
    local libdir="$1"
    if compgen -G "$libdir/libdb_cxx-4.8.*" >/dev/null; then
        echo "-4.8"
    elif compgen -G "$libdir/libdb_cxx.*" >/dev/null; then
        echo ""
    else
        die "Could not find libdb_cxx in $libdir"
    fi
}

detect_bdb_include() {
    local prefix="$1"
    if [[ -d "$prefix/include/db48" ]]; then
        echo "$prefix/include/db48"
    elif [[ -f "$prefix/include/db_cxx.h" ]]; then
        echo "$prefix/include"
    else
        die "Berkeley DB headers not found under $prefix/include"
    fi
}

resolve_paths() {
    OPENSSL_PREFIX="$(brew_prefix openssl@3)" || die "openssl@3 prefix missing"
    BOOST_PREFIX="$(brew_prefix boost)" || die "boost prefix missing"
    BDB_PREFIX="$(brew_prefix berkeley-db@4)" || die "berkeley-db@4 prefix missing"
    QT_PREFIX="$(brew_prefix qt@5)" || die "qt@5 prefix missing"

    OPENSSL_INCLUDE="$OPENSSL_PREFIX/include"
    OPENSSL_LIB="$OPENSSL_PREFIX/lib"
    BOOST_INCLUDE="$BOOST_PREFIX/include"
    BOOST_LIB="$BOOST_PREFIX/lib"
    BDB_INCLUDE="$(detect_bdb_include "$BDB_PREFIX")"
    BDB_LIB="$BDB_PREFIX/lib"
    BOOST_LIB_SUFFIX="$(detect_boost_suffix "$BOOST_LIB")"
    BDB_LIB_SUFFIX="$(detect_bdb_suffix "$BDB_LIB")"

    export PATH="$QT_PREFIX/bin:$PATH"
    need_cmd qmake || die "qmake not found in qt@5"
    verify_file "$OPENSSL_INCLUDE/openssl/ssl.h" "OpenSSL headers missing"
    verify_file "$BOOST_INCLUDE/boost/version.hpp" "Boost headers missing"
    verify_file "$BDB_INCLUDE/db_cxx.h" "Berkeley DB C++ header missing"

    log "OpenSSL: $OPENSSL_PREFIX"
    log "Boost: $BOOST_PREFIX (suffix=${BOOST_LIB_SUFFIX})"
    log "Berkeley DB: $BDB_PREFIX (suffix=${BDB_LIB_SUFFIX})"
    log "Qt: $QT_PREFIX ($(qmake -query QT_VERSION 2>/dev/null || true))"
}

build_cli() {
    [[ "$BUILD_CLI" == "1" ]] || { log "Skipping CLI"; return 0; }

    log "Building InfiniteRicksd and InfiniteRicks-cli with makefile.osx"
    local stage_log="$LOG_DIR/cli-${BUILD_STAMP}.log"
    ln -sfn "$(basename "$stage_log")" "$LOG_DIR/cli-latest.log"

    local upnp_value="-"
    local extra_includes=()
    local extra_libraries=()
    if [[ "$USE_UPNP" != "-" ]]; then
        local mini_prefix
        mini_prefix="$(brew_prefix miniupnpc)" ||
            die "miniupnpc missing; install it or set USE_UPNP=-"
        upnp_value="$USE_UPNP"
        extra_includes+=(-I"${mini_prefix}/include")
        extra_libraries+=(-L"${mini_prefix}/lib")
    fi

    set +e
    (
        cd "$ROOT/src"
        make -f makefile.osx clean || true
        rm -f leveldb/libleveldb.a leveldb/libmemenv.a
        make -C leveldb clean || true
        make -f makefile.osx -j"$JOBS" \
            CXX=clang++ \
            RELEASE=1 \
            USE_UPNP="$upnp_value" \
            MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
            OPENSSL_INCLUDE_PATH="$OPENSSL_INCLUDE" \
            OPENSSL_LIB_PATH="$OPENSSL_LIB" \
            BOOST_INCLUDE_PATH="$BOOST_INCLUDE" \
            BOOST_LIB_PATH="$BOOST_LIB" \
            BOOST_LIB_SUFFIX="$BOOST_LIB_SUFFIX" \
            BDB_INCLUDE_PATH="$BDB_INCLUDE" \
            BDB_LIB_PATH="$BDB_LIB" \
            BDB_LIB_SUFFIX="$BDB_LIB_SUFFIX" \
            INCLUDEPATHS="-I${ROOT}/src -I${ROOT}/src/obj -I${OPENSSL_INCLUDE} -I${BDB_INCLUDE} -I${BOOST_INCLUDE} ${extra_includes[*]+${extra_includes[*]}}" \
            LIBPATHS="-L${OPENSSL_LIB} -L${BDB_LIB} -L${BOOST_LIB} ${extra_libraries[*]+${extra_libraries[*]}}"
    ) 2>&1 | tee "$stage_log"
    local result=${PIPESTATUS[0]}
    set -e
    if [[ "$result" -ne 0 ]]; then
        write_error_extract "$stage_log" "$ERRORS_FILE"
        die "macOS CLI build failed; see $stage_log"
    fi

    verify_file "$ROOT/src/InfiniteRicksd" "InfiniteRicksd was not produced"
    verify_file "$ROOT/src/InfiniteRicks-cli" "InfiniteRicks-cli was not produced"
    cp -f "$ROOT/src/InfiniteRicksd" "$RELEASE_DIR/InfiniteRicksd"
    cp -f "$ROOT/src/InfiniteRicks-cli" "$RELEASE_DIR/InfiniteRicks-cli"
    chmod +x "$RELEASE_DIR/InfiniteRicksd" "$RELEASE_DIR/InfiniteRicks-cli"
    strip "$RELEASE_DIR/InfiniteRicksd" "$RELEASE_DIR/InfiniteRicks-cli" 2>/dev/null || true
    log "CLI artifacts: $RELEASE_DIR/InfiniteRicksd and InfiniteRicks-cli"
}

build_gui() {
    [[ "$BUILD_GUI" == "1" ]] || { log "Skipping GUI"; return 0; }

    log "Building InfiniteRicks-qt.app"
    local build_dir="$ROOT/build-macos-qt"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir"

    rm -f "$ROOT/src/leveldb/libleveldb.a" "$ROOT/src/leveldb/libmemenv.a"
    make -C "$ROOT/src/leveldb" clean >/dev/null 2>&1 || true

    local lrelease
    lrelease="$(command -v lrelease || command -v lrelease-qt5 || true)"
    [[ -n "$lrelease" ]] || lrelease="$QT_PREFIX/bin/lrelease"
    [[ -x "$lrelease" ]] || die "lrelease missing from qt@5"

    local qmake_args=(
        "RELEASE=1"
        "USE_UPNP=${USE_UPNP}"
        "USE_QRCODE=${USE_QRCODE}"
        "USE_DBUS=0"
        "BOOST_INCLUDE_PATH=${BOOST_INCLUDE}"
        "BOOST_LIB_PATH=${BOOST_LIB}"
        "BOOST_LIB_SUFFIX=${BOOST_LIB_SUFFIX}"
        "BOOST_THREAD_LIB_SUFFIX=${BOOST_LIB_SUFFIX}"
        "BDB_INCLUDE_PATH=${BDB_INCLUDE}"
        "BDB_LIB_PATH=${BDB_LIB}"
        "BDB_LIB_SUFFIX=${BDB_LIB_SUFFIX}"
        "OPENSSL_INCLUDE_PATH=${OPENSSL_INCLUDE}"
        "OPENSSL_LIB_PATH=${OPENSSL_LIB}"
        "QMAKE_MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}"
        "QMAKE_CXXFLAGS+=-std=c++17"
        "QMAKE_LRELEASE=${lrelease}"
    )

    if [[ "$USE_QRCODE" == "1" ]]; then
        local qr_prefix
        qr_prefix="$(brew_prefix qrencode)" || die "qrencode missing"
        qmake_args+=(
            "QRENCODE_INCLUDE_PATH=${qr_prefix}/include"
            "QRENCODE_LIB_PATH=${qr_prefix}/lib"
        )
    fi

    qmake "${qmake_args[@]}" "$ROOT/InfiniteRicks-qt.pro"

    local stage_log="$LOG_DIR/gui-${BUILD_STAMP}.log"
    ln -sfn "$(basename "$stage_log")" "$LOG_DIR/gui-latest.log"
    set +e
    make -j"$JOBS" 2>&1 | tee "$stage_log" | tee "$build_dir/build.log"
    local result=${PIPESTATUS[0]}
    set -e
    if [[ "$result" -ne 0 ]]; then
        write_error_extract "$stage_log" "$ERRORS_FILE"
        die "macOS GUI build failed; see $stage_log"
    fi

    local app=""
    app="$(find "$build_dir" "$ROOT" -maxdepth 3 -name 'InfiniteRicks-Qt.app' -type d 2>/dev/null | head -1 || true)"
    [[ -n "$app" ]] ||
        app="$(find "$build_dir" "$ROOT" -maxdepth 3 -name 'InfiniteRicks-qt.app' -type d 2>/dev/null | head -1 || true)"
    [[ -n "$app" ]] || die "InfiniteRicks-qt.app was not produced"

    rm -rf "$RELEASE_DIR/InfiniteRicks-qt.app"
    cp -R "$app" "$RELEASE_DIR/InfiniteRicks-qt.app"

    if [[ "$DEPLOY_APP" == "1" ]]; then
        local macdeploy
        macdeploy="$(command -v macdeployqt || true)"
        [[ -n "$macdeploy" ]] || macdeploy="$QT_PREFIX/bin/macdeployqt"
        if [[ -x "$macdeploy" ]]; then
            log "Bundling Qt frameworks with macdeployqt"
            "$macdeploy" "$RELEASE_DIR/InfiniteRicks-qt.app" -always-overwrite ||
                warn "macdeployqt failed; the app was left without bundled frameworks"
        else
            warn "macdeployqt not found; the target Mac may need Qt frameworks installed"
        fi
    fi

    log "GUI artifact: $RELEASE_DIR/InfiniteRicks-qt.app"
}

main() {
    check_macos
    ensure_homebrew
    install_brew_deps
    resolve_paths
    mkdir -p "$RELEASE_DIR" "$LOG_DIR"

    build_cli
    build_gui

    [[ "$BUILD_CLI" != "1" ]] || {
        verify_file "$RELEASE_DIR/InfiniteRicksd" "InfiniteRicksd artifact missing"
        verify_file "$RELEASE_DIR/InfiniteRicks-cli" "InfiniteRicks-cli artifact missing"
    }
    [[ "$BUILD_GUI" != "1" ]] ||
        verify_file "$RELEASE_DIR/InfiniteRicks-qt.app" "InfiniteRicks-qt.app artifact missing"
    log "macOS build completed successfully"
    log "Artifacts: $RELEASE_DIR"
}

run_with_log() {
    setup_logging
    local status_file
    status_file="$(mktemp)"
    set +e
    (
        set -euo pipefail
        main "$@"
        echo 0 > "$status_file"
    ) 2>&1 | tee -a "$LOG_FILE"
    local tee_result=${PIPESTATUS[0]}
    set -e
    local main_result=1
    [[ ! -f "$status_file" ]] || main_result="$(cat "$status_file" 2>/dev/null || echo 1)"
    rm -f "$status_file"
    if [[ "$main_result" != "0" || "$tee_result" -ne 0 ]]; then
        write_error_extract "$LOG_FILE" "$ERRORS_FILE"
        exit 1
    fi
}

run_with_log "$@"
