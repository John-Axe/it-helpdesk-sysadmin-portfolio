# SOP — Linux user provisioning & offboarding

> Lab/practice SOP for a small fleet of Ubuntu 22.04 LTS servers managed
> without a full IdM/LDAP layer (local users + SSH keys + sudo groups).
> Not a real employer's procedure.

## Scope

Covers provisioning a new user across a small server fleet and cleanly
offboarding one, including SSH key removal, sudo group removal, cron/at
job cleanup, and running-process checks. See
`scripts/bash/user-offboarding-script.sh` for the automated version of the
offboarding half of this SOP.

## Part 1 — Provisioning a new user

### 1. Create the local account

```bash
sudo adduser --disabled-password --gecos "Jane Smith" jsmith
```

`--disabled-password` because this environment uses SSH key auth only, no
local password login.

### 2. Add to the appropriate groups

```bash
# Standard access group, no sudo
sudo usermod -aG developers jsmith

# Only if the request explicitly grants admin rights
sudo usermod -aG sudo jsmith
```

Verify:

```bash
groups jsmith
```

### 3. Install the user's SSH public key

```bash
sudo mkdir -p /home/jsmith/.ssh
sudo tee /home/jsmith/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... jsmith@laptop
EOF
sudo chown -R jsmith:jsmith /home/jsmith/.ssh
sudo chmod 700 /home/jsmith/.ssh
sudo chmod 600 /home/jsmith/.ssh/authorized_keys
```

The exact permissions above matter — see
`tickets/linux/TICKET-002-ssh-key-auth-suddenly-failing.md` for what
happens when `StrictModes` rejects a key because the home directory or
`.ssh` folder is too permissive.

### 4. Test before handing off credentials

```bash
sudo -u jsmith ssh -T git@internal-git.contoso.local 2>&1 | head -5
```

Or simply have the new user test their own key-based login from their
workstation before considering the ticket resolved.

### 5. Repeat across the fleet (or use config management)

For more than a couple of hosts, this step should be handled by
configuration management (Ansible/Puppet/etc.) rather than manually per
server — manual per-host user creation doesn't scale and is a common
source of drift. Document which hosts a given user actually needs access
to; don't provision everywhere by default.

## Part 2 — Offboarding

Run through this checklist **in order** — disabling login first, then
cleaning up scheduled/background work, then removing the account, avoids a
window where a departing user's cron jobs keep running after their access
is supposedly revoked.

### 1. Immediately lock the account (do this first, same day as notice)

```bash
sudo usermod -L jsmith          # locks the password (defense in depth)
sudo usermod -s /usr/sbin/nologin jsmith   # blocks interactive shell
```

This alone doesn't revoke SSH key auth (key auth bypasses the password
lock) — the next step is what actually matters for this environment.

### 2. Remove SSH access

```bash
sudo mv /home/jsmith/.ssh/authorized_keys /home/jsmith/.ssh/authorized_keys.disabled-$(date +%F)
```

Renaming rather than deleting preserves the key for audit purposes for a
retention period, while immediately blocking login.

### 3. Check for and kill active sessions

```bash
who | grep jsmith
sudo pkill -KILL -u jsmith
```

### 4. Audit and remove cron/at jobs

```bash
sudo crontab -u jsmith -l
sudo crontab -u jsmith -r   # only after confirming nothing business-critical runs from this user's crontab
atq | grep jsmith           # check pending `at` jobs too
```

If the user's crontab runs something the team still needs (a report
script, a scheduled sync), migrate that job to a dedicated service account
**before** removing the user's crontab, not after.

### 5. Remove from sudo/admin groups immediately, other groups after

```bash
sudo deluser jsmith sudo
```

### 6. Full removal after the retention window (commonly 30 days)

```bash
sudo deluser --remove-home jsmith
```

`--remove-home` deletes their home directory — confirm nothing needed
(personal scripts, notes) was supposed to be handed off to a teammate
first; if so, archive `/home/jsmith` to a shared location before running
this.

### 7. Fleet-wide check

Since this environment doesn't have centralized identity, confirm the
account existed only on the hosts it was actually provisioned on
(reference the access list from Part 1) rather than assuming — run a
quick fleet-wide check if unsure:

```bash
for host in $(cat /etc/ansible/hosts-list.txt); do
    ssh "$host" "id jsmith 2>/dev/null && echo FOUND on $host"
done
```

## Checklist summary

- [ ] Account locked and shell disabled same day as offboarding notice
- [ ] `authorized_keys` renamed/removed
- [ ] Active sessions killed
- [ ] Cron/at jobs audited and migrated if needed
- [ ] Removed from `sudo` and other privileged groups
- [ ] Home directory archived if needed, then removed after retention
      window
- [ ] Confirmed no other hosts in the fleet still have the account
