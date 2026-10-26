#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for script in build.sh verify-on-device.sh scripts/check.sh layout/DEBIAN/*; do
    sh -n "$script"
done
python3 -m unittest discover -s tests -p 'test_*.py' -v
out=$(mktemp)
prefout=$(mktemp)
trap 'rm -f "$out" "$prefout"' EXIT
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

if [ "$(uname -s)" = Darwin ]; then
    clang -fobjc-arc -Wall -Wextra -Werror -I. -framework Foundation -framework CoreFoundation tests/test_preferences.m -o "$prefout"
    "$prefout"
    clang -fobjc-arc -Wall -Wextra -Werror -I. -framework Foundation tests/test_runtime.m -o "$prefout"
    "$prefout"
else
    echo 'Foundation preference/runtime tests require macOS; executed by GitHub CI.'
fi
