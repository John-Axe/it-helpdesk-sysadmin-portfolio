# SOP — Incident runbook: service outage (detect → triage → mitigate → postmortem)

> Lab/practice incident runbook for a fictitious small Linux server
> fleet. Not a real employer's procedure. A general-purpose incident
> framework — pairs with the specific technical triage steps in
> `runbooks/linux/systemd-service-recovery-procedure.md` for the
> "diagnose and fix" phase of a systemd-managed service outage
> specifically.

## Scope

The end-to-end process for handling a service outage from first alert
through resolution and postmortem — the incident-management framework
this repo's more technical, symptom-specific runbooks (systemd recovery,
disk/LVM issues, etc.) plug into during the mitigate phase.

## Severity definitions (lab example scale)

| Severity | Definition | Example |
|---|---|---|
| SEV1 | Full outage, all users affected, no workaround | Primary database down, entire app unreachable |
| SEV2 | Partial outage or major degradation, workaround exists or subset of users affected | One of two web app instances down, load balancer routing around it |
| SEV3 | Minor degradation, limited/no user impact | Elevated error rate on a non-critical background job |

## Phase 1 — Detect

### 1. Confirm the alert is real before escalating

```bash
curl -sf https://app.contoso.local/health || echo "health check failed"
systemctl status <affected-service>
```

A monitoring false positive (a transient blip, a monitoring system's own
network hiccup) is common enough to be worth a 30-second sanity check
before paging anyone — but don't let this check turn into a long
investigation; if it's not immediately obviously a false positive within
a minute or so, treat it as real and move to Phase 2.

### 2. Assign initial severity and declare the incident

Based on the severity table above, declare the incident in whatever
channel/tool the team uses (a dedicated incident channel, paging tool
incident record, etc.) — this starts the clock for tracking and ensures
others know an incident is in progress rather than independently
investigating the same alert.

### 3. Assign an incident commander (IC)

For SEV1/SEV2: one person owns coordinating the response (not
necessarily the person fixing it) — keeps communication centralized and
prevents duplicate or conflicting remediation attempts from multiple
people acting independently.

## Phase 2 — Triage

### 1. Establish current scope and impact

- Is it one host or many? One service or a downstream cascade?
- Check other services that depend on, or are depended on by, the
  affected one — an outage often starts one layer away from where it's
  first noticed.

```bash
systemctl list-dependencies <affected-service>
```

### 2. Pull recent logs and recent changes together

```bash
journalctl -u <affected-service> --since "30 minutes ago" --no-pager
```

Cross-reference against the deploy/change log for the same window — a
service outage immediately following a deploy or config change is a
correlation worth checking first, before a longer open-ended
investigation.

### 3. Form a working hypothesis, state it explicitly

Rather than trying fixes ad hoc, state the current best theory of root
cause out loud/in the incident channel before acting on it — this keeps
the IC and responders aligned and makes it much faster for someone else
to spot a flaw in the reasoning.

## Phase 3 — Mitigate

The goal of this phase is **restoring service**, not necessarily finding
root cause yet — those can be, and often should be, sequential rather
than the same step, especially under SEV1 time pressure.

### 1. Apply the fastest safe mitigation available

In rough order of preference (fastest/lowest-risk first):
1. Restart the affected service, if the working hypothesis is consistent
   with a transient/crash-loop issue (see
   `runbooks/linux/systemd-service-recovery-procedure.md` for the
   detailed technical steps).
2. Roll back a recent deploy/config change, if the timing correlation
   from Phase 2 step 2 points at one.
3. Fail over to a redundant instance/replica, if available and the
   primary can't be quickly restored.
4. Apply a more invasive fix (e.g. a resource expansion per
   `runbooks/linux/disk-lvm-expansion-procedure.md`, a firewall
   correction per `runbooks/linux/firewall-rule-change-procedure.md`)
   once the specific root cause is identified.

### 2. Verify the mitigation actually worked

```bash
systemctl status <affected-service>
curl -sf https://app.contoso.local/health
```

Watch for a few minutes before declaring resolved — a fix that looks
clean immediately after applying can still be masking a slower-building
version of the same problem (see the same caution in the systemd
recovery runbook).

### 3. Communicate resolution

Update the incident channel/record with what was done and current
status. Downgrade or close the incident per the severity criteria once
service is confirmed stable, not just "looks okay for a minute."

## Phase 4 — Postmortem

### 1. Write it up promptly (within a few business days, while details are fresh)

Cover: timeline (detect → mitigate → resolve, with timestamps), root
cause (not just the immediate trigger — the underlying condition that
allowed it), impact (who/what was affected, for how long), and what
worked/didn't in the response itself.

### 2. Blameless framing

Focus on what allowed the failure to happen and reach production/users,
not on any individual's specific action — the goal is a system that's
harder to fail the same way again, not identifying who to blame for this
instance of it.

### 3. Extract concrete action items, each with an owner

Vague action items ("improve monitoring") don't get done. Specific ones
("add an alert on X threshold, owner: Y, by Z date") do. Track them to
completion — a postmortem with unactioned findings from last quarter is
a sign the process isn't actually preventing repeat incidents.

### 4. Feed findings back into the relevant runbook

If the incident revealed a gap in an existing runbook (a check that
should have caught it sooner, a mitigation step that wasn't documented),
update that runbook as part of closing out the postmortem — this is how
`tickets/` and `runbooks/` in this repo stay connected: an incident's
lessons become the next runbook's checklist item.

## Quick reference — incident phase checklist

- [ ] Alert sanity-checked (not a false positive) before escalating
- [ ] Severity assigned, incident declared
- [ ] IC assigned (SEV1/SEV2)
- [ ] Scope and impact established
- [ ] Logs and recent changes cross-referenced
- [ ] Working hypothesis stated explicitly before acting
- [ ] Fastest safe mitigation applied and verified
- [ ] Resolution communicated, incident closed
- [ ] Postmortem written within a few business days
- [ ] Action items assigned owners and tracked to completion
- [ ] Relevant runbook(s) updated with findings
