# SOP — SSH hardening checklist

> Lab/practice checklist for Ubuntu 22.04 LTS `sshd`. Not a real employer's
> procedure. Written to also cover the diagnostic angle from
> `tickets/linux/TICKET-002-ssh-key-auth-suddenly-failing.md`.

## Scope

Baseline hardening steps for a new server's SSH daemon, plus the
permission requirements that `StrictModes` enforces (a frequent source of
"my key stopped working" tickets that have nothing to do with the key
itself).

## Steps

### 1. Disable password authentication, enforce key-only

`/etc/ssh/sshd_config`:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

**Before applying**, confirm at least one admin's SSH key is already
installed and tested — locking out password auth without a working key in
place is how you get locked out of a box that only has console/OOB access
as a fallback.

### 2. Disable root login over SSH

```
PermitRootLogin no
```

Use `sudo` after logging in as a named user instead. If a specific
break-glass scenario needs root SSH (rare, generally avoid), use
`PermitRootLogin prohibit-password` instead of a flat `no`, which still
allows root key-based login but blocks root password login — but the
strong preference is `no` with sudo for everything.

### 3. Restrict which users/groups can SSH in at all

```
AllowGroups ssh-users sudo
```

Only accounts in `ssh-users` or `sudo` groups can authenticate over SSH at
all — service accounts and other local-only accounts are blocked from
remote login even if they had a key configured by mistake.

### 4. Change the default port (optional, low-value but common ask)

Mostly reduces automated scan/brute-force log noise, not a real security
boundary on its own — don't treat it as a substitute for the other
controls here. If used:

```
Port 2222
```

Update any firewall rules (`ufw allow 2222/tcp`) and document it clearly —
this is the single most common cause of "I can't reach the server
anymore" self-inflicted lockouts after a hardening pass.

### 5. Enforce `StrictModes` (should already be the default — verify)

```
StrictModes yes
```

This makes `sshd` refuse to honor a user's `authorized_keys` file if any
component of the path (home directory, `.ssh`, the file itself) is
group- or world-writable. Required permissions:

```bash
chmod 750 /home/<user>          # or 700 — 750 only if group-readable is intentional
chmod 700 /home/<user>/.ssh
chmod 600 /home/<user>/.ssh/authorized_keys
chown -R <user>:<user> /home/<user>/.ssh
```

**Diagnostic note**: if a user's key auth suddenly fails with
`Permission denied (publickey)` and nothing about the key itself changed,
check `/var/log/auth.log` for `Authentication refused: bad ownership or
modes` before assuming the key is bad — this was the actual root cause in
TICKET-002 (a config-management run accidentally set `/home/<user>` to
777).

### 6. Set idle timeout and connection limits

```
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 4
MaxSessions 10
```

Drops idle sessions after 10 minutes of no response, and limits repeated
auth attempts per connection to slow down brute-force attempts (this
complements, doesn't replace, fail2ban or a similar tool for actually
banning repeat offenders — see step 8).

### 7. Restrict SSH protocol/ciphers to modern-only

```
Protocol 2
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

Verify compatibility with whatever SSH clients/tools the team actually
uses before applying broadly — a very old client library could be locked
out by disabling legacy algorithms.

### 8. Install fail2ban for actual ban enforcement

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
```

Default `sshd` jail is usually sufficient as a starting point; confirm
with:

```bash
sudo fail2ban-client status sshd
```

### 9. Validate config before restarting the daemon

```bash
sudo sshd -t
```

**Always** run this before restarting `sshd` — a syntax error in
`sshd_config` combined with restarting the service can leave the server
completely unreachable over SSH with no automatic rollback.

```bash
sudo systemctl restart sshd
```

### 10. Test from a **new** session before closing the existing one

Open a fresh terminal and SSH in as a normal user to confirm the change
didn't break access, while keeping your current session open as a
fallback. Never close the only working session before confirming the new
config works.

## Verification checklist

- [ ] Password auth disabled, key auth confirmed working first
- [ ] Root SSH login disabled
- [ ] `AllowGroups`/`AllowUsers` scoped correctly
- [ ] `StrictModes yes`, and all user home/`.ssh`/`authorized_keys`
      permissions confirmed correct
- [ ] `sshd -t` passed before restart
- [ ] New session tested successfully before closing the old one
- [ ] fail2ban active and jailing on `sshd`
