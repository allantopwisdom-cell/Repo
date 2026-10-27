#!/bin/sh
# Read-only snapshot for the original v1.3.4 GitHub release. No private API calls.
set -u
PC_DOMAIN=com.minis.powercuff-baldaran-trusted
PC_VERSION=1.3.4
pc_stage=baseline
pc_failures=0
pc_unknown=0
case "${1:-}" in
    --help|-h)
        printf '%s\n' 'Usage: sh Powercuff-1.3.4-device-check.sh [--label baseline|off-before|light|off-after|lpm-off|lpm-on]'
        printf '%s\n' 'Run as mobile. Output is a snapshot, never stable-release approval.'
        exit 0 ;;
    --label)
        [ "$#" -eq 2 ] || { echo 'A single stage label is required.' >&2; exit 2; }
        pc_stage=$2 ;;
    '') [ "$#" -eq 0 ] || { echo 'Invalid arguments.' >&2; exit 2; } ;;
    *) echo 'Unknown option; use --help.' >&2; exit 2 ;;
esac
case "$pc_stage" in baseline|off-before|light|off-after|lpm-off|lpm-on) : ;;
    *) echo 'Unknown stage label; use --help.' >&2; exit 2 ;;
esac

pc_fail() { pc_failures=$((pc_failures + 1)); printf 'CHECK-FAILED: %s\n' "$*"; }
pc_unverified() { pc_unknown=$((pc_unknown + 1)); printf 'UNVERIFIED: %s\n' "$*"; }
pc_uid=$(id -u 2>/dev/null) || { echo 'Cannot verify user identity.' >&2; exit 2; }
if [ "$pc_uid" != 501 ]; then
    echo 'Run as mobile (UID 501), not root or another user. No checks were performed.' >&2
    exit 2
fi

printf '%s\n' 'Powercuff v1.3.4 device acceptance snapshot / tool v1'
printf 'Stage: %s (manually supplied; not automatic LPM detection)\n' "$pc_stage"
printf 'UTC: '; date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unavailable
printf '%s\n' 'Reference DEB SHA256: 9d1a20f0c68aaa7600573c2b6381bd5de5df521020c342c75a4b637e411f9ee6'
printf '%s\n' 'This tool does not change preferences, post notifications, restart services or delete files.'

printf '\n%s\n' '[Target]'
pc_model=$(sysctl -n hw.machine 2>/dev/null) || pc_model=
pc_ios=$(sysctl -n kern.osproductversion 2>/dev/null) || pc_ios=
pc_build=$(sysctl -n kern.osversion 2>/dev/null) || pc_build=
printf 'Model: %s / iOS: %s / build: %s\n' "${pc_model:-unavailable}" "${pc_ios:-unavailable}" "${pc_build:-unavailable}"
if [ -z "$pc_model" ]; then pc_unverified 'Device model could not be read.'
elif [ "$pc_model" != iPhone15,3 ]; then pc_fail 'Device differs from the iPhone15,3 acceptance target.'; fi
if [ -z "$pc_ios" ]; then pc_unverified 'iOS version could not be read.'
elif [ "$pc_ios" != 16.5 ]; then pc_fail 'iOS differs from the 16.5 acceptance target.'; fi
if [ -n "$pc_build" ] && [ "$pc_build" != 20F66 ]; then pc_fail 'OS build differs from 20F66.'; fi
printf '%s\n' 'Confirm RootHide Dopamine 3.0.4 in the jailbreak app; package versions alone do not prove it.'

printf '\n%s\n' '[Installed package]'
pc_package_paths=
if command -v dpkg-query >/dev/null 2>&1; then
    pc_status=$(dpkg-query -W -f='${Status}' "$PC_DOMAIN" 2>/dev/null) || pc_status=
    pc_version=$(dpkg-query -W -f='${Version}' "$PC_DOMAIN" 2>/dev/null) || pc_version=
    pc_arch=$(dpkg-query -W -f='${Architecture}' "$PC_DOMAIN" 2>/dev/null) || pc_arch=
    printf 'Status: %s / version: %s / architecture: %s\n' "${pc_status:-unavailable}" "${pc_version:-unavailable}" "${pc_arch:-unavailable}"
    [ "$pc_status" = 'install ok installed' ] || pc_fail 'Powercuff is not confirmed fully installed.'
    [ "$pc_version" = "$PC_VERSION" ] || pc_fail 'Installed package is not v1.3.4.'
    [ "$pc_arch" = iphoneos-arm64e ] || pc_fail 'Installed package architecture is not iphoneos-arm64e.'
    pc_package_paths=$(dpkg-query -L "$PC_DOMAIN" 2>/dev/null) || pc_package_paths=
else
    pc_unverified 'dpkg-query unavailable; package identity cannot be checked.'
fi

pc_resolve() {
    pc_logical=$1
    if command -v jbroot >/dev/null 2>&1; then
        pc_mapped=$(jbroot "$pc_logical" 2>/dev/null) || pc_mapped=
        case "$pc_mapped" in /*)
            if [ -f "$pc_mapped" ]; then printf '%s\n' "$pc_mapped"; return 0; fi ;;
        esac
    fi
    if [ -f "$pc_logical" ]; then printf '%s\n' "$pc_logical"; return 0; fi
    printf '%s\n' "$pc_package_paths" | while IFS= read -r pc_candidate; do
        case "$pc_candidate" in /*"$pc_logical")
            if [ -f "$pc_candidate" ]; then printf '%s\n' "$pc_candidate"; break; fi ;;
        esac
    done
}
pc_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
    fi
}
printf '\n%s\n' '[On-disk payload vs original release]'
while read -r pc_expected pc_logical; do
    pc_path=$(pc_resolve "$pc_logical")
    if [ -z "$pc_path" ]; then pc_unverified "Cannot resolve $pc_logical"; continue; fi
    if [ ! -r "$pc_path" ]; then pc_fail "Not readable by mobile: $pc_logical"; continue; fi
    pc_digest=$(pc_hash "$pc_path")
    if [ "$pc_digest" = "$pc_expected" ]; then
        printf 'DISK-MATCH: %s\n' "$pc_logical"
    elif [ -z "$pc_digest" ]; then pc_unverified "Cannot hash $pc_logical"
    else
        pc_unverified "DISK-DIFF: $pc_logical (installer patching/resigning may change bytes; investigate before blaming corruption)"
        printf '  Observed SHA256: %s\n' "$pc_digest"
    fi
done <<'PC_PAYLOAD'
f31882309f4b34493c82bf77409b759d1215d8681bf30777fe111498abc8aae9 /Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted.dylib
151c39eeff63c2d1cd2bb16085f49fe575f9e733214d620152243fd60fe78a6d /Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted.plist
d1fde6133793623369755c10e3fe59412399ba5f0278672f2b020f217ee492a0 /Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff.plist
bd06cc513c9c68e5b4b7d5df34733efb565733843ede76622af8d878d0ee046a /Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff@2x.png
54e1ac92512ecb3c44d4b5da803e532c4862f67a10838b9627f61699aeca5b65 /Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff@3x.png
22dcbf2f67960e69b9aac957ee57f2d288c749f7e05be13c9957426d3fe6319c /Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/icon.png
PC_PAYLOAD
printf '%s\n' 'Matching disk bytes do not prove an already running process reloaded that file.'

printf '\n%s\n' '[Process snapshots]'
for pc_process in SpringBoard thermalmonitord; do
    if command -v pgrep >/dev/null 2>&1; then
        pc_pids=$(pgrep -x "$pc_process" 2>/dev/null) || pc_pids=
        if [ -z "$pc_pids" ]; then pc_fail "No visible $pc_process process at collection time."; continue; fi
        for pc_pid in $pc_pids; do
            case "$pc_pid" in ''|*[!0-9]*) pc_unverified 'Unexpected PID output.'; continue ;; esac
            printf '%s PID=%s\n' "$pc_process" "$pc_pid"
            ps -p "$pc_pid" -o pid=,etime=,comm= 2>/dev/null || pc_unverified 'Cannot read process elapsed time.'
        done
    else pc_unverified "pgrep unavailable: $pc_process liveness not checked."; fi
done

printf '\n%s\n' '[Only Powercuff preference keys]'
for pc_key in PowerMode RequireLowPowerMode; do
    if command -v defaults >/dev/null 2>&1; then
        if pc_raw=$(defaults read "$PC_DOMAIN" "$pc_key" 2>/dev/null); then
            printf '%s=%s\n' "$pc_key" "$pc_raw"
        else pc_unverified "$pc_key missing or unreadable; a missing key alone is not a plugin fault."; fi
    else pc_unverified "defaults unavailable: $pc_key not read."; fi
done

printf '\n%s\n' '[Notify state: cached, not liveness or physical throttling proof]'
pc_request_value= pc_mode_value= pc_applied_value=
for pc_key in loaded.s loaded.t hook request thermals applied; do
    if ! command -v notifyutil >/dev/null 2>&1; then pc_unverified "notifyutil unavailable: $pc_key"; continue; fi
    pc_raw=$(notifyutil -g "$PC_DOMAIN.$pc_key" 2>/dev/null) || pc_raw=
    printf '%s\n' "${pc_raw:-$pc_key unavailable}"
    # Apple's utility can print an error and still exit 0; validate key AND value.
    pc_value=$(printf '%s\n' "$pc_raw" | awk -v key="$PC_DOMAIN.$pc_key" 'NF == 2 && $1 == key && $2 ~ /^[0-9]+$/ { print $2; n++ } END { if (n != 1) exit 1 }') || pc_value=
    if [ -z "$pc_value" ]; then pc_unverified "Unrecognized or failed notification read: $pc_key"; continue; fi
    case "$pc_key" in
        loaded.s|loaded.t|hook) [ "$pc_value" = 1 ] || pc_unverified "Marker $pc_key is not 1; inspect injection and fresh logs." ;;
        request) pc_request_value=$pc_value ;;
        thermals) pc_mode_value=$pc_value ;;
        applied)
            pc_applied_value=$pc_value
            case "$pc_value" in
                0|1|2|3|4) : ;;
                10) pc_unverified 'Waiting for a valid response (10).' ;;
                11) pc_fail 'Transport timeout (11); the previous profile may still be active.' ;;
                98|99) pc_fail 'Exception/ABI diagnostic (98/99), possibly cached; correlate with process reload and fresh logs.' ;;
                *) pc_unverified 'Unknown applied diagnostic.' ;;
            esac ;;
    esac
done

# Protocol v2 values fit in signed 64 bits and have 19 decimal digits beginning 5.
# Avoid arithmetic on arbitrary-length/leading-zero strings or a 32-bit shell.
case "$pc_request_value:$pc_mode_value" in 5*:5*) pc_numeric_pair=yes ;; *) pc_numeric_pair=no ;; esac
if [ "$pc_numeric_pair" = yes ] && [ "${#pc_request_value}" -eq 19 ] && [ "${#pc_mode_value}" -eq 19 ] && [ "$((1 << 40))" = 1099511627776 ]; then
    pc_session=$(((pc_request_value >> 8) & 4294967295))
    pc_mode=$((pc_mode_value & 255))
    if [ "$((pc_request_value >> 40))" -eq "$((0x504302))" ] && [ "$((pc_request_value & 255))" -eq 165 ] && [ "$pc_session" -ne 0 ] && [ "$((pc_request_value >> 8))" -eq "$((pc_mode_value >> 8))" ] && [ "$pc_mode" -le 4 ]; then
        printf 'SESSION-MATCH: session=%s, published mode=%s\n' "$pc_session" "$pc_mode"
    else pc_unverified 'Request/reply session or protocol differs; repeat a quiet snapshot (reads are not atomic).'; fi
else pc_unverified 'Cannot safely decode the sampled session pair.'; fi
case "$pc_stage" in
    off-before|off-after|lpm-off) pc_expected_mode=0 ;;
    light|lpm-on) pc_expected_mode=2 ;;
    *) pc_expected_mode= ;;
esac
if [ -n "$pc_expected_mode" ] && [ "$pc_applied_value" != "$pc_expected_mode" ]; then
    pc_fail "Manual stage $pc_stage expects applied=$pc_expected_mode; observed ${pc_applied_value:-unknown}."
fi

printf '\n%s\n' '[Relevant crash filenames only; old files are not new failures]'
set --
for pc_file in /var/mobile/Library/Logs/CrashReporter/thermalmonitord* /var/mobile/Library/Logs/CrashReporter/panic-full*; do
    [ -f "$pc_file" ] || continue
    set -- "$@" "$pc_file"
done
printf 'Visible relevant files: %s; listing the newest 20 only (contents are not read).\n' "$#"
if [ "$#" -gt 0 ]; then
    if command -v ls >/dev/null 2>&1; then
        ls -1t "$@" 2>/dev/null | awk 'NR <= 20 { sub(/^.*\//, ""); print }'
    else pc_unverified 'Cannot sort crash filenames.'; fi
fi
printf '\nCHECK-FAILED=%s UNVERIFIED=%s\n' "$pc_failures" "$pc_unknown"
printf '%s\n' 'NOT-RELEASE-APPROVAL: no PAC, real throttling, watchdog endurance or battery result is implied.'
if [ "$pc_failures" -gt 0 ]; then exit 1; fi
if [ "$pc_unknown" -gt 0 ]; then exit 3; fi
exit 0
