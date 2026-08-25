# IT Help Desk / Sys Admin Portfolio

A practice/lab portfolio demonstrating entry-to-mid-level IT support and
system administration competency across two environments: a Windows /
Active Directory / Microsoft 365 environment, and a Linux server
environment.

**Everything in this repository is a lab/practice scenario against a
fictitious domain (`contoso.local` / `contoso.onmicrosoft.com`) and a
small self-hosted lab (see `network-lab/topology.md`).** None of it
reflects a real employer's or customer's systems, tickets, or data — no
real hostnames, credentials, or company information appear anywhere in
this repo. Where a script or procedure resembles something you'd run
against production, treat it as a documented, safe-by-default reference
implementation, not a claim of "verified in production."

## Why this exists

This is a companion track to my
[cybersecurity engineering portfolio](https://github.com/John-Axe) —
that side demonstrates offensive/defensive security tooling; this side
demonstrates the help-desk and sysadmin fundamentals those tools
ultimately protect: account/access administration, endpoint
troubleshooting, systems hygiene, and the documentation habits (tickets,
runbooks, KB articles) that make support work repeatable instead of
tribal knowledge. Loosely modeled in spirit on
[technessjoka/it-help-desk-experience](https://gitlab.com/technessjoka/it-help-desk-experience)
— real-format case documentation, not marketing copy.

## What's here

| Directory | Contents |
|---|---|
| [`tickets/`](tickets/) | 18 ITSM-style case studies (9 Windows/AD, 9 Linux) — symptom → triage → root cause → resolution → prevention |
| [`runbooks/`](runbooks/) | 19 step-by-step SOPs (9 Windows/AD/M365, 10 Linux) covering onboarding, offboarding, hardening, recovery, patching, and incident response |
| [`scripts/powershell/`](scripts/powershell/) | 9 PowerShell scripts with comment-based help — AD/M365 automation |
| [`scripts/bash/`](scripts/bash/) | 9 Bash scripts — Linux fleet automation |
| [`knowledge-base/`](knowledge-base/) | 10 issue → solution KB articles for common end-user problems |
| [`network-lab/topology.md`](network-lab/topology.md) | Practice lab topology (Mermaid diagram) used to reproduce the scenarios above |
| [`homelab/build-guide.md`](homelab/build-guide.md) | Step-by-step guide to actually stand up the practice lab on VirtualBox/Hyper-V with free evaluation ISOs, including a VM/VLAN build-layout diagram |
| [`certifications-roadmap.md`](certifications-roadmap.md) | Planned certification path (A+, Network+, Security+, and beyond) — a roadmap, not a claim of credentials already held |

## Tickets

Each ticket follows the same structure a real ITSM tool would capture:
summary/priority/category, symptom as reported, the actual triage steps
taken (commands, menu paths, log excerpts), root cause, resolution, and a
follow-up/prevention note.

**Windows/AD:**
[account lockout](tickets/windows/TICKET-001-ad-account-lockout.md) ·
[Outlook/O365 sync](tickets/windows/TICKET-002-outlook-o365-not-syncing.md) ·
[printer GPO deployment](tickets/windows/TICKET-003-printer-gpo-deployment-failing.md) ·
[BSOD triage](tickets/windows/TICKET-004-bsod-triage.md) ·
[VPN post-update failure](tickets/windows/TICKET-005-vpn-client-failing-post-update.md) ·
[BitLocker recovery key request](tickets/windows/TICKET-006-bitlocker-recovery-key-request.md) ·
[hybrid mail-flow delay](tickets/windows/TICKET-007-teams-exchange-hybrid-mail-flow-delay.md) ·
[shared calendar permissions](tickets/windows/TICKET-008-shared-calendar-permissions-issue.md) ·
[domain trust relationship broken](tickets/windows/TICKET-009-laptop-wont-join-domain-trust-relationship.md)

**Linux:**
[`/var/log` filling disk](tickets/linux/TICKET-001-var-log-filling-disk.md) ·
[SSH key auth failure](tickets/linux/TICKET-002-ssh-key-auth-suddenly-failing.md) ·
[silent cron failure](tickets/linux/TICKET-003-cron-job-silently-not-running.md) ·
[systemd crash loop](tickets/linux/TICKET-004-systemd-service-crash-looping.md) ·
[ACL blocking app](tickets/linux/TICKET-005-permissions-acl-blocking-app.md) ·
[inode exhaustion](tickets/linux/TICKET-006-inode-exhaustion.md) ·
[NTP drift breaking Kerberos](tickets/linux/TICKET-007-ntp-clock-drift-kerberos.md) ·
[firewalld config drift](tickets/linux/TICKET-008-firewalld-blocking-app-port.md) ·
[broken unattended-upgrade](tickets/linux/TICKET-009-failed-unattended-upgrade-broken-apt.md)

## Runbooks

**Windows/AD/M365:**
[new-hire onboarding](runbooks/windows-ad-m365/new-hire-onboarding.md) ·
[SSPR setup](runbooks/windows-ad-m365/self-service-password-reset-setup.md) ·
[GPO deployment](runbooks/windows-ad-m365/gpo-deployment-procedure.md) ·
[Intune enrollment](runbooks/windows-ad-m365/intune-device-enrollment-walkthrough.md) ·
[DL/shared mailbox management](runbooks/windows-ad-m365/distribution-list-shared-mailbox-management.md) ·
[BitLocker recovery procedure](runbooks/windows-ad-m365/bitlocker-recovery-procedure.md) ·
[Conditional Access/MFA rollout](runbooks/windows-ad-m365/conditional-access-mfa-policy-rollout.md) ·
[Autopilot device provisioning](runbooks/windows-ad-m365/windows-autopilot-device-provisioning.md) ·
[file server backup & DR](runbooks/windows-ad-m365/file-server-backup-disaster-recovery.md)

**Linux:**
[user provisioning & offboarding](runbooks/linux/user-provisioning-and-offboarding.md) ·
[log rotation setup](runbooks/linux/log-rotation-setup.md) ·
[SSH hardening checklist](runbooks/linux/ssh-hardening-checklist.md) ·
[systemd recovery procedure](runbooks/linux/systemd-service-recovery-procedure.md) ·
[cron troubleshooting](runbooks/linux/cron-troubleshooting-procedure.md) ·
[staged patch management](runbooks/linux/patch-management-staged-rollout.md) ·
[disk/LVM expansion](runbooks/linux/disk-lvm-expansion-procedure.md) ·
[firewall rule change procedure](runbooks/linux/firewall-rule-change-procedure.md) ·
[backup verification & restore-test](runbooks/linux/backup-verification-and-restore-test.md) ·
[service outage incident runbook](runbooks/linux/incident-runbook-service-outage.md)

## Scripts

All scripts are **safe by default**. Anything that changes system state —
disabling an account, deleting files, restarting a service, installing
updates — defaults to a dry-run/report-only mode and requires an explicit
flag (`-Apply` in PowerShell, `--apply` in Bash) to actually act. None
reference real hostnames, domains, or credentials — placeholders like
`contoso.local` and `svc-helpdesk` are used throughout.

**PowerShell** (parser-verified with `pwsh` — see *Verification* below):
[bulk AD user creation from CSV](scripts/powershell/bulk-ad-user-creation.ps1) ·
[stale-account audit](scripts/powershell/stale-account-audit.ps1) ·
[O365 mailbox size report](scripts/powershell/o365-mailbox-size-report.ps1) ·
[disk-space alert](scripts/powershell/disk-space-alert.ps1) ·
[installed-software inventory export](scripts/powershell/installed-software-inventory-export.ps1) ·
[Intune compliance report](scripts/powershell/intune-compliance-report.ps1) ·
[AD sensitive-group membership audit](scripts/powershell/ad-group-membership-audit.ps1) ·
[O365 license utilization report](scripts/powershell/o365-license-utilization-report.ps1) ·
[BitLocker recovery-key escrow check](scripts/powershell/bitlocker-recovery-key-escrow-check.ps1)

**Bash** (verified with `bash -n` and exercised end-to-end in dry-run and,
where non-destructive, real mode):
[user offboarding](scripts/bash/user-offboarding.sh) ·
[log cleanup/rotation helper](scripts/bash/log-cleanup-rotation-helper.sh) ·
[service health check](scripts/bash/service-health-check.sh) ·
[patch/update audit report](scripts/bash/patch-update-audit-report.sh) ·
[backup script (tar + rotate)](scripts/bash/backup-tar-rotate.sh) ·
[firewall rule audit](scripts/bash/firewall-rule-audit.sh) ·
[cron job inventory across a fleet](scripts/bash/cron-job-inventory-fleet.sh) ·
[per-user disk usage report](scripts/bash/disk-quota-per-user-report.sh) ·
[SSL certificate expiry checker](scripts/bash/ssl-cert-expiry-checker.sh)

## Knowledge base

Short, single-issue articles in the style an internal help-desk wiki
would actually use: [VPN connection drops](knowledge-base/vpn-connection-drops.md) ·
["printer offline" loop](knowledge-base/printer-shows-offline-loop.md) ·
[slow login / roaming profile bloat](knowledge-base/slow-login-times-roaming-profile-bloat.md) ·
[MFA re-enrollment after phone loss](knowledge-base/mfa-re-enrollment-after-phone-loss.md) ·
[can't access shared drive (DNS)](knowledge-base/cant-access-shared-drive-mapped-drive-dns.md) ·
[Outlook search not returning results](knowledge-base/outlook-search-not-returning-results.md) ·
[BitLocker recovery prompt every boot](knowledge-base/bitlocker-recovery-key-prompt-every-boot.md) ·
[Teams camera/mic not detected](knowledge-base/teams-camera-mic-not-detected.md) ·
[OneDrive stuck syncing](knowledge-base/onedrive-stuck-syncing.md) ·
[certificate warning on internal site](knowledge-base/certificate-warning-internal-site.md)

## Homelab

[`homelab/build-guide.md`](homelab/build-guide.md) is a step-by-step
walkthrough for actually standing up the practice lab described in
[`network-lab/topology.md`](network-lab/topology.md) — free/local tools
only (VirtualBox or Hyper-V, a Windows Server evaluation ISO, Ubuntu
Server 22.04 LTS), with exact VM specs, hypervisor network setup, and
install steps, plus a second Mermaid diagram showing the VM/virtual-switch
build layout (distinct from the topology doc's logical network diagram).

## Verification

- **Bash**: every script in `scripts/bash/` passes `bash -n` (syntax
  check) and was exercised end-to-end — dry-run mode for all, and real
  (`--apply`) mode for the non-destructive backup script — against a
  scratch test directory during development.
- **PowerShell**: every script in `scripts/powershell/` was run through
  PowerShell 7.6.5's own AST parser
  (`[System.Management.Automation.Language.Parser]::ParseFile`) —
  0 parse errors across all 9 scripts. That confirms valid syntax, not
  runtime behavior against a real AD/Exchange Online tenant (these
  scripts weren't executed against real infrastructure). Review before
  running against a real environment, as you should with any script
  pulled from a portfolio repo.

## License

MIT — see [LICENSE](LICENSE).
