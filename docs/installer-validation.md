# Remote installer validation

Validated on November 25, 2026, on the Debian 13 Trixie development VM with
Cinnamon 6.4.10 and Nemo 6.4.5. This is follow-up coverage for the installer
changes after the initial RC2 import; it does not replace the
[release candidate validation history](test-results.md).

## Controlled archive tests

`/usr/bin/python3 tests/test_install.py -v` passed all 15 tests. Each test
uses a disposable home, configuration, state, temporary directory, and a
loopback HTTP archive server. Download shims redirect the production GitHub
URL to that server while invoking real curl or wget. Git is absent from the
test PATH. No test mirror option was added to the production installer.

Coverage includes:

- Bash stdin installation with curl and wget, a standalone downloaded
  installer, and offline local checkout and extracted-source installation.
- Default `main`, explicit branch/tag/commit refs, slash encoding, and `--ref`
  overriding a local checkout. Installed application and launcher contents
  were checked against the selected fixture revision, with final file modes.
- Reinstallation with Nemo metadata, a custom launcher, saved grid state,
  and a pending recovery journal preserved byte for byte.
- Offline execution and self-removal of the installed uninstaller, and its
  refusal to remove a pending recovery journal.
- `--start` propagation through the existing local installation logic using
  a simulated supervisor, without contacting the live graphical session.
- HTML/error bodies, truncated gzip data or footer, a corrupt checksum,
  unsafe paths, links, duplicate paths, mixed roots, missing required files,
  and invalid shell/Python syntax rejected before executing archive code.
- HTTP failures with both downloaders, missing downloader/dependency errors,
  invalid arguments, recursion prevention, and SIGTERM cleanup during a
  pending download. Disposable temporary directories were empty after checks.

The suite uses a local HTTP fixture, not a live GitHub repository archive.
HTTPS/TLS negotiation, GitHub availability, API limits, and a populated
public `main` branch were not tested by this fixture.

## Linux and graphical lifecycle checks

- The existing 11-test runtime unit suite passed unchanged.
- Shell syntax checks passed for the modified installer and uninstaller.
- The real separate PAM/logind X11 harness passed repeat installation,
  supervised XDG startup and fresh initialization, logout while preserving
  the shared user manager, upgrade with Nemo settings retained, and repeated
  removal. Its first removal invoked the installed offline uninstaller.
  The optional prior-build fixture was absent, so the upgrade used the
  documented version-marked copy of the current executable.
- The normal desktop's watcher PID, active state, zero restart count,
  Cinnamon/Nemo D-Bus owners, and absence of a pending journal were unchanged.
  Live desktop metadata was byte-identical before and after this harness.

The compensator executable and supported startup files were unchanged.
The full runtime Xvfb fault suite and optional idle benchmark were not rerun
for this installer-only change; see the earlier
[publication checks](publication-checks.md#linux-follow-up-validation) for
their most recent coverage. Live VMware resize, physical drag across resize,
and real volume timing acceptance scenarios remain outstanding.
