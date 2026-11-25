# Installation methods

Run installation and removal as the desktop user, never with `sudo`. The
installer writes only user-owned application, startup, and configuration
files. It retains the existing dependency checks and does not install system
packages automatically. Use your distribution's package manager, with `sudo`
only when required for missing system packages. The [README](../README.md#install-and-initialize)
lists the Debian runtime dependencies.

Remote installation additionally requires `bash`, `/usr/bin/python3`, trusted
HTTPS certificates (Debian's `ca-certificates`), and either `curl` or `wget`.
Python's standard library handles archive validation and extraction; Git,
release assets, and additional Python packages are not needed.

## Install directly from GitHub

Choose one:

```bash
curl -fsSL https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash
```

```bash
wget -qO- https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash
```

These commands execute code retrieved from the project's `main` branch.
They install for the next graphical login. A successful installation ends
by printing the installed version. A failed initial download can leave Bash
with empty input, so a pipeline's exit status alone is not proof of success.
The inspect-first method below makes the download and execution separate.

The archive downloader prefers curl when available, otherwise wget. An HTTP
or transport failure aborts installation; it does not install a partial
download. GitHub's unauthenticated API limits can also cause a download to fail.

### Selecting a revision and starting immediately

The remote default is `main`. Use `--ref` for an existing branch, tag, or
commit, and `--start` to install/upgrade and start in the current X11 Cinnamon
login:

```bash
curl -fsSL https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash -s -- --ref main --start
```

```bash
wget -qO- https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh | bash -s -- --ref main --start
```

Replace the argument after `--ref` to select a different revision. Branch names
containing `/` are supported. Tags must exist in GitHub, but need not have an
associated GitHub release. A full commit ID pins the application inputs;
`main` and other branches can advance between installations. The bootstrap
script still comes from the URL shown, while all installed application and
startup files come from the single archive for the selected ref. The selected
revision's installer controls its installation behavior.

## Inspect before executing

Download the bootstrap to a private temporary directory, inspect it, and
then run it. Interrupt before execution if you do not want to proceed:

```bash
(
    set -eu
    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 1' HUP INT TERM
    curl -fsSL https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh -o "$work/install.sh"
    less "$work/install.sh"
    bash "$work/install.sh"
)
```

For wget, replace the curl line with:

```bash
wget -qO "$work/install.sh" https://raw.githubusercontent.com/bobapplemac/nemo-grid-compensator/main/install.sh
```

You can pass `--ref` and `--start` to `bash "$work/install.sh"` as above.
Inspecting the bootstrap does not review the application or the installer
inside a subsequently downloaded archive. For a complete source review,
download GitHub's source archive for a chosen revision, inspect its contents,
and use the local installation method below.

## Local checkout or extracted archive

From a complete repository checkout or extracted GitHub source archive:

```sh
./install.sh
# Or start immediately in the current graphical login:
./install.sh --start
```

Local installation uses the adjacent application, startup files, and
uninstaller without downloading anything. A standalone copy of `install.sh`
with those files missing automatically uses remote mode. Supplying `--ref`
also requests remote mode, even from a complete checkout.

## Archive handling

The bootstrap requests GitHub's repository tar archive over HTTPS and follows
the archive redirect. It downloads into a directory created by `mktemp -d`.
Before executing the downloaded installer, it checks the gzip stream including
its checksum/footer, the tar inventory, one repository root, and the required
installation inputs. Absolute or parent-traversing paths, duplicate members,
links, special files, missing inputs, invalid Python or shell syntax, and
oversized archives are rejected. Limits are 16 MiB compressed, 64 MiB expanded,
10,000 members, and 4 MiB per required input.

Only the required regular files are copied to fixed paths in that private
directory. The bootstrap invokes the extracted local installer once with a
recursion guard. Temporary downloads, extracted inputs, and unfinished atomic
installation files are removed on success, errors, or handled HUP/INT/TERM
signals. As with other shell traps, cleanup cannot run after SIGKILL or power
loss.

These checks validate archive structure and syntax, not authorship or behavior.
HTTPS and trust in the chosen GitHub repository/revision remain necessary;
there is no separate signature or release-checksum verification.
See the [installer validation report](installer-validation.md) for exercised
failure cases and the controlled test environment.

## Reinstallation, upgrades, and offline removal

Rerunning the same installation command refreshes managed files atomically
per file. It preserves Nemo configuration, icon positions, saved utility
state, and pending recovery journals. As before, managed autostart and
launcher files are refreshed; see [custom launcher configuration](cli.md#persisting-custom-geometry)
for upgrade considerations. `--start` restarts an active service when the
application or supported launcher changes, retaining the existing recovery
and session-supervision path. Without `--start`, the running watcher is left
to the existing session lifecycle.

Every installation of this installer also saves an executable uninstaller:

```sh
~/.local/libexec/nemo-grid-compensator-uninstall
# Also remove utility state, after any pending transaction is resolved:
~/.local/libexec/nemo-grid-compensator-uninstall --purge-state
```

This requires no network or source checkout. The original `./uninstall.sh`
works too. Removal retains the last Nemo settings and icon arrangement,
refuses pending transaction journals, and removes the installed uninstaller
itself. For externally supervised or foreground use, stop the watcher first
and pass `--files-only`.
