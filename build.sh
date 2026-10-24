#!/bin/sh
set -e
variant="${1:-roothide}"
if [ "$variant" != "roothide" ]; then
    echo "Unknown variant: $variant" >&2
    exit 1
fi
export THEOS_PACKAGE_SCHEME=roothide
make clean 2>/dev/null || true
make package messages=yes
