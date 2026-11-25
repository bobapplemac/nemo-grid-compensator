# Changelog

## v0.1.0rc2 — current release candidate

Feature-complete for the planned v0.1.0 release; daily-use acceptance testing
is still in progress. This is not the stable v0.1.0 release.

### Functionality carried forward from rc1

- Event-driven desktop icon-grid compensation for single-monitor, scale-1
  Cinnamon X11.
- Automatic initialization of supported fresh profiles and repeatable
  installation, upgrades and removal.
- XDG autostart with a supervised systemd user service, journald logs and
  session-scoped shutdown.
- Recovery across compositor replacement and interrupted transactions.
  Repeated compositor loss pauses compensation.
- Validated baseline is Debian 13, Cinnamon 6.4.10, Nemo 6.4.5. VMware
  rendering faults are outside the utility's remit. See the [validation history](docs/test-results.md)
  for isolated, injected and outstanding tests.

### RC2 review changes

- Restore visibility owned by an interrupted transaction even when grid
  recovery is ambiguous. Preserve the journal and stop supervision retries.
- Verify recovered checkpoints against surviving icon identities and cells.
- Diagnose partially initialized profiles and require explicit initialization
  on an established profile.
- Document persistent custom launcher settings and upgrade behavior.

### Installer updates after the RC2 bundle

- Support stdin and standalone-script installation from one GitHub repository
  archive, defaulting to `main`, with optional branch/tag/commit selection via
  `--ref`. No Git installation or GitHub release is needed.
- Validate archive structure and required source syntax before invoking the
  extracted local installer; clean up temporary inputs and prevent recursion.
- Retain local offline installation, existing runtime dependency checks,
  startup supervision, and saved layout/recovery state. Install an offline
  uninstaller under `~/.local/libexec/`.
- Document curl, wget, and inspect-first installation. These changes do not
  alter the compensator runtime, optimizer, defaults, or rc2 version.
- Installations now initialize supported profiles without saved checkpoints
  or pending journals and start immediately in the current X11 session by
  default. `--no-start` opts out; non-graphical installs defer startup.
  Future-login startup remains configured through the existing XDG launcher.

### Remaining limitations and acceptance work

The validated baseline uses X11, one monitor, and 100% display scaling.
Multi-monitor, HiDPI, and Wayland are outside the supported scope.
Rapid live VMware resize bursts on this candidate, a physical drag crossing
a resize, and real removable/SMB volume changes during commit remain
acceptance scenarios. The VMware Mesa/LLVMpipe graphics fault remains
unresolved. Controlled work-area, input, mount, and logout injections do not
establish equivalent live coverage. See the validation history linked above
for the rc1 and rc2 results and their limits.
