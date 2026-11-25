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
has_desktop() {
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.NemoDesktop | grep -q true
}
wait_for_visibility() {
    target=$1
    for i in {1..35}; do
        if has_desktop; then active=true; else active=false; fi
        [ "$target" != "$active" ] || return 0
        sleep .15
    done
    return 1
}
journal=state/nemo-grid-compensator/transaction.json
for kind in layout initialization; do
    for phase in held prepared released; do
        gsettings set org.nemo.desktop show-desktop-icons false
        wait_for_visibility false
        /usr/bin/python3 - "$journal" "$kind" "$phase" <<'PY'
import json,sys
path,kind,phase=sys.argv[1:]
if kind=="initialization":
    data=dict(initialization=True, restore_icons=True, writing=phase!="prepared",
              old=["before"], new=["after"])
else:
    data=dict(old={"adjust":[199,199]}, new={"adjust":[198,198]}, files=[])
data["visibility"]=phase
with open(path,"w") as f: json.dump(data,f)
PY
        status=0
        "$tool" --recover >"recovery-$kind-$phase.log" 2>&1 || status=$?
        test "$status" = 78
        test -s "$journal"
        if [ "$phase" = held ]; then
            test "$(gsettings get org.nemo.desktop show-desktop-icons)" = true
            grep -q '"visibility": "released"' "$journal"
            wait_for_visibility true
        else
            test "$(gsettings get org.nemo.desktop show-desktop-icons)" = false
            wait_for_visibility false
        fi
        unlink "$journal"
        echo "PASS: ambiguous $kind recovery with visibility $phase"
    done
done
# Prepare an established grid with spacing and one missing required key.
sed -i '/^nemo-icon-view-zoom-level=/d' "$meta"
cp "$meta" expected-partial
"$tool" --watch --initialize >partial.log 2>&1 & watcher=$!
for i in {1..40}; do
    grep -q 'Partial Nemo grid configuration' partial.log && break
    sleep .15
done
grep -q -- '--init --dry-run' partial.log
kill -TERM "$watcher"
wait "$watcher"
cmp expected-partial "$meta"
"$tool" --init --dry-run
cmp expected-partial "$meta"
"$tool" --init
grep -q '^nemo-icon-view-zoom-level=3$' "$meta"
test "$(grep '^desktop-grid-adjust=' "$meta")" = "$(grep '^desktop-grid-adjust=' expected-partial)"
test "$(gsettings get org.nemo.desktop show-desktop-icons)" = false
echo "PASS: partial profile required explicit initialization and retained its spacing and visibility"
