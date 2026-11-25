# Nemo Grid Compensator

Consistent icon spacing and balanced margins for Cinnamon's Nemo desktop,
while preserving your manually arranged icon rows and columns as the display
resolution changes.

**Current version: v0.1.0rc2.** This release candidate is undergoing daily-use
acceptance testing. See the [changelog](CHANGELOG.md) and
[validation history](docs/test-results.md) for completed and outstanding work.

## Why use it?

Nemo centers its desktop grid within the available work area. The unused
space around the grid changes with resolution, and horizontal and vertical
cell sizes differ. The result can be uneven margins or spacing that looks
comfortable at one resolution and awkward at another.

Nemo Grid Compensator selects spacing using the current work area, icon and
label bounds, and your existing logical grid cells. It aims for consistent
margins and pitch (the distance between cells), keeping icons in their chosen
rows and columns rather than sorting or packing them. Pixel coordinates change
as the grid changes; layouts that cannot fit safely are skipped.

- Handles ordinary desktop files, directories, launchers, symlinks, built-in
  icons, and mounted volumes through Nemo metadata and GVfs.
- Requires no modifications to Nemo or Cinnamon packages. Cinnamon remains
  responsible for starting and stopping Nemo Desktop; adjustments can briefly
  hide and restart the desktop icons.
- Uses native display, file, settings, and session events with debouncing for
  low idle activity. A five-second position-checkpoint fallback is used when
  GVfs lacks metadata signals. See the [historical idle benchmark](docs/test-results.md#idle-benchmark).
- Runs under a systemd user service, with journald logs, session-scoped shutdown,
  a single-writer lock, and recovery journals for interrupted adjustments.
  Ambiguous recovery retains the journal and stops automatic retries.

## Compatibility and limits

The validated baseline is **Debian 13 Trixie, Cinnamon 6.4.10, Nemo 6.4.5,
X11, one monitor, and 100% display scaling**. Other Cinnamon distributions
and versions may work, but have not been validated.

The supported layout uses Nemo's modern desktop grid, Normal icon size,
Auto-arrange off, and Align to grid on. The work area must start at the
top-left of the display. Multi-monitor and cloned outputs, HiDPI/fractional
scaling, and Wayland are outside the supported scope. Saved metadata from
additional monitors can also prevent operation.

Manual arrangement preservation depends on usable saved positions and a grid
large enough to hold the chosen cells. A physical drag overlapping a resize
remains an acceptance-testing gap. An unresolved VMware Mesa/LLVMpipe graphics
fault is separate from transaction recovery; the utility cannot prevent or
repair graphics-driver faults. See [troubleshooting and limitations](docs/troubleshooting.md)
and the [validation history](docs/test-results.md) for details.

## Before and after

Screenshots will be added after capture on the validated desktop. The planned
comparison will show the same icon arrangement and display resolutions with
Nemo's native spacing and with compensation enabled. No example images are
included yet.

## Install and initialize

Run either command as your Cinnamon desktop user, without `sudo`. No local
Git installation or published GitHub release is required:

```bash
curl -fsSL https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash
```

```bash
wget -qO- https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash
```

These install from `main` for the next graphical login. Rerun the same command
to reinstall or upgrade. The installer downloads one repository archive and
uses that revision's local installation logic. To select a branch, tag, or
commit, or to start in the current X11 Cinnamon login, pass arguments to Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash -s -- --ref main --start
```

Replace `main` after `--ref` with the desired existing ref. For a
[download-inspect-execute method](docs/installation.md#inspect-before-executing),
archive validation details, and dependency guidance, see the
[installation guide](docs/installation.md). A complete local checkout or
extracted source archive also supports `./install.sh` and `./install.sh --start`
without network access; adding `--ref` explicitly requests a GitHub download.

The installer checks dependencies; it does not install distribution packages.
Debian runtime packages are `cinnamon`, `nemo`, `python3`, `python3-gi`,
`gir1.2-gtk-3.0`, `gvfs`, `dbus-user-session`, `systemd`, `x11-utils`,
`x11-xserver-utils`, `coreutils`, and `util-linux`.

Files are installed under `~/.local/bin/`, `~/.local/libexec/`, and the XDG
configuration directory's `autostart/` (normally `~/.config/autostart/`). The
launcher creates a transient systemd user unit at each graphical login; no
`systemctl enable` step or lingering is needed. Re-running the installer
upgrades the managed files.

Startup initializes supported fresh profiles automatically. An established
or partially configured profile may require explicit initialization. With
the watcher stopped, preview and then apply from the owning Cinnamon session:

```sh
systemctl --user stop nemo-grid-compensator.service
~/.local/bin/nemo-grid-compensator --init --dry-run
~/.local/bin/nemo-grid-compensator --init
~/.local/libexec/nemo-grid-compensator-session
```

Initialization sets the supported grid mode, alignment, and icon size while
preserving the desktop visibility preference. It refuses a populated legacy
grid or an existing non-Normal icon size. Review the preview before applying.

## Usage and configuration

```sh
systemctl --user status nemo-grid-compensator.service
journalctl --user -u nemo-grid-compensator.service -b
systemctl --user stop nemo-grid-compensator.service
# Start again in the current Cinnamon session:
~/.local/libexec/nemo-grid-compensator-session
```

For a one-shot preview with the watcher stopped:

```sh
~/.local/bin/nemo-grid-compensator --once --dry-run --verbose
```

Defaults target 25 px left/top image margins and 80 × 85 px cell pitch,
subject to fit and label-clearance constraints. Geometry is configured with
command-line arguments; there is no configuration file. See the
[command-line reference](docs/cli.md) for all defaults and how to persist
custom launcher arguments across upgrades. Use only one startup entry per user.

## Remove

Run as the desktop user:

```sh
~/.local/libexec/nemo-grid-compensator-uninstall
~/.local/libexec/nemo-grid-compensator-uninstall --purge-state
```

The installed uninstaller works offline without the original repository.
`./uninstall.sh` remains available in a local checkout. `--purge-state` also
removes the utility's saved state and logs.

Removal stops the managed service and refuses to remove a pending transaction
journal. It preserves Nemo's last applied spacing, alignment, icon size,
visibility, and icon positions; it does not restore earlier desktop settings.
For a foreground or externally supervised installation, stop its watcher
first and use `--files-only`. The uninstaller can be rerun.

## Documentation and tests

- [Command-line reference and configuration](docs/cli.md)
- [Installation methods and archive validation](docs/installation.md)
- [Startup, events, transactions, and recovery](docs/architecture.md)
- [Troubleshooting and limitations](docs/troubleshooting.md)
- [Validation history and remaining acceptance scenarios](docs/test-results.md)
- [Running the tests](tests/README.md)

The application remains a single Python executable. `startup/` contains the
supported supervised launcher, `examples/` the optional unsupervised desktop
entry, and `tests/` the regression and integration harnesses.

Licensed under the [MIT License](LICENSE).
Copyright (c) 2026 Andrew J. Moore.
