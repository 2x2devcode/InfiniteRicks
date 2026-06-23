#!/usr/bin/env bash
#
# Build InfiniteRicks bootstrap.dat and a distributable .tar.gz with checksums.
#
# Usage:
#   ./contrib/make_bootstrap.sh
#   ./contrib/make_bootstrap.sh --datadir ~/.InfiniteRicks --full
#   ./contrib/make_bootstrap.sh --testnet --output-dir /tmp/bootstrap-out
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    printf 'ERROR: python3 is required\n' >&2
    exit 1
fi

exec python3 "$SCRIPT_DIR/make_bootstrap.py" "$@"
