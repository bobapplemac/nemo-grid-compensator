# Repository preparation checks

Repository preparation on November 25, 2026 began on a Windows host with
Python 3.13 and Git for Windows' shell. No Cinnamon desktop or installed WSL
was available locally. Follow-up validation used SSH to the Debian development
VM. The [release validation history](test-results.md) remains separate from
these checkout checks and the repeat validation below.

## Changes and preservation

- Kept the application, installer, uninstaller, supported startup files,
  optional desktop entry, and executable test fixtures unchanged.
- Moved the original test report to `docs/test-results.md`, adding only a
  provenance introduction and heading. Consolidated release notes into the
  root `CHANGELOG.md` with rc2 retained as the current release candidate.
- Reworked the README for installation, initialization, operation,
  configuration, removal, compatibility, and planned screenshots.
- Updated MIT attribution to Andrew J. Moore without changing license terms.
- Replaced the test documentation's development username and absolute source
  path example with the invoking user and checkout directory.
- Added ignore rules for generated profiles, downloaded test tools, Python
  caches, environments, logs, temporary files, and editor/build output; added
  LF checkout rules and recorded executable modes in Git.
- Retained `tests/baseline` because the optional benchmark uses it. No caches,
  credentials, private network addresses, personal desktop metadata, or
  unrelated temporary artifacts were found in the supplied project files.
  No third-party notices were removed.

## Checkout validation

- Python syntax compiled without imports or cache generation for the
  application, archived benchmark, and four Python test helpers (six files).
- `bash -n` checked all 16 shell entry points. `sh -n` also checked the
  installer, uninstaller, and supported session launcher.
- Relative Markdown links and heading fragments were checked against files.
  Installer source paths and test-harness file references were checked.
- The initial unit-suite attempt could not run on Windows: importing the
  application requires `fcntl`, followed by the real PyGObject/GTK stack.
  No mock runtime was substituted; Linux follow-up results are recorded below.
- Reviewed the initial staged tree, whitespace, LF line endings, executable
  modes, and ignore rules. The repository had no prior commit, so the initial
  staged diff represents the entire project rather than a change-only diff.

These syntax and repository checks do not establish runtime compatibility or
replace the Debian/Cinnamon validation.

## Linux follow-up validation

The staged Git contents were transferred to a private directory with their
recorded executable modes and LF line endings. The VM runs Debian 13 Trixie,
Cinnamon 6.4.10, and Nemo 6.4.5. Existing extracted Xvfb tools were reused;
no distribution packages or application changes were needed.

- All 11 unit tests passed using the real Linux/PyGObject runtime.
- Python syntax passed for all six Python files; Linux shell syntax and
  executable checks passed for all 16 shell scripts. The executable reported
  `nemo-grid-compensator 0.1.0rc2`.
- The separate PAM/logind harness passed supervised XDG startup and fresh
  initialization, logout while preserving the shared user manager, upgrade,
  and repeated removal with native settings preserved. Its optional older
  build fixture was absent, so upgrade used the documented version-marked copy.
- The first isolated-suite attempt correctly refused the SSH environment
  without `XDG_SESSION_TYPE=x11`. The rerun explicitly supplies it; the test
  instructions now document this prerequisite.
- `XDG_SESSION_TYPE=x11 bash tests/run.sh` completed with exit status 0:
  all 11 unit tests, 18 isolated profiles covering initialization,
  interrupted transactions, event/checkpoint behavior, compositor loss and
  replacement/cooldown, Nemo restart, input deferral, RC2 ambiguous recovery
  and partial-profile handling, and all 13 injected transaction cases passed.
- The installed watcher kept its PID, zero restart count, and active status;
  the live Cinnamon and Nemo D-Bus owners were unchanged and no pending
  journal appeared. During the successful run, the live metadata differed in
  one `nemo-icon-position-timestamp` entry only; saved positions and grid
  settings were unchanged. The initial failed attempt also coincided with a
  metadata hash change, but only the hash was captured at that earlier
  boundary, so its exact difference cannot be established retrospectively.

Detailed logs and private profiles were retained in the VM's separate
validation directory, outside the publication tree. Credentials and private
connection details were not added to the repository. The optional idle
benchmark and live VMware resize/drag/real-volume acceptance scenarios were
not rerun. Isolated Xvfb sessions and injected events remain distinct from
those live scenarios.

## Publication follow-up

1. Supply before-and-after screenshots with resolution and environment
   captions; retain the same icon arrangement for a fair comparison.
2. The staged-content Linux regression and PAM/logind checks passed. After
   publication, a fresh Git clone is still useful to confirm distribution
   and rendered documentation; rerun the documented checks when candidate
   contents or the target environment change.
3. Continue rc2 daily-use acceptance for live resize bursts, physical drag
   during resize, and real volume changes during commit. Keep the unresolved
   VMware graphics issue documented; simulated coverage is not live coverage.
4. Review the staged initial tree with `git diff --cached --stat` and
   `git diff --cached`, then create the initial commit, for example
   `git commit -m "Import v0.1.0rc2 and prepare public repository"`.
5. When approved, push `main` to the existing `origin` remote:
   `git push -u origin main`. Confirm the rendered README and documentation
   on [GitHub](https://github.com/bobapplemac/nemo-grid-compensator).

No commit, tag, release, or push was created during this preparation. RC2
remains the publication baseline; stable v0.1.0 requires the acceptance
decision. A legacy runtime diagnostic still calls the utility a prototype
when grid spacing is missing; it was left unchanged to preserve the candidate.
