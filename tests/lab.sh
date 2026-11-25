#!/bin/bash
set -euo pipefail
stage=$(cd "$(dirname "$0")/.." && pwd)
export STAGE="$stage"
profile=$(mktemp -d "$STAGE/profile.XXXXXX")
cd "$profile"
mkdir -p config data state cache run Desktop
chmod 700 run
export XDG_CONFIG_HOME="$PWD/config" XDG_DATA_HOME="$PWD/data" XDG_STATE_HOME="$PWD/state" XDG_CACHE_HOME="$PWD/cache" XDG_RUNTIME_DIR="$PWD/run"
export XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_DESKTOP=cinnamon DESKTOP_SESSION=cinnamon
export NO_AT_BRIDGE=1 XAUTHORITY=/dev/null
export LD_LIBRARY_PATH="$STAGE/test-tools/usr/lib/x86_64-linux-gnu"
printf 'XDG_DESKTOP_DIR="%s/Desktop"\n' "$PWD" >config/user-dirs.dirs
echo "Lab profile: $profile"
dbus-run-session -- bash "$STAGE/tests/session-tests.sh" >session.log 2>&1
