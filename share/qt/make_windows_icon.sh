#!/bin/bash
# Create multiresolution Windows icon from InfiniteRicks brand PNGs
# (Rick portal logo — same artwork as splash.png / infinitericksico.ico)
set -euo pipefail
cd "$(dirname "$0")"
ICON_DST=../../src/qt/res/icons/infinitericks.ico
convert \
  ../../src/qt/res/icons/infinitericks-16.png \
  ../../src/qt/res/icons/infinitericks-32.png \
  ../../src/qt/res/icons/infinitericks-48.png \
  ../../src/qt/res/icons/infinitericks-128.png \
  ../../src/qt/res/icons/infinitericks.png \
  "${ICON_DST}"
