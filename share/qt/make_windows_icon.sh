#!/bin/bash
# create multiresolution windows icon
ICON_DST=../../src/qt/res/icons/infinitericksico.ico

convert ../../src/qt/res/icons/infinitericks-16.png ../../src/qt/res/icons/infinitericks-32.png ../../src/qt/res/icons/infinitericks-48.png ${ICON_DST}
