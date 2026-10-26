#!/bin/sh
set -eu
cd "$(dirname "$0")"
variant="${1:-roothide}"
if [ "$variant" != roothide ]; then
    echo "Unknown variant: $variant" >&2
    exit 1
fi
: "${THEOS:?Set THEOS to the RootHide Theos checkout}"
export THEOS_PACKAGE_SCHEME=roothide
make clean
make package DEBUG=0 FINALPACKAGE=1 messages=yes
