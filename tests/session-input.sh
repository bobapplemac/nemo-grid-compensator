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
/usr/bin/python3 "$STAGE/tests/drag.py" "$tool"
"$tool" --watch >active.log 2>&1 & watcher=$!
for i in {1..30}; do grep -q 'work area' active.log && break; sleep .2; done
before=$(grep -c 'work area' active.log)
owner() {
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetNameOwner org.NemoDesktop
}
old=$(owner)
pid=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.GetConnectionUnixProcessID org.NemoDesktop | sed -En 's/^\(uint32 ([0-9]+),\)$/\1/p')
tr '\0' '\n' <"/proc/$pid/environ" | grep -Fx "DISPLAY=$DISPLAY"
kill -KILL "$pid"
for i in {1..40}; do
    if now=$(owner 2>/dev/null) && [ "$old" != "$now" ]; then break; fi
    sleep .2
done
test "$(owner)" != "$old"
for i in {1..20}; do
    if [ "$(grep -c 'work area' active.log)" -gt "$before" ]; then break; fi
    sleep .2
done
test "$(grep -c 'work area' active.log)" -gt "$before"
grep 'Existing spacing and icon positions' active.log | tail -n 1
kill -0 "$watcher"
echo 'PASS: Nemo unexpectedly exited, Cinnamon restarted it and the watcher reconciled'
kill -TERM "$watcher"
wait "$watcher"
! pgrep -P "$watcher" -x xprop
echo 'PASS: clean watcher shutdown reaped its X11 helper'
