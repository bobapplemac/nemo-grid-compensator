#!/bin/bash
set -euo pipefail
stage=$(cd "$(dirname "$0")/.." && pwd)
export STAGE="$stage"
profile=$(mktemp -d "$stage/login.XXXXXX")
cd "$profile"
echo "Login profile: $profile"
mkdir -p home config data state cache Desktop system-config
export HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/config" XDG_DATA_HOME="$PWD/data"
export XDG_STATE_HOME="$PWD/state" XDG_CACHE_HOME="$PWD/cache" XDG_CONFIG_DIRS="$PWD/system-config"
export XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_DESKTOP=cinnamon DESKTOP_SESSION=cinnamon
export NO_AT_BRIDGE=1 XAUTHORITY=/dev/null LD_LIBRARY_PATH="$stage/test-tools/usr/lib/x86_64-linux-gnu"
printf 'XDG_DESKTOP_DIR="%s/Desktop"\n' "$PWD" >config/user-dirs.dirs
if [ "${INSTALL_DURING_SESSION:-0}" = 1 ]; then
    # A private source copy gives the default-start test its own unit name,
    # including when installation refreshes the launcher. Never touch the
    # installed watcher belonging to the normal login.
    mkdir -p source/startup source/test-bin
    cp "$stage/install.sh" "$stage/uninstall.sh" "$stage/nemo-grid-compensator" source/
    cp "$stage/startup/nemo-grid-compensator.desktop" source/startup/
    sed 's/--unit=nemo-grid-compensator /--unit=nemo-grid-compensator-login-test /' \
        "$stage/startup/nemo-grid-compensator-session" >source/startup/nemo-grid-compensator-session
    # Match the installer's status/stop probes to the private launcher's unit.
    cat >source/test-bin/systemctl <<'SH'
#!/bin/bash
args=()
for arg do
    [ "$arg" != nemo-grid-compensator.service ] || arg=nemo-grid-compensator-login-test.service
    args+=("$arg")
done
exec /usr/bin/systemctl "${args[@]}"
SH
    chmod 755 source/test-bin/systemctl
    export INSTALL_SOURCE="$PWD/source"
else
    "$stage/install.sh" --no-start
    "$stage/install.sh" --no-start
    sed -i 's/--unit=nemo-grid-compensator /--unit=nemo-grid-compensator-login-test /' "$HOME/.local/libexec/nemo-grid-compensator-session"
fi
server="$stage/test-tools/usr/bin/Xvfb"
"$server" -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp -ac 3>display-number >xvfb.log 2>&1 &
xvfb=$!
trap 'kill "$xvfb" 2>/dev/null || true' EXIT
for i in {1..30}; do [ -s display-number ] && break; sleep .1; done
export DISPLAY=":$(cat display-number)"
echo "Isolated logind session: $XDG_SESSION_ID, display: $DISPLAY"
dbus-run-session -- bash "$stage/tests/login-session.sh" >session.log 2>&1 || { tail -n 40 session.log; exit 1; }
tail -n 22 session.log
