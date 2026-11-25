# Command-line reference

| Argument | Behavior |
| --- | --- |
| `--version` | Print the release candidate version |
| `--once` | Apply a single adjustment, the default |
| `--watch` | Watch the graphical session in the foreground |
| `--init` | Initialize Nemo's supported per-monitor grid keys |
| `--recover` | Recover a pending transaction with the watcher stopped |
| `--dry-run` | Preview changes without writing desktop or utility state |
| `--verbose` | Print the logical cell of each icon |
| `--initialize` | First-profile bootstrap used with `--watch` by the launcher |
| `--session-id` | Bind a watcher to a specific logind session |
| `--old-area WIDTHxHEIGHT` | Supply the previous work area for a one-shot adjustment |
| `--margin LEFT,TOP` | Target 25,25 px |
| `--min-margin X,Y` | Minimum nominal image margins, 15,15 px |
| `--min-label-clearance PIXELS` | Minimum estimated clearance, 10 px |
| `--pitch X,Y` | Target pitch, 80,85 px |
| `--min-pitch X,Y` | Minimum pitch, 70,75 px |
| `--preferred-max-pitch X,Y` | Soft ceilings, 100,110 px |
| `--debounce SECONDS` | Debounce, 0.65 s |
| `--hysteresis PIXELS` | Hysteresis, 2 px |

The measured two-line label reserve also bounds vertical pitch. Initialization
leaves desktop visibility as set by the user and refuses an already
populated legacy grid or a previously configured non-Normal icon size.

## Persisting custom geometry

The release launcher passes no geometry arguments and uses the defaults
above. To keep a custom profile, save a copy of the launcher under a
user-managed name, for example
`~/.local/libexec/nemo-grid-compensator-session-custom`. Append the desired
arguments to its final command. For example:

```sh
"$HOME/.local/bin/nemo-grid-compensator" --watch --initialize \
    --session-id "$XDG_SESSION_ID" --margin 25,25 --pitch 82x90
```

Keep the preceding `systemd-run` options and line continuation in the
original launcher. Point the existing
`${XDG_CONFIG_HOME:-$HOME/.config}/autostart/nemo-grid-compensator.desktop`
`Exec` line at the custom launcher:

```ini
Exec=/bin/sh -c "exec ~/.local/libexec/nemo-grid-compensator-session-custom"
```

This uses the same autostart filename and service name, so there is one
watcher. The installer refreshes both the distributed launcher and the
managed autostart entry on every install or upgrade. A separately named
custom launcher survives, but reapply the custom `Exec` line after upgrading.
Keep both steps in your deployment playbook. Restart the transient unit by
stopping it and running the custom launcher in the owning Cinnamon session;
the next graphical login also uses it. A configuration file is deferred.
