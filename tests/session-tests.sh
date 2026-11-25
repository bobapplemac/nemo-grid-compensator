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
grep -E 'desktop-grid-adjust|nemo-icon-view-(auto-layout|keep-aligned|zoom-level)' "$meta" | sort >expected-keys
name_owner() {
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus         --method org.freedesktop.DBus.GetNameOwner org.NemoDesktop
}
owner=$(name_owner)
"$tool" --init
grep -E 'desktop-grid-adjust|nemo-icon-view-(auto-layout|keep-aligned|zoom-level)' "$meta" | sort | cmp expected-keys -
test "$(name_owner)" = "$owner"
echo "PASS: repeated init preserved grid keys and the existing Nemo Desktop process"
gsettings set org.nemo.desktop show-desktop-icons false
sleep .5
"$tool" --init
test "$(gsettings get org.nemo.desktop show-desktop-icons)" = false
gsettings set org.nemo.desktop show-desktop-icons true
sleep .5
count=80
if [ "${RUN_BENCH:-1}" = 0 ]; then count=12; fi
for i in $(seq -w 1 "$count"); do touch "Desktop/fixture-$i.txt"; done
sleep 2
sample() {
    pid="$1"
    printf 'pid=%s elapsed=%s ' "$pid" "$(date +%s.%N)"
    tr '\n' ' ' <"/proc/$pid/schedstat"
    grep -E '^(VmRSS|voluntary_ctxt_switches|nonvoluntary_ctxt_switches)' "/proc/$pid/status" | tr '\n' ' '
    echo
}
bench() {
    "$1" --watch >"$2.log" 2>&1 & watcher=$!
    sleep 4
    sample "$watcher"
    sleep 20
    sample "$watcher"
    kill "$watcher"
    wait "$watcher" || true
    grep -E 'Watching|work area|Skipping' "$2.log"
}
if [ "${RUN_BENCH:-1}" = 1 ]; then
    bench "$STAGE/tests/baseline" baseline
    bench "$tool" event
else
    for phase in stopped gvfs committed; do
        set +e
        /usr/bin/python3 "$STAGE/tests/fault.py" "$tool" "$phase" >"fault-$phase.log" 2>&1
        status=$?
        set -e
        if [ "$status" != 86 ]; then cat "fault-$phase.log"; exit 1; fi
        test "$(gsettings get org.nemo.desktop show-desktop-icons)" = false
        "$tool" --recover
        test "$(gsettings get org.nemo.desktop show-desktop-icons)" = true
        test ! -e state/nemo-grid-compensator/transaction.json
        echo "PASS: interrupted transaction at $phase recovered"
        sleep .7
    done
fi
"$tool" --watch >active.log 2>&1 & watcher=$!
sleep 4
if "$tool" --once >duplicate.log 2>&1; then echo "Lock regression"; exit 1; fi
grep 'process is running' duplicate.log
echo "Checkpoint count $(/usr/bin/python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["cells"]))' "$checkpoint")"
if [ "${RUN_BENCH:-1}" = 0 ]; then
    before=$(grep -c 'work area' active.log)
    read -r old new < <(/usr/bin/python3 - "$checkpoint" <<'PY2'
import json,sys
grid=json.load(open(sys.argv[1]))
cells=grid["cells"]
icon=next(value for key,value in cells.items() if key.endswith("/fixture-01.txt"))
h,v=grid["adjust"]
pitch=int(130*(h/100))
x,y=icon["xy"]
print(f"{x},{y}",f"{x+10*pitch},{y}")
PY2
    )
    gio set Desktop/fixture-01.txt metadata::nemo-icon-position "$new"
    sleep 1
    grep -q "xy.*" "$checkpoint"
    /usr/bin/python3 - "$checkpoint" "$new" <<'PY2'
import json,sys
cells=json.load(open(sys.argv[1]))["cells"]
assert next(v["xy"] for k,v in cells.items() if k.endswith("/fixture-01.txt"))==list(map(int,sys.argv[2].split(",")))
PY2
    test "$before" = "$(grep -c 'work area' active.log)"
    echo "PASS: GVfs position checkpoint without optimization"
    gio set Desktop/fixture-01.txt metadata::nemo-icon-position "$old"
    sleep .4
    xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "0, 0, 1920, 1025"
    xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "0, 0, 1920, 1020"
    xprop -root -f _GTK_WORKAREAS_D0 32c -set _GTK_WORKAREAS_D0 "0, 0, 1920, 1020"
    sleep 1.5
    grep -q 'work area 1920x1020' active.log
    test "$(grep -c 'work area 1920x10[02][05]' active.log)" = 1
    echo "PASS: work-area notifications coalesced"
    mv Desktop/fixture-02.txt Desktop/renamed-fixture.txt
    sleep 2
    grep -q 'renamed-fixture.txt' "$checkpoint"
    echo "PASS: desktop rename triggers reevaluation"
fi
gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Logout 2
for i in {1..30}; do if ! kill -0 "$watcher" 2>/dev/null; then break; fi; sleep .2; done
wait "$watcher"
echo 'Watcher exited on Cinnamon logout'
