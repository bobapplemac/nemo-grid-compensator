#!/bin/bash
set -euo pipefail
"$STAGE/test-tools/usr/bin/Xvfb" -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp -ac 3>display-number >xvfb.log 2>&1 & server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
for i in {1..30}; do [ -s display-number ] && break; sleep .1; done
export DISPLAY=":$(cat display-number)"
if [ "${FRESH_DISABLED:-0}" = 1 ]; then
    gsettings set org.nemo.desktop show-desktop-icons false
fi
cinnamon-session --session cinnamon --failsafe >cinnamon.log 2>&1 &
for i in {1..30}; do
 if gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.IsSessionRunning 2>/dev/null | grep -q true; then break; fi
 sleep .2
done
tool="$STAGE/nemo-grid-compensator"
meta=config/nemo/desktop-metadata
test ! -e "$meta"
if [ "${FRESH_DISABLED:-0}" = 1 ]; then
    "$tool" --init --dry-run
    test ! -e "$meta"
    "$tool" --init
    test -f "$meta"
    test "$(gsettings get org.nemo.desktop show-desktop-icons)" = false
    if gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus         --method org.freedesktop.DBus.NameHasOwner org.NemoDesktop | grep -q true; then
        echo "Nemo Desktop started against the disabled preference"
        exit 1
    fi
    "$tool" --init
    echo 'PASS: fresh initialize leaves desktop icons disabled'
    exit 0
fi
"$tool" --init --dry-run
test ! -e "$meta"
"$tool" --init
grep -E 'desktop-grid-adjust|nemo-icon-view-(auto-layout|keep-aligned|zoom-level)' "$meta"
checkpoint=state/nemo-grid-compensator/grid.json
for i in $(seq -w 1 12); do touch "Desktop/fixture-$i.txt"; done
for i in {1..20}; do
    ready=yes
    for file in Desktop/*.txt; do
        if ! gio info -a metadata::nemo-icon-position "$file" | grep -q 'metadata::nemo-icon-position:'; then
            ready=no
            break
        fi
    done
    [ "$ready" = yes ] && break
    sleep .2
done
test "$ready" = yes
mode=${FAULT_CASE:?}
before=$(grep -E '^desktop-grid-adjust=|^nemo-icon-view-' "$meta" | sort)
status=0
/usr/bin/python3 "$STAGE/tests/release-fault.py" "$tool" "$mode" >fault.log 2>&1 || status=$?
cat fault.log
grep -q "INJECTED $mode" fault.log
test "$(gsettings get org.nemo.desktop show-desktop-icons)" = true
if [ "$mode" = logout-commit ] || [ "$mode" = logout-remap ]; then
    test "$status" = 0
    test -e state/nemo-grid-compensator/transaction.json
    "$tool" --recover
else
    test "$status" = 1
    test "$(grep -E '^desktop-grid-adjust=|^nemo-icon-view-' "$meta" | sort)" = "$before"
fi
test ! -e state/nemo-grid-compensator/transaction.json
echo "PASS: $mode preserved native settings and recoverability"
