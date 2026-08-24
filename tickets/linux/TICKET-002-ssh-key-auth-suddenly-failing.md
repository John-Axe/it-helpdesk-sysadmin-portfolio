# TICKET-002 — SSH key authentication suddenly failing

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `jump01` in
> a small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (admin access blocked) |
| Category | SSH / Access |
| Reported by | Sysadmin, unable to SSH in with normal key |
| Affected system | `jump01` |

## Symptom

SSH key login that worked yesterday now fails with:

```
Permission denied (publickey).
```

Password auth is disabled on this host by policy, so this effectively
locked the admin out over SSH (console/out-of-band access still available
via the hypervisor console, which is how this was diagnosed).

## Triage steps

1. Connected via out-of-band console access (not SSH) to investigate from
   the server side.
2. Ran SSH in verbose mode from the client to see how far the handshake got
   before failing:

   ```
   ssh -vvv admin@jump01
   ```

   Output showed the client offering the correct key
   (`Offering public key: /home/admin/.ssh/id_ed25519`), server responding
   `Authentications that can continue: publickey`, but then immediately
   rejecting — no prompt, no partial success.
3. On the server, checked `/var/log/auth.log` for the corresponding
   attempt:

   ```
   grep sshd /var/log/auth.log | tail -20
   ```

   Found: `Authentication refused: bad ownership or modes for directory
   /home/admin`.
4. Checked permissions:

   ```
   ls -ld /home/admin /home/admin/.ssh /home/admin/.ssh/authorized_keys
   ```

   `/home/admin` showed `drwxrwxrwx` (777) — world-writable. `sshd` refuses
   to trust `authorized_keys` if any component of the path up to the home
   directory is group- or world-writable, as a defense against another
   local user planting their own key.
5. Checked recent changes: a config-management run (Ansible playbook,
   applied the previous evening) had a task that recursively
   `chmod 777`'d a deployment directory using a wildcard path that
   accidentally matched `/home/admin` as well, due to an overly broad glob
   in the playbook.

## Root cause

An Ansible playbook's file-permissions task used an overly broad path glob
that unintentionally recursed into `/home/admin` and set world-writable
permissions on it. OpenSSH's `StrictModes yes` (the default, and left
enabled here deliberately) then refused to honor `authorized_keys` in that
directory as a security precaution.

## Resolution

1. Corrected ownership and permissions on the affected home directory:

   ```
   chmod 750 /home/admin
   chmod 700 /home/admin/.ssh
   chmod 600 /home/admin/.ssh/authorized_keys
   chown -R admin:admin /home/admin
   ```

2. Re-tested SSH key login — succeeded immediately, no server restart
   needed (StrictModes checks happen per-connection, not cached).
3. Audited other user home directories on the same host for the same
   glob-related damage:

   ```
   for d in /home/*; do stat -c '%A %n' "$d"; done
   ```

   Found and fixed one additional affected account.

## Follow-up / prevention

- Fixed the Ansible playbook's glob to scope explicitly to the intended
  deployment directory instead of a broad wildcard, and added a
  `--check --diff` dry-run step to the deployment pipeline so permission
  changes are reviewed before applying.
- Documented the StrictModes permission requirements in
  `runbooks/linux/ssh-hardening-checklist.md` as a quick reference for
  diagnosing "publickey" rejections that aren't actually about the key
  itself.
