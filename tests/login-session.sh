#!/bin/bash
set -euo pipefail
manager() { DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" systemctl --user "$@"; }
unit=nemo-grid-compensator-login-test.service
trap 'manager stop "$unit" >/dev/null 2>&1 || true' EXIT
cinnamon-session --session cinnamon >cinnamon.log 2>&1 &
if [ "${INSTALL_DURING_SESSION:-0}" = 1 ]; then
    for i in {1..45}; do
        if gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager \
            --method org.gnome.SessionManager.IsSessionRunning 2>/dev/null | grep -q true; then break; fi
        sleep .2
    done
    PATH="$INSTALL_SOURCE/test-bin:$PATH" "$INSTALL_SOURCE/install.sh"
    for i in {1..45}; do
        if manager is-active --quiet "$unit" && [ -e "$XDG_STATE_HOME/nemo-grid-compensator/grid.json" ]; then break; fi
        sleep .2
    done
    manager is-active --quiet "$unit"
    test -e "$XDG_STATE_HOME/nemo-grid-compensator/grid.json"
    grep -q '^nemo-icon-view-auto-layout=false$' "$XDG_CONFIG_HOME/nemo/desktop-metadata"
    grep -q '^nemo-icon-view-keep-aligned=true$' "$XDG_CONFIG_HOME/nemo/desktop-metadata"
    grep -q '^nemo-icon-view-zoom-level=3$' "$XDG_CONFIG_HOME/nemo/desktop-metadata"
    echo 'PASS: default installation initialized and started the supervised watcher in the current session'
    # Let Nemo finish its initial metadata save and the watcher settle before
    # comparing a repeat install against the running desktop.
    sleep 3
    pid=$(manager show "$unit" -p MainPID --value)
    cp "$XDG_CONFIG_HOME/nemo/desktop-metadata" expected-metadata
    PATH="$INSTALL_SOURCE/test-bin:$PATH" "$INSTALL_SOURCE/install.sh"
    test "$(manager show "$unit" -p MainPID --value)" = "$pid"
    cmp expected-metadata "$XDG_CONFIG_HOME/nemo/desktop-metadata"
    echo 'PASS: repeated default installation retained the active watcher and desktop metadata'
    gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Logout 2
    for i in {1..45}; do
        if ! manager is-active --quiet "$unit"; then break; fi
        sleep .2
    done
    ! manager is-active --quiet "$unit"
    manager show-environment >/dev/null
    "$HOME/.local/libexec/nemo-grid-compensator-uninstall" --files-only --purge-state
    echo 'PASS: default-start watcher stopped on logout; offline removal preserved the shared user manager'
    exit 0
fi
for i in {1..45}; do
    if manager is-active --quiet "$unit" && [ -e "$XDG_STATE_HOME/nemo-grid-compensator/grid.json" ]; then break; fi
    sleep .4
done
manager show "$unit" -p ActiveState -p MainPID -p NRestarts
manager is-active --quiet "$unit"
test -e "$XDG_STATE_HOME/nemo-grid-compensator/grid.json"
grep 'desktop-grid-adjust=' "$XDG_CONFIG_HOME/nemo/desktop-metadata"
echo 'PASS: XDG graphical login launched the supervised service and initialized the fresh profile'
gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.Logout 2
for i in {1..45}; do
    if ! manager is-active --quiet "$unit"; then break; fi
    sleep .3
done
! manager is-active --quiet "$unit"
manager show-environment >/dev/null
echo 'PASS: graphical logout stopped the watcher and preserved the user manager'
signature=$(grep -E '^desktop-grid-adjust=|^nemo-icon-view-' "$XDG_CONFIG_HOME/nemo/desktop-metadata" | sort)
if [ -f "$STAGE/reviewed-baseline" ]; then
    install -m 0755 "$STAGE/reviewed-baseline" "$HOME/.local/bin/nemo-grid-compensator"
else
    sed "s/0.1.0rc2/0.0.0-test/" "$STAGE/nemo-grid-compensator" >"$HOME/.local/bin/nemo-grid-compensator"
fi
"$STAGE/install.sh" --no-start
test "$("$HOME/.local/bin/nemo-grid-compensator" --version)" = "nemo-grid-compensator 0.1.0rc2"
test "$signature" = "$(grep -E '^desktop-grid-adjust=|^nemo-icon-view-' "$XDG_CONFIG_HOME/nemo/desktop-metadata" | sort)"
echo 'PASS: upgrade preserved saved Nemo layout'
test -x "$HOME/.local/libexec/nemo-grid-compensator-uninstall"
"$HOME/.local/libexec/nemo-grid-compensator-uninstall" --files-only --purge-state
"$STAGE/uninstall.sh" --files-only --purge-state
test ! -e "$HOME/.local/bin/nemo-grid-compensator"
test ! -e "$HOME/.local/libexec/nemo-grid-compensator-uninstall"
test ! -e "$XDG_CONFIG_HOME/autostart/nemo-grid-compensator.desktop"
test ! -e "$XDG_STATE_HOME/nemo-grid-compensator"
test "$signature" = "$(grep -E '^desktop-grid-adjust=|^nemo-icon-view-' "$XDG_CONFIG_HOME/nemo/desktop-metadata" | sort)"
echo 'PASS: repeated removal purged program state and preserved native settings'
