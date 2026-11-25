#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 tests/test_release.py
RUN_BENCH=0 bash tests/lab.sh
FRESH_DISABLED=1 bash tests/lab.sh
bash tests/lab-crash.sh
bash tests/lab-input.sh
bash tests/lab-rc2.sh
for mode in logout-prepared logout-stopped logout-gvfs logout-commit logout-remap \
    create rename delete mount unmount gio-busy fs-busy dbus-timeout; do
    FAULT_CASE="$mode" bash tests/lab-release.sh
done
