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
name_owner() {
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetNameOwner "$1"
}
journal=state/nemo-grid-compensator/transaction.json
printf '{"old":{"adjust":[199,199]},"new":{"adjust":[198,198]},"files":[]}' >"$journal"
set +e
"$tool" --recover >unsafe.log 2>&1
status=$?
set -e
test "$status" = 78
test -f "$journal"
grep 'Keeping the recovery journal' unsafe.log
printf 'PASS: unsafe recovery exits 78 and retains its journal\n'
unlink "$journal"
"$tool" --watch --debounce 0.75 >crash-watch.log 2>&1 & watcher=$!
sleep 4
before=$(grep -c 'work area' crash-watch.log)
nemo=$(name_owner org.NemoDesktop)
incumbent=$(name_owner org.Cinnamon)
pid=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.GetConnectionUnixProcessID org.Cinnamon | tr -cd '0-9' | sed 's/^32//')
tr '\0' '\n' <"/proc/$pid/environ" | grep -Fx "DISPLAY=$DISPLAY"
kill -KILL "$pid"
for i in {1..30}; do
    grep -q 'Cinnamon disappeared' crash-watch.log && break
    sleep .1
done
grep 'Cinnamon disappeared' crash-watch.log
kill -0 "$watcher"
test "$(grep -c 'work area' crash-watch.log)" = "$before"
if [ "$(name_owner org.Cinnamon 2>/dev/null || true)" = "" ]; then
    cinnamon --replace >replacement.log 2>&1 &
fi
for i in {1..80}; do
    grep -q 'Cinnamon returned' crash-watch.log && [ "$(grep -c 'work area' crash-watch.log)" -gt "$before" ] && break
    sleep .1
done
grep 'Cinnamon returned' crash-watch.log
test "$(grep -c 'work area' crash-watch.log)" -gt "$before"
test "$(name_owner org.Cinnamon)" != "$incumbent"
test "$(name_owner org.NemoDesktop)" = "$nemo"
echo 'PASS: real compositor loss and replacement, no premature optimization or Nemo restart'
for run in 1 2; do
    previous=$(name_owner org.Cinnamon)
    cinnamon --replace >"replacement-$run.log" 2>&1 &
    for i in {1..70}; do
        if next=$(name_owner org.Cinnamon 2>/dev/null) && [ "$next" != "$previous" ]; then break; fi
        sleep .1
    done
    test "$(name_owner org.Cinnamon)" != "$previous"
done
for i in {1..20}; do
    grep -q 'Pausing compensation for 90 seconds' crash-watch.log && break
    sleep .1
done
grep 'Pausing compensation for 90 seconds' crash-watch.log
count=$(grep -c 'work area' crash-watch.log)
sleep 3
test "$(grep -c 'work area' crash-watch.log)" = "$count"
echo 'PASS: repeated compositor replacement opened the circuit breaker'

gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Logout 2
wait "$watcher"
echo 'PASS: watcher exited on Cinnamon logout after compositor recovery'
