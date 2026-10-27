#!/bin/sh
# Read-only; run in NewTerm as mobile for the same preference view as Settings.
DOMAIN=com.minis.powercuff-baldaran-trusted
printf 'Powercuff diagnostics (notification values can be stale; not proof of liveness)\n'
if command -v id >/dev/null 2>&1; then
    if [ "$(id -u)" = 0 ]; then
        echo 'Root defaults are not the mobile preference domain. Repeat as mobile.'
    fi
fi
for f in /Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted.dylib \
         /Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted.plist \
         /Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff.plist; do
    p=$f
    if command -v jbroot >/dev/null 2>&1; then
        mapped=$(jbroot "$f" 2>/dev/null) && [ -n "$mapped" ] && p=$mapped
    fi
    if [ -f "$p" ]; then echo "FOUND $p"; else echo "UNRESOLVED $f (check dpkg -L $DOMAIN)"; fi
 done
if command -v defaults >/dev/null 2>&1; then
    defaults read "$DOMAIN" 2>/dev/null || echo 'No readable domain: a new install defaults to Off.'
fi
if command -v notifyutil >/dev/null 2>&1; then
    for key in loaded.s loaded.t hook thermals applied; do
        echo "--- $key ---"
        notifyutil -g "$DOMAIN.$key" 2>/dev/null || echo 'unavailable'
    done
else
    echo 'notifyutil unavailable: use Console logs, subsystem com.minis.powercuff-baldaran-trusted.'
fi
cat <<'HELP'
loaded.*=1: loader ran at least once; hook=1: product initializer was observed.
applied 0..4: private method returned; 10: waiting; 11: transport timeout/stale mode possible;
98: ObjC exception; 99: ABI mismatch. State 11 does not mean the previous profile was cleared.
thermals contains a versioned 64-bit word with a daemon session; stale-session replies are rejected.
Neither published nor applied state proves CPU throttling or battery improvement.
Test Off -> Light -> Off, then the LPM gate, and inspect fresh daemon logs/crash reports.
HELP
