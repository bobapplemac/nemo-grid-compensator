#!/bin/sh
set -eu
[ "$(id -u)" != 0 ] || { echo "Run this uninstaller as the desktop user." >&2; exit 1; }
purge=no
stop=yes
for option do
    case "$option" in
        --purge-state) purge=yes ;;
        --files-only) stop=no ;;
        *) echo "Usage: $0 [--purge-state] [--files-only]" >&2; exit 2 ;;
    esac
done
state="${XDG_STATE_HOME:-$HOME/.local/state}/nemo-grid-compensator"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
service=nemo-grid-compensator.service
if [ "$stop" = yes ]; then
    systemctl --user show-environment >/dev/null
    if systemctl --user is-active --quiet "$service"; then
        systemctl --user stop "$service"
    fi
fi
if [ -d "$state" ]; then
    [ ! -L "$state/lock" ] || { echo "Unexpected lock symlink." >&2; exit 1; }
    exec 9>>"$state/lock"
    flock -n 9 || { echo "Stop the running compensator before uninstalling." >&2; exit 1; }
fi
if [ -e "$state/transaction.json" ] || [ -L "$state/transaction.json" ]; then
    echo "A transaction is pending. Review and run nemo-grid-compensator --recover first." >&2
    exit 1
fi
rm -f -- "$config/autostart/nemo-grid-compensator.desktop" \
    "$HOME/.local/bin/nemo-grid-compensator" "$HOME/.local/libexec/nemo-grid-compensator-session"
if [ "$purge" = yes ] && [ -d "$state" ]; then
    rm -f -- "$state/grid.json" "$state/compositor.json" "$state/interactive-watch.log" "$state/lock"
    rmdir -- "$state"
fi
echo "Removed Nemo Grid Compensator. Nemo settings and icon positions were retained."
