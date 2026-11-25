#!/bin/sh
set -eu
[ "$(id -u)" != 0 ] || { echo "Run this installer as the desktop user." >&2; exit 1; }
start=auto
ref=main
remote=no
while [ "$#" -gt 0 ]; do
    case "$1" in
        --start) start=yes ;;
        --no-start) start=no ;;
        --ref)
            [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--ref requires a branch, tag, or commit." >&2; exit 2; }
            ref=$2 remote=yes
            shift ;;
        --ref=*)
            ref=${1#--ref=} remote=yes
            [ -n "$ref" ] || { echo "--ref must not be empty." >&2; exit 2; } ;;
        *) echo "Usage: $0 [--start|--no-start] [--ref BRANCH|TAG|COMMIT]" >&2; exit 2 ;;
    esac
    shift
done
case "$ref" in
    -*) echo "--ref requires a branch, tag, or commit, not another option." >&2; exit 2 ;;
esac

download_dir=
install_tmp=
cleanup() {
    [ -z "$install_tmp" ] || rm -f -- "$install_tmp"
    [ -z "$download_dir" ] || rm -rf -- "$download_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# A piped script has no source directory. A standalone downloaded installer
# also bootstraps; a complete checkout/archive installs directly unless --ref
# explicitly requests another revision.
here=
if [ -f "$0" ]; then
    here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi
for file in nemo-grid-compensator uninstall.sh startup/nemo-grid-compensator-session startup/nemo-grid-compensator.desktop; do
    if [ -z "$here" ] || [ ! -f "$here/$file" ]; then
        remote=yes
        break
    fi
done
if [ "${NEMO_GRID_COMPENSATOR_LOCAL:-}" = 1 ] && [ "$remote" = yes ]; then
    echo "Downloaded installer lacks its local files or tried to bootstrap again." >&2
    exit 1
fi
if [ "$remote" = yes ]; then
    [ -x /usr/bin/python3 ] || { echo "Missing dependency: /usr/bin/python3" >&2; exit 1; }
    encoded_ref=$(/usr/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ref")
    url="https://api.github.com/repos/bobapplemac/nemo-grid-compensator/tarball/$encoded_ref"
    download_dir=$(mktemp -d "${TMPDIR:-/tmp}/nemo-grid-download.XXXXXX")
    archive="$download_dir/repository.tar.gz"
    echo "Downloading Nemo Grid Compensator ($ref)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --output "$archive" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only --timeout=30 --tries=2 -O "$archive" "$url"
    else
        echo "Missing download tool: install curl or wget." >&2
        exit 1
    fi
    # Validate the entire member inventory before writing any source files.
    # Copy only the installation inputs, never extract paths chosen by tar.
    /usr/bin/python3 - "$archive" "$download_dir/source" <<'PY'
from pathlib import Path, PurePosixPath
import gzip
import io
import sys
import tarfile

archive, destination = map(Path, sys.argv[1:])
required = {"install.sh", "uninstall.sh", "nemo-grid-compensator",
            "startup/nemo-grid-compensator-session", "startup/nemo-grid-compensator.desktop"}
try:
    if archive.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("archive exceeds 16 MiB")
    # Read through the gzip footer as well as the tar inventory, so a truncated
    # download or CRC failure cannot hide behind tar's end-of-archive blocks.
    with gzip.open(archive, "rb") as stream:
        contents = stream.read(64 * 1024 * 1024 + 1)
    if len(contents) > 64 * 1024 * 1024:
        raise ValueError("expanded archive exceeds 64 MiB")
    with tarfile.open(fileobj=io.BytesIO(contents), mode="r:") as bundle:
        members = {}
        roots = set()
        total = 0
        for item in bundle:
            name = item.name.rstrip("/")
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or "\\" in name
                    or any(part in ("", ".", "..") for part in name.split("/"))
                    or name in members or not (item.isfile() or item.isdir())):
                raise ValueError("unsafe, duplicate, or non-regular archive member")
            roots.add(path.parts[0])
            members[name] = item
            total += item.size
            if len(members) > 10000 or total > 64 * 1024 * 1024:
                raise ValueError("archive contents exceed limits")
        if len(roots) != 1:
            raise ValueError("expected one repository root directory")
        root = roots.pop()
        sources = {}
        for relative in required:
            item = members.get(f"{root}/{relative}")
            if item is None or not item.isfile() or not 0 < item.size <= 4 * 1024 * 1024:
                raise ValueError(f"missing or invalid installation file: {relative}")
            sources[relative] = bundle.extractfile(item).read()
        compile(sources["nemo-grid-compensator"], "nemo-grid-compensator", "exec")
        for relative, data in sources.items():
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
except (OSError, ValueError, EOFError, SyntaxError, tarfile.TarError) as error:
    sys.exit(f"Invalid repository archive: {error}")
PY
    for script in install.sh uninstall.sh startup/nemo-grid-compensator-session; do
        sh -n "$download_dir/source/$script"
    done
    set --
    case "$start" in
        yes) set -- --start ;;
        no) set -- --no-start ;;
    esac
    NEMO_GRID_COMPENSATOR_LOCAL=1 sh "$download_dir/source/install.sh" "$@"
    exit 0
fi

for command in systemd-run systemctl xrandr xwininfo xprop stdbuf gsettings flock; do
    command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
/usr/bin/python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gio, Gtk; assert Gio.SettingsSchemaSource.get_default().lookup("org.nemo.desktop", True), "Nemo is required"'
if [ "$start" = auto ]; then
    if [ "${XDG_SESSION_TYPE:-}" = x11 ] && [ -n "${DISPLAY:-}" ] && [ -n "${XDG_SESSION_ID:-}" ]; then
        start=yes
    else
        start=no
    fi
fi
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
    install_tmp=$(mktemp "$dir/.nemo-grid-install.XXXXXX")
    install -m "$mode" -- "$source" "$install_tmp"
    mv -fT -- "$install_tmp" "$destination"
    install_tmp=
}
target="$HOME/.local/bin/nemo-grid-compensator"
changed=no
cmp -s "$here/nemo-grid-compensator" "$target" || changed=yes
install_atomic "$here/nemo-grid-compensator" "$target" 755
launcher="$HOME/.local/libexec/nemo-grid-compensator-session"
cmp -s "$here/startup/nemo-grid-compensator-session" "$launcher" || changed=yes
install_atomic "$here/startup/nemo-grid-compensator-session" "$launcher" 755
install_atomic "$here/startup/nemo-grid-compensator.desktop" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/nemo-grid-compensator.desktop" 644
install_atomic "$here/uninstall.sh" "$HOME/.local/libexec/nemo-grid-compensator-uninstall" 755
if [ "$start" = yes ]; then
    if [ "$changed" = yes ] && systemctl --user is-active --quiet nemo-grid-compensator.service; then
        systemctl --user stop nemo-grid-compensator.service
    fi
    if ! systemctl --user is-active --quiet nemo-grid-compensator.service; then
        state="${XDG_STATE_HOME:-$HOME/.local/state}/nemo-grid-compensator"
        # Configure a first installation before starting supervision. Existing
        # checkpoints and interrupted transactions keep their normal recovery
        # path; upgrades do not reset an established profile.
        if [ ! -e "$state/grid.json" ] && [ ! -L "$state/grid.json" ] &&
           [ ! -e "$state/transaction.json" ] && [ ! -L "$state/transaction.json" ]; then
            "$target" --init
        fi
        "$launcher"
    fi
fi
"$target" --version
if [ "$start" = yes ]; then
    echo "Service started or already running. Automatic startup is configured for future Cinnamon logins."
    echo "Check status: systemctl --user status nemo-grid-compensator.service"
else
    echo "Installed with automatic startup for the next Cinnamon login."
    echo "To start now, run ~/.local/libexec/nemo-grid-compensator-session from your X11 Cinnamon session."
fi
