# SOP — systemd service recovery procedure

> Lab/practice SOP for Ubuntu 22.04 LTS. Not a real employer's procedure.
> Generalized from `tickets/linux/TICKET-004-systemd-service-crash-looping.md`.

## Scope

A repeatable triage flow for any systemd-managed service that's down,
crash-looping, or reported as unhealthy by monitoring — from first
response through root cause and a documented fix.

## Steps

### 1. Get current status

```bash
systemctl status <service>.service
```

Read the `Active:` line carefully — it tells you which of several distinct
states you're actually in:

- `active (running)` — service is up; if monitoring still says it's down,
  the problem may be at a different layer (health-check endpoint, reverse
  proxy, firewall) not the service itself
- `activating (auto-restart)` — crash loop in progress
- `failed` — stopped trying (either `Restart=no`, or it hit a
  `StartLimitBurst` ceiling)
- `inactive (dead)` — cleanly stopped, not crashing — check who/what
  stopped it (`journalctl` around the stop time, or a deploy script that
  intentionally stopped it and never restarted it)

### 2. Pull recent logs

```bash
journalctl -u <service>.service -n 100 --no-pager
```

For a longer window or to catch the very first failure after a deploy:

```bash
journalctl -u <service>.service --since "1 hour ago" --no-pager
```

Look for the **first** error in a crash sequence, not just the last one —
a service can throw several downstream errors that are symptoms of one
root problem earlier in the log.

### 3. Check the unit's restart policy to understand behavior so far

```bash
systemctl cat <service>.service
```

Note `Restart=`, `RestartSec=`, and any `StartLimitIntervalSec=`/
`StartLimitBurst=` — these determine whether systemd will keep retrying
indefinitely (risk: hammering a dependency, generating huge log volume) or
give up after N attempts and report `failed` (easier to notice, but stops
retrying on its own even if the underlying issue is transient).

### 4. Reproduce manually if the log isn't conclusive

Run the service's actual start command directly (not via systemd) to see
full, unfiltered output and interact with it directly:

```bash
sudo -u <service-user> /path/to/actual/start/command
```

Check the unit file's `ExecStart=` line via `systemctl cat` to get the
exact command and working directory systemd uses, and replicate it
exactly (including environment variables set via `Environment=` or
`EnvironmentFile=` in the unit).

### 5. Common root causes to check, roughly in order of frequency

1. **Dependency/environment mismatch** — e.g. Python venv missing a
   package after a deploy (see TICKET-004), a config file referencing a
   path that changed, an expected environment variable unset.
2. **Port already in use** — another process (often a previous instance
   that didn't fully die) is holding the port:
   ```bash
   sudo ss -ltnp | grep <port>
   ```
3. **Permission issue** — service user can't read a config file or write
   to a data/log directory after a permissions change elsewhere on the
   system.
4. **Resource exhaustion** — check `dmesg | grep -i "out of memory"` for an
   OOM-killer event, or `df -h` for a full disk blocking writes.
5. **Upstream dependency down** — database, cache, or API the service
   depends on is unreachable; check connectivity from the service's
   context (`sudo -u <service-user> curl ...` or similar) before assuming
   the service itself is broken.

### 6. Apply the fix, then restart cleanly

```bash
sudo systemctl restart <service>.service
sudo systemctl status <service>.service
```

Confirm `Active: active (running)` and that the restart counter (visible
via `systemctl status`, "Main PID" and process age) is stable — i.e. it
hasn't restarted again within the next minute or two of watching.

### 7. Watch logs live for a few minutes post-fix

```bash
journalctl -u <service>.service -f
```

Don't close the ticket immediately after the first clean start — a fix
that resolves the crash but doesn't address a slower-building version of
the same problem (e.g. a memory leak) can look fine for a few minutes and
then recur.

## Follow-up hardening (apply after the fire is out)

- If `RestartSec` is very low (1-2s) and the service was crash-looping
  hard, consider raising it and adding `StartLimitBurst`/
  `StartLimitIntervalSec` so a genuinely broken deploy fails out to
  `failed` state after a handful of attempts instead of looping
  indefinitely — much easier to alert on and much less log noise during
  an incident.
- Add a deploy-pipeline smoke test (hit a health endpoint, check exit
  code) so this class of failure is caught before it reaches production
  monitoring.
- If root cause was a missing dependency or config drift, check whether
  config management (Ansible/Puppet/etc.) should own that file/state
  going forward instead of a manual deploy step.

## Quick reference

| Command | Purpose |
|---|---|
| `systemctl status <svc>` | Current state, recent log tail, restart count |
| `journalctl -u <svc> -n 100` | Recent logs |
| `journalctl -u <svc> --since "1 hour ago"` | Logs from a specific window |
| `systemctl cat <svc>` | Full unit file as systemd sees it (including drop-ins) |
| `systemctl show <svc> -p Restart -p RestartSec -p StartLimitBurst` | Restart policy specifics |
| `systemctl daemon-reload` | Required after editing a unit file directly |
