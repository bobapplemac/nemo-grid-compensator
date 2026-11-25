# Re-run validation on Debian 13

These tests require the Debian/Cinnamon runtime packages listed in the
[README](../README.md#install-and-initialize), plus `bash`, `xauth`, and
`dbus-run-session` (Debian package `dbus-daemon`). The input test also needs
`libx11-6` and `libxtst6`. The extracted display-server instructions below
assume Debian amd64, matching the harness's library path. They are not a
Windows test procedure.

The non-graphical regression suite can be run separately on Linux with the
real PyGObject/GTK dependencies installed:

```sh
/usr/bin/python3 tests/test_release.py
```

Installer regression coverage runs separately as the same non-root user:

```sh
/usr/bin/python3 tests/test_install.py -v
```

It requires both curl and wget for coverage of both download paths, in addition
to the runtime dependencies above. It serves controlled archives on loopback
HTTP and uses download shims to redirect the installer's fixed GitHub HTTPS
request to that fixture. No GitHub access, Git executable, live service changes,
or writes to the user's real home are involved. It covers stdin, standalone,
local checkout/archive, ref selection and encoding, same-archive inputs,
reinstallation/state preservation, offline removal, dependency detection,
`--start` delegation with a simulated supervisor, archive rejection, HTTP
errors, recursion prevention, and interruption cleanup. Real graphical
startup/upgrade/removal remains covered by the separate PAM/logind harness.
See the [installer validation report](../docs/installer-validation.md) for
the recorded results and the limits of the controlled transport fixture.

As the desktop user, extract Debian's test display server into the checkout.
This step downloads packages and does not install them.

```sh
mkdir -p test-tools
(
  cd test-tools
  apt-get download xvfb xserver-common libxfont2
  for package in ./*.deb; do dpkg-deb -x "$package" .; done
)
bash tests/run.sh
# The suite includes the rc2 recovery and partial-profile cases.
bash tests/lab.sh  # Optional 80-icon benchmark against the archived polling fixture
```

The isolated harness inherits `XDG_SESSION_TYPE` from the invoking session.
When running through SSH rather than an X11 desktop terminal, use
`XDG_SESSION_TYPE=x11 bash tests/run.sh` (and the same prefix for individual
lab scripts). The harness creates its own Xvfb display and private session
bus; do not point it at the live desktop display or bus.

Test profiles have a private Xvfb display, session bus, and XDG directories.
The scripts print each profile location and write the detail to its
`session.log`. The circuit breaker test deliberately terminates or replaces
only the isolated Cinnamon process. Test fixtures simulate selected transaction
events and use an XTest button hold for the input check.

For the real login path, run the following on a development VM with a systemd
user manager. Run from the checkout as the desktop user. PAM
creates a separate X11 login. The utility stays unprivileged. The test unit
has its own name and cannot collide with the installed watcher.

```sh
sudo systemd-run --unit=nemo-grid-login-validation --wait --pipe --collect \
  --property="User=$(id -un)" --property=PAMName=login \
  --setenv=XDG_SESSION_TYPE=x11 --setenv=XDG_SESSION_CLASS=user \
  --setenv=XDG_SESSION_DESKTOP=cinnamon \
  "$PWD/tests/login-lab.sh"
```

A separate real login should remain active for the shared user-manager
shutdown check. The harness installs twice, exercises startup and logout,
upgrades the test executable, then uninstalls twice. The optional prior
hardened executable can be saved as `reviewed-baseline` at the checkout
root. If absent the upgrade test uses a copy marked with an older version.
That fallback checks replacement and metadata preservation; it does not
establish compatibility with an actual older build.

`tests/baseline` is the archived polling prototype used only by the optional
idle benchmark. It is intentionally retained to reproduce the historical
comparison and is not an alternate supported application. Fault-injection
helpers and the rc2-specific harness are regression fixtures, not obsolete
prototypes.

Generated `profile.*` and `login.*` directories remain in the checkout for
inspection and are ignored by Git, along with `test-tools/`. These profiles
contain logs and synthetic desktop metadata; do not publish them as personal
desktop captures. See the [validation history](../docs/test-results.md) for
the distinction between isolated, injected, and live VM coverage.
