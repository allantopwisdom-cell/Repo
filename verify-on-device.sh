#!/bin/sh
# Read-only self-check for PowerCuff Baldaran Trusted (RootHide).
# Run on the device as root:  sh verify-on-device.sh
# It never changes any setting.

DOMAIN=com.minis.powercuff-baldaran-trusted
THERMALS="$DOMAIN.thermals"
SETTINGS="$DOMAIN.settingschanged"

# RootHide keeps jailbreak files under a random root; jbroot() maps a
# jailbreak-relative path to its real location.
jb() {
    if command -v jbroot >/dev/null 2>&1; then jbroot "$1"; else printf '%s' "$1"; fi
}

echo "== 1. installed files =="
for f in /Library/MobileSubstrate/DynamicLibraries/Powercuff.dylib \
         /Library/MobileSubstrate/DynamicLibraries/Powercuff.plist \
         /Library/PreferenceLoader/Preferences/Powercuff/Powercuff.plist; do
    p=$(jb "$f")
    if [ -f "$p" ]; then echo "  OK   $f"; else echo "  MISS $f"; fi
done

echo "== 2. preferences (cfprefsd view) =="
if command -v defaults >/dev/null 2>&1; then
    defaults read "$DOMAIN" 2>/dev/null || echo "  (domain not readable yet; open Settings once)"
else
    echo "  defaults not available"
fi

echo "== 3. published thermal state =="
if command -v notifyutil >/dev/null 2>&1; then
    v=$(notifyutil -g "$THERMALS" 2>/dev/null)
    case "$v" in
        0|"") echo "  state=${v:-0}  -> Off (stock)" ;;
        1) echo "  state=1  -> Nominal" ;;
        2) echo "  state=2  -> Light" ;;
        3) echo "  state=3  -> Moderate" ;;
        4) echo "  state=4  -> Heavy" ;;
        *) echo "  state=$v  -> unexpected" ;;
    esac
else
    echo "  notifyutil not available"
fi

echo "== 4. daemon status =="
if command -v launchctl >/dev/null 2>&1; then
    launchctl list 2>/dev/null | grep -i thermalmonitord || echo "  thermalmonitord not listed"
fi

echo
echo "How to read the result:"
echo "  - All three files OK and state=0 means installed, defaulting to Off."
echo "  - Set Profile=Moderate in Settings, wait 2s, rerun: state should become 3."
echo "  - Set Profile=Off and rerun: state must return to 0."
echo "  - If state never changes, the tweak is not loaded into SpringBoard:"
echo "    respring once, then re-check."
