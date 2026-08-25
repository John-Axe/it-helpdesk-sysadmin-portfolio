# SOP — Firewall rule change procedure

> Lab/practice SOP for Ubuntu 22.04 LTS hosts using `ufw` and RHEL-family
> hosts using `firewalld` (this fleet runs both, depending on host role —
> steps are given for each where they differ). Not a real employer's
> procedure. Written in response to
> `tickets/linux/TICKET-008-firewalld-blocking-app-port.md`, which traced
> back to exactly the runtime-vs-permanent gap this procedure's
> verification step exists to catch.

## Scope

A safe, auditable process for adding, modifying, or removing a firewall
rule on a Linux host — covering both `ufw` (simpler, used on
general-purpose hosts) and `firewalld` (zone-based, used where more
granular interface/zone separation is needed) — with an explicit
verification step to prevent the runtime/permanent configuration drift
that caused TICKET-008.

## Before making any change

- Confirm the actual requirement: source (which hosts/networks need
  access), destination port(s), protocol, and business justification.
  "Open port 8443" without a scoped source is a much larger change than
  "allow 10.10.10.0/24 to reach 8443."
- Confirm you have an alternate access path to the host (out-of-band
  console, or a second SSH session already open) before touching any
  rule that could affect SSH access itself — a firewall change that locks
  out your only active session is a self-inflicted outage.

## Part A — `ufw` hosts

### 1. Review current rules

```bash
sudo ufw status verbose
```

### 2. Add the rule, scoped as tightly as the requirement allows

Prefer a scoped source over a blanket allow:

```bash
sudo ufw allow from 10.10.10.0/24 to any port 8443 proto tcp
```

Only use an unscoped allow when the requirement genuinely is
"any source":

```bash
sudo ufw allow 8443/tcp
```

### 3. Verify the rule is active and ordered correctly

```bash
sudo ufw status numbered
```

`ufw` evaluates rules in order for `deny`/`reject`, so confirm a new
`allow` isn't shadowed by an earlier, broader `deny` rule above it — if
it is, use `ufw insert <NUM>` to place it correctly rather than appending
to the end.

### 4. Test from an actual source in the intended scope

```bash
curl -sv telnet://<host>:8443   # or nc -zv <host> 8443
```

Run this from a host that's actually within the scoped source range, not
just from localhost, to confirm the rule works as intended rather than
just existing.

## Part B — `firewalld` hosts

### 1. Review current *and* permanent configuration — both, not just one

This is the step that would have caught TICKET-008 before it became an
outage:

```bash
sudo firewall-cmd --zone=internal --list-all
sudo firewall-cmd --permanent --zone=internal --list-all
```

If these two don't match, **stop and investigate the drift before adding
a new rule on top of it** — an existing mismatch means the running
config could revert to something unexpected on the next reload or
reboot, independent of the new change being made now.

### 2. Add the rule to the permanent configuration

```bash
sudo firewall-cmd --permanent --zone=internal --add-port=8443/tcp
```

For a scoped source rather than a zone-wide port open, use a rich rule:

```bash
sudo firewall-cmd --permanent --zone=internal \
    --add-rich-rule='rule family="ipv4" source address="10.10.10.0/24" port port="8443" protocol="tcp" accept'
```

### 3. Reload to apply the permanent config to the runtime

```bash
sudo firewall-cmd --reload
```

### 4. Verify runtime and permanent configuration now match

```bash
sudo firewall-cmd --zone=internal --list-all
sudo firewall-cmd --permanent --zone=internal --list-all
```

Confirm the new rule appears in **both** outputs — this is the specific
check that was missing before TICKET-008, and is not optional.

### 5. Test from an actual source in the intended scope

Same as Part A step 4 — verify against a real client in the intended
source range, not just confirm the rule exists in configuration.

## Rollback

- `ufw`: `sudo ufw delete allow from 10.10.10.0/24 to any port 8443 proto tcp`
  (or `ufw delete <NUM>` using the numbered listing).
- `firewalld`: `sudo firewall-cmd --permanent --zone=internal --remove-port=8443/tcp`
  (or `--remove-rich-rule=...` matching exactly what was added), then
  `sudo firewall-cmd --reload` — and re-verify runtime/permanent match
  afterward, same as for any change.

## Change hygiene

- Record every firewall change (what, why, who, when) in the
  change-management system, not just in shell history — shell history is
  not an audit trail and doesn't survive a host rebuild.
- Prefer managing firewall rules through config management (Ansible,
  Puppet, etc.) with rules defined in version control over ad hoc
  `firewall-cmd`/`ufw` commands run by hand — TICKET-008's root cause was
  an untracked manual edit; version-controlled rules make that class of
  drift visible in a diff instead of invisible until something breaks.
- Periodically audit for runtime/permanent drift across the fleet (see
  `scripts/bash/firewall-rule-audit.sh`) rather than relying on this
  procedure's step-4 check catching every case — drift can also be
  introduced outside this procedure entirely.

## Verification checklist

- [ ] Requirement scoped to specific source/port/protocol, not broader
      than needed
- [ ] Alternate access path to the host confirmed before changing
      anything that could affect SSH/management access
- [ ] (`firewalld` only) Runtime and permanent config confirmed matching
      **before** the change
- [ ] Rule verified present in both runtime and permanent config **after**
      the change
- [ ] Tested from an actual client in the intended source scope, not just
      localhost
- [ ] Change logged in the change-management system
