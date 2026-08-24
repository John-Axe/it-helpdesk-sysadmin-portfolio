# TICKET-004 — systemd service crash-looping after deploy

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `web02` in a
> small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P1 — Critical (service down) |
| Category | systemd / Application |
| Reported by | Monitoring alert (service down) |
| Affected system | `web02`, `myapp.service` |

## Symptom

After a routine application deploy, monitoring alerted that `myapp.service`
was down. The site returned `502 Bad Gateway` from the front-end reverse
proxy.

## Triage steps

1. Checked service status:

   ```
   systemctl status myapp.service
   ```

   Output showed `Active: activating (auto-restart) (Result: exit-code)` and
   a restart counter climbing — confirmed a crash loop, not a clean stop.
2. Pulled recent logs:

   ```
   journalctl -u myapp.service -n 100 --no-pager
   ```

   Repeated stack trace ending in:
   `ModuleNotFoundError: No module named 'requests'`.
3. Checked the deploy process — the app runs inside a Python virtual
   environment (`/opt/myapp/venv`) activated by the systemd unit's
   `ExecStart` line. The deploy script had a step to
   `pip install -r requirements.txt`, but it ran that step *outside* the
   venv (a missing `source venv/bin/activate` in the deploy script after a
   recent refactor of that script), so dependencies were installed to the
   system Python instead of the app's venv.
4. Confirmed the theory:

   ```
   /opt/myapp/venv/bin/python -c "import requests"
   ```

   Failed with the same `ModuleNotFoundError`, confirming the venv was
   missing the dependency while the system Python had it.
5. Checked the systemd unit's restart policy to understand the blast
   radius while diagnosing:

   ```
   systemctl cat myapp.service
   ```

   ```
   [Service]
   Restart=always
   RestartSec=2
   ```

   `RestartSec=2` meant it was retrying every 2 seconds, generating a high
   volume of log noise and needless load — worth revisiting once the
   immediate fire was out.

## Root cause

A refactor of the deploy script dropped the `source venv/bin/activate`
line before the `pip install` step, so the latest dependency
(`requests`, newly added in this release) was installed into the system
Python environment instead of the application's virtual environment that
the systemd service actually uses.

## Resolution

1. Manually installed the missing dependency into the correct venv to
   restore service immediately:

   ```
   /opt/myapp/venv/bin/pip install -r /opt/myapp/requirements.txt
   systemctl restart myapp.service
   systemctl status myapp.service
   ```

   Confirmed `Active: active (running)` and the restart counter stopped
   climbing.
2. Fixed the deploy script to re-add the venv activation step, and added a
   post-install verification step (`venv/bin/pip check` plus an import
   smoke test) so a similar gap fails the deploy loudly instead of
   deploying broken code silently.

## Follow-up / prevention

- Adjusted `RestartSec` from `2` to `10` with a `StartLimitBurst=5` /
  `StartLimitIntervalSec=300` guard, so a genuinely broken deploy fails out
  of the restart loop and reports `failed` after a handful of attempts
  instead of hammering the box indefinitely — makes both monitoring and
  `journalctl` output much easier to read during an incident.
- Documented the recovery steps generically in
  `runbooks/linux/systemd-service-recovery-procedure.md` so any
  crash-looping service can be triaged with the same `systemctl status` →
  `journalctl -u` → identify exit reason → fix → restart flow.
- Added a smoke test to the deploy pipeline (curl the app's `/healthz`
  endpoint and check for HTTP 200 within 30 seconds of restart) so this
  class of failure is caught by the deploy pipeline itself, before
  monitoring has to page anyone.
