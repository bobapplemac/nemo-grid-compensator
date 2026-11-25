#!/bin/sh
set -eu
[ "$(id -u)" != 0 ] || { echo "Run this installer as the desktop user." >&2; exit 1; }
case "${1:-}" in
    "") start=no ;;
    --start) start=yes ;;
    *) echo "Usage: $0 [--start]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for command in systemd-run systemctl xrandr xwininfo xprop stdbuf gsettings flock; do
    command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
/usr/bin/python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gio, Gtk; assert Gio.SettingsSchemaSource.get_default().lookup("org.nemo.desktop", True), "Nemo is required"'
if [ "$start" = yes ]; then
    [ "${XDG_SESSION_TYPE:-}" = x11 ] && [ -n "${DISPLAY:-}" ] && [ -n "${XDG_SESSION_ID:-}" ] ||
        { echo "Run --start from an X11 Cinnamon login." >&2; exit 1; }
    systemctl --user show-environment >/dev/null
fi
install_atomic() {
    source=$1 destination=$2 mode=$3
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        echo "Refusing to replace $destination." >&2
        exit 1
    fi
    if [ -f "$destination" ] && cmp -s "$source" "$destination" && [ "$(stat -c %a "$destination")" = "$mode" ]; then
        return
    fi
    dir=$(dirname -- "$destination")
    mkdir -p -- "$dir"
    tmp=$(mktemp "$dir/.nemo-grid-install.XXXXXX")
    trap 'unlink "$tmp"' EXIT HUP INT TERM
    install -m "$mode" -- "$source" "$tmp"
    mv -fT -- "$tmp" "$destination"
    trap - EXIT HUP INT TERM
}
target="$HOME/.local/bin/nemo-grid-compensator"
changed=no
cmp -s "$here/nemo-grid-compensator" "$target" || changed=yes
install_atomic "$here/nemo-grid-compensator" "$target" 755
launcher="$HOME/.local/libexec/nemo-grid-compensator-session"
cmp -s "$here/startup/nemo-grid-compensator-session" "$launcher" || changed=yes
install_atomic "$here/startup/nemo-grid-compensator-session" "$launcher" 755
install_atomic "$here/startup/nemo-grid-compensator.desktop" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/nemo-grid-compensator.desktop" 644
if [ "$start" = yes ]; then
    if [ "$changed" = yes ] && systemctl --user is-active --quiet nemo-grid-compensator.service; then
        systemctl --user stop nemo-grid-compensator.service
    fi
    if ! systemctl --user is-active --quiet nemo-grid-compensator.service; then
        "$launcher"
    fi
fi
"$target" --version
