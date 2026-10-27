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
version=$(sed -n 's/^Version: //p' control)
package="packages/com.minis.powercuff-baldaran-trusted_${version}_iphoneos-arm64e.deb"
test -f "$package"
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    epoch=$SOURCE_DATE_EPOCH
else
    epoch=$(git log -1 --format=%ct) || {
        echo 'Set SOURCE_DATE_EPOCH when building a source archive without Git metadata.' >&2
        exit 1
    }
fi
python3 scripts/normalize_package.py "$package" --epoch "$epoch"
# Redirect before cat: POSIX sh pipelines must not hide a failing validator behind tee.
python3 scripts/verify_package.py "$package" --version "$version" --source-root . > packages/verification.txt
python3 scripts/test_built_package.py "$package" >> packages/verification.txt
cat packages/verification.txt
