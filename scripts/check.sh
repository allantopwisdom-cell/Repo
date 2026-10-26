#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for script in build.sh verify-on-device.sh scripts/check.sh layout/DEBIAN/*; do
    sh -n "$script"
done
python3 -m unittest discover -s tests -p 'test_*.py' -v
out=$(mktemp)
trap 'rm -f "$out"' EXIT
cc -std=c11 -Wall -Wextra -Werror -I. tests/test_protocol.c -o "$out"
"$out"
python3 - <<'PY'
from pathlib import Path
import plistlib
for path in Path('.').rglob('*.plist'):
    if not any(x in path.parts for x in ('theos-roothide', '.theos')):
        plistlib.loads(path.read_bytes())
print('plist syntax PASS')
PY
