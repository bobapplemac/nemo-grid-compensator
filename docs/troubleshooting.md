# Troubleshooting and limits

Use `journalctl --user -u nemo-grid-compensator.service -b` first. The
watcher should log when it pauses for a resize, unstable compositor or
unsupported layout. An icon drag whose saved coordinates land after a
resize can race Nemo's native realignment. The watcher defers while the
primary button is down and uses the last available logical checkpoint.

For a pending journal, stop the service and run `--recover` from the owning
Cinnamon session. If the journal or metadata changed independently, inspect
it before editing or removing anything. A journal whose visibility is
marked held indicates the utility was authorized to turn icons back on.
A crash between changing the boolean and releasing the journal cannot
disambiguate a later external choice to turn icons off. A released record
does not re-enable icons. Keep the journal to investigate unexpected cases.

The utility cannot repair Mesa or prevent graphics-driver faults. It
responds to compositor loss and backs off on repeated crashes. See the
[validation report](test-results.md) for VMware resize and drag coverage.

The optional direct XDG example is for manual or unsupervised use. Use one
startup entry per user. Stop the supervisor before using mutable one-shot
commands. Install or initialize in the supported graphical session.

## Partially initialized profiles

When the watcher finds saved spacing or other evidence of a configured
profile but required grid keys are missing, startup logs the missing keys
and leaves the profile alone. Stop the service in the owning Cinnamon
session and preview with
`~/.local/bin/nemo-grid-compensator --init --dry-run`. If the proposed
settings are suitable, run `--init` and launch the service again. When
icons are disabled, explicit initialization fills the keys without enabling
the icons. Existing spacing is preserved as the optimizer's starting point.
