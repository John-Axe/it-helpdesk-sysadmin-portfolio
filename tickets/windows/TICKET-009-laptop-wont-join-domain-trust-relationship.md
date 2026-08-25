# TICKET-009 — Laptop can't authenticate to domain, "trust relationship" error

> Lab scenario. Environment: fictitious `contoso.local` domain, Windows 11
> domain-joined laptop. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (user fully blocked from logging in) |
| Category | Active Directory / Domain Trust |
| Reported by | End user, in person at the help desk |
| Affected system | Laptop `HQ-LT-071`, Windows 11 23H2, domain-joined |

## Symptom

User's laptop had been sitting powered off over a two-week vacation.
On return, attempting to log in with their domain account failed with:

```
The trust relationship between this workstation and the primary domain
failed.
```

Logging in with a **local** administrator account (kept for exactly this
scenario) worked fine, confirming the OS itself was healthy and the
problem was specifically the machine's domain trust.

## Triage steps

1. Logged in locally as the break-glass local admin to investigate rather
   than immediately rejoining the domain, to first confirm root cause
   instead of just applying the standard fix blind.
2. Confirmed basic network/DC reachability wasn't the issue:

   ```
   Test-ComputerSecureChannel -Verbose
   ```

   Returned `False`, with a verbose error consistent with the machine's
   computer account password being out of sync with what AD has on file
   — not a connectivity problem (DC was reachable, DNS resolved fine).
3. Checked the machine account's `pwdLastSet` attribute in AD to confirm
   the theory:

   ```
   Get-ADComputer -Identity "HQ-LT-071" -Properties PasswordLastSet
   ```

   Showed a `PasswordLastSet` value roughly 35 days old — just past the
   default 30-day computer account password change interval
   (`DisablePasswordChange` was not set, so this is expected default
   behavior). Since the laptop was off for the past two weeks, it never
   had a chance to perform its scheduled password rotation, and by the
   time it powered back on, its locally cached password no longer matched
   what AD expected — a very common cause after any extended time offline
   (long vacation, an unused loaner laptop, etc.).
4. Ruled out a more serious cause (the machine being deleted/reset in AD,
   or a genuine name conflict) by confirming the computer object still
   existed in AD with the same SID as recorded in earlier device
   inventory records — a full domain rejoin (leave + rejoin) is needed
   instead of a simple secure-channel reset if the AD object itself is
   gone or reset, so it was worth ruling out before picking the fix.

## Root cause

The computer account's Kerberos secure-channel password, normally rotated
automatically every 30 days by default AD domain member policy, went
stale while the laptop was powered off for two weeks and unable to
perform its scheduled rotation. On return, the machine's locally cached
password no longer matched AD's copy, breaking the secure channel used
to authenticate domain logons — independent of the user's own account,
which was never the problem.

## Resolution

1. Since the computer object itself was intact (not deleted/reset),
   used a secure-channel reset rather than a full domain leave/rejoin —
   faster and non-disruptive to the machine's existing local profile:

   ```
   Reset-ComputerMachinePassword -Server dc01.contoso.local -Credential (Get-Credential)
   ```

   Credential supplied was a domain account with rights to reset computer
   account passwords (not Domain Admin — delegated permission scoped to
   the OU, per least-privilege).
2. Rebooted the laptop.
3. Confirmed the fix:

   ```
   Test-ComputerSecureChannel -Verbose
   ```

   Returned `True`.
4. User logged in with their domain account and existing profile — no
   profile loss, since the fix operates at the machine-trust level and
   doesn't touch the user's local profile.

## Follow-up / prevention

- Flagged to the sysadmin team that devices expected to sit powered off
  for extended periods (loaner pool, seasonal staff, long-leave
  employees) are a predictable source of this exact ticket — considered,
  but decided against, extending the default 30-day machine password
  change interval domain-wide, since shortening the exposure window is
  better security practice than accommodating infrequently-used
  hardware; instead added a note to the device-return checklist to
  proactively run `Test-ComputerSecureChannel` (and reset if needed)
  before handing a long-idle device back to a user, catching this before
  it becomes a help-desk ticket.
- Added this scenario to the standing help-desk quick-reference: "trust
  relationship" error + local admin login works = check
  `Test-ComputerSecureChannel` before assuming a full rejoin is needed;
  a secure-channel reset is faster and preserves the local profile.
