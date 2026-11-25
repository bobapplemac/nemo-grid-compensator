# Startup and transaction architecture

Cinnamon starts the XDG entry. The launcher contacts the systemd user manager
on its standard bus and passes the graphical session bus, X display, auth
location and XDG directories only to the transient unit. The watcher
validates the Cinnamon session manager's logind session against the launch
session and X display. It exits on session logout or loss of the session
manager, even with another login keeping the user manager alive. There is
no change to Nemo's native autostart condition or global session settings.

Systemd provides journald logging and restarts failures after five seconds,
with three starts per 60 seconds. An ambiguous recovery exits with status
78 and systemd does not retry. The direct XDG example uses `--watch` with no
supervisor and requires explicit initialization.

## Event handling

GDK monitor changes and an event-only X11 root-property subscription feed
debounced layout checks. GSettings, GIO file monitors, volume inventory and
D-Bus name ownership trigger updates. GVfs position events normally update
only the checkpoint. A five-second fallback is limited to desktop
position checkpoints on GVfs versions without the signal. Short waits
during startup and transactions are bounded.

Cinnamon compositor ownership is monitored separately. Compensation waits
for a stable owner, settled work area and a mapped Nemo Desktop when icons
are enabled. Three compositor losses in a minute pause compensation for
90 seconds. The cooldown survives watcher restarts within that boot.

## Transaction and recovery

The per-user lock prevents concurrent writers. A prepared journal records
old and new cells and the specific GIO attributes that may change. Before
taking down Nemo, the watcher marks that it owns the temporary visibility
change. It takes a second snapshot with Nemo stopped. It verifies file and
mount inventories, compositor ownership and work-area state before the
atomic metadata commit. Only the named metadata keys and GIO icon-position
attributes are changed. A primary-button press defers starting a transaction.

The grid adjustments identify the committed side. A position-only repair
has an explicit commit marker. Recovery rechecks current data and rewrites
only positions that still match the recorded old or new value. It avoids
stopping Nemo when no on-disk repair is needed. A released journal does not
authorize restoring visibility. During a shutdown the journal remains if
verification could not finish. Ambiguous journals are retained, with the
reason in the log.

State lives under `$XDG_STATE_HOME/nemo-grid-compensator` or
`~/.local/state/nemo-grid-compensator`. Nemo's own user metadata and GVfs
retain the final layout.

### Recovery verification

Before a recovered layout is written to the checkpoint, recovery checks
the committed spacing and each surviving icon's logical cell using the
same verifier as a normal adjustment. Disappeared files and mounts and
replacements with a different identity are omitted. If a surviving icon
is in an unexpected cell, recovery stops and retains the journal for
review. The utility does not silently accept a moved icon as part of the
recovered checkpoint.

Validation and reconciliation run inside the visibility restoration
boundary. If the operation cannot be completed, an owned visibility
change is released and the journal stays on disk. A prepared or released
record does not authorize enabling icons. The same rule applies to an
interrupted initialization.
