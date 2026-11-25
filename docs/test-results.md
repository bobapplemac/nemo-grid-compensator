# RC1 and RC2 validation history

This report preserves validation recorded with the release candidate bundle
on the Debian development VM. It is historical evidence, not a claim that
every recorded scenario was rerun during repository preparation. RC2 remains
in daily-use acceptance testing. See [repository preparation checks](publication-checks.md)
for the later checkout checks and repeat Linux validation.

## v0.1.0rc1 validation

Validated on the Debian 13 development VM with Cinnamon 6.4.10, Nemo 6.4.5,
GVfs 1.57.2, systemd 257, and unmodified Debian packages. The visual optimizer
matched the hardened baseline byte for byte.

## Passed in an isolated Cinnamon session

- Fresh profile without Nemo metadata, automatic initialization, explicit
  initialization dry run, repeated initialization, and a fresh profile with
  icons intentionally disabled. No Customize dialog was used.
- XDG login launched the supervised process in a separate PAM/logind X11
  session while the normal login remained active. The service initialized the
  profile on first login. Actual Cinnamon logout stopped only the isolated
  watcher while the same systemd user manager remained available.
- Repeat installation, upgrade from the previous hardened executable, repeat
  removal including purged utility state, and preservation of Nemo keys.
- Unexpected process exit after Nemo stopped, after the first GVfs write, and
  after atomic desktop-metadata commit. Recovery restored visibility and
  reconciled the journal. Duplicate writers were rejected.
- Cinnamon was killed once and subsequently replaced twice. Compensation
  stayed paused during owner loss, resumed after recovery without restarting
  Nemo, and entered the cooldown after repeated losses. The watcher exited
  after Cinnamon logout. A unit test verified cooldown durability and expiry.
- Nemo Desktop was killed separately. Cinnamon restarted it and the watcher
  reevaluated the layout. A clean watcher stop reaped its X11 helper.
- The watcher checkpointed a GVfs position change without optimization,
  coalesced rapid X11 work-area property changes, and reevaluated on rename.

## Passed with injected conditions

Real private-session Nemo/GVfs state was used around the injected conditions.
These are controlled regression tests rather than live VMware scenarios.

- Session-ending flag set at journal preparation, after Nemo stopped, after a
  GVfs write, after atomic commit, and during remap. In every case visibility
  was restored when the utility owned it, and incomplete work was discarded
  or remained recoverable.
- Real files were created, renamed, or removed after a GVfs write. The native
  grid stayed unchanged and recovery preserved the newer file inventory.
- Injected mount and unmount inventory changes aborted stale plans. Injected
  D-Bus no-reply, GIO busy, and filesystem EAGAIN left no unresolved journal.
- XTest held the primary button on the Xvfb display. A planned adjustment
  deferred without taking down Nemo. This did not exercise a physical drag
  whose final saved position overlaps a VMware resize.
- Malformed and out-of-scope recovery data, no-follow file checks, a procfs
  exit race, transient error classification, and visibility ownership have
  automated unit coverage.

## Idle benchmark

Sampled for 20 seconds with 80 ordinary desktop icons. CPU is runtime as a
percentage of one core. Scheduling events from procfs are a wakeup proxy.
These figures are for the main watcher process.

| Watcher | CPU | Scheduling events/s | RSS |
| --- | ---: | ---: | ---: |
| Original polling prototype | 1.18% | 90.8 | 56.3 MiB |
| v0.1.0rc1 | 0.00% observed | 0 observed | 57.5 MiB |

## Live VM acceptance deployment

- Ran the release installer and enabled the preferred XDG launcher. Exactly
  one compensator is active. Desktop metadata remained byte-identical, the
  five icons and SMB volume were present, and the Cinnamon and Nemo owners
  did not change. The deployment required neither a logout nor a reboot.
- An isolated, supervised dry-run of the release executable restarted once
  after SIGKILL. A different isolated-state supervisor retained an ambiguous
  journal, exited with status 78, and recorded zero restarts.
- The previous hardened build handled real VM resizes and recovered from a
  logged compositor fault on the development desktop. The interaction
  between that fault and the overlapping desktop operations remains unknown.

## Outstanding manual coverage

Rapid VMware resize bursts on this exact candidate, a physical drag crossing
a resize, and a real removable or SMB volume changing during commit remain
daily-use acceptance scenarios. Equivalent work-area, input and inventory
conditions were tested in isolation or injected as noted above. The Mesa
LLVMpipe fault was neither fixed nor deliberately reproduced on the live
session. Exact logout timing at production write boundaries is represented
by the injected tests. The real shared-manager logout was at a settled
desktop.

## v0.1.0rc2 review validation

- Confirmed rc1's visibility restoration ran after several fallible recovery
  checks. In rc2, recovery releases owned visibility even if those checks
  cannot resolve the journal. The journal stays on disk with the updated
  visibility phase, and exit status 78 prevents automatic retries.
- The real isolated Cinnamon test covered ambiguous layout and initialization
  recovery with held, prepared and released journals. Held restored native
  Nemo Desktop availability. Prepared and released preserved intentional
  disablement. All six retained their journal and returned status 78.
- Focused tests verified that an unexpected surviving cell blocks checkpoint
  acceptance and retains the journal. Removed and replaced files and mounts
  were filtered by identity. A simulated initialization metadata read error
  confirmed that held visibility is released on failure.
- Tested a partial profile with existing spacing and a missing zoom key.
  Automatic startup printed the explicit initialization instructions and
  left the profile unchanged. Preview was read-only. Explicit initialization
  restored the required key and preserved spacing and disabled icons.
- The 11-test unit suite and existing isolated Nemo transaction and fault
  suites passed. The separate PAM/logind login, logout, upgrade and removal
  test also passed on rc2. The rc1 performance and outstanding VMware input
  and real mount timing notes above remain historical context.
- Deployed rc2 on the live VM. Verified one active watcher, byte-identical
  desktop metadata, the same five icon cells including the SMB volume,
  unchanged Nemo and Cinnamon owners, status 78 supervision policy and no
  pending journal. Did not log out or deliberately resize the active desktop.
