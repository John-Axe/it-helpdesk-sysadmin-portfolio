# Certifications roadmap

> Honest framing: these are certifications I am planning to pursue, in
> the order below, not credentials I currently hold. This page tracks
> intent and target timeline, not achievement. I'll update it (and link
> the actual credential) as/if each one is completed.

## Why this order

The plan follows a fairly standard entry-to-mid-level IT support track:
broad hardware/OS/networking fundamentals first, then a security
baseline, then platform-specific depth in the two environments this
portfolio focuses on (Windows/AD/M365 and Linux).

## Planned certifications

### 1. CompTIA A+ (Core 1 + Core 2)

- **Status**: Not started
- **Target**: Foundational — planned as the first certification
- **Why**: Broadest entry-level validation of hardware, OS, networking,
  troubleshooting, and operational procedure fundamentals. Directly
  overlaps with the BSOD triage, printer, and general desktop-support
  scenarios documented in `tickets/windows/`.

### 2. CompTIA Network+

- **Status**: Not started
- **Target**: After A+
- **Why**: Deepens the networking fundamentals A+ only partially covers —
  directly relevant to the VPN, DNS, and DHCP troubleshooting scenarios in
  this repo (`tickets/windows/TICKET-005-vpn-client-failing-post-update.md`,
  `knowledge-base/cant-access-shared-drive-mapped-drive-dns.md`) and to
  understanding the lab topology in `network-lab/topology.md` at a deeper
  level than "it works."

### 3. CompTIA Security+

- **Status**: Not started
- **Target**: After Network+
- **Why**: Baseline security certification expected for many mid-level IT
  support and sysadmin roles, and a natural bridge toward the adjacent
  cybersecurity-engineering portfolio track. Directly relevant to the
  SSH-hardening, ACL/permissions, and MFA/credential-hygiene material
  already in this repo
  (`runbooks/linux/ssh-hardening-checklist.md`,
  `knowledge-base/mfa-re-enrollment-after-phone-loss.md`).

### 4. Microsoft Certified: Modern Desktop Administrator Associate / Endpoint Administrator Associate (MD-102)

- **Status**: Not started
- **Target**: After Security+
- **Why**: Validates Intune/Autopilot/M365 endpoint management skills
  directly — matches the content in
  `runbooks/windows-ad-m365/intune-device-enrollment-walkthrough.md` and
  `runbooks/windows-ad-m365/new-hire-onboarding.md`.

### 5. Microsoft Certified: Identity and Access Administrator Associate (SC-300) — stretch goal

- **Status**: Not started, tentative
- **Target**: After MD-102, depending on role direction
- **Why**: Deepens the Entra ID/hybrid identity material touched on in
  `runbooks/windows-ad-m365/self-service-password-reset-setup.md` and the
  AD/Entra sync content throughout the Windows runbooks — most relevant
  if career direction leans toward identity/M365 administration
  specifically rather than generalist sysadmin work.

### 6. Linux Foundation Certified System Administrator (LFCS) or Red Hat Certified System Administrator (RHCSA) — parallel track

- **Status**: Not started
- **Target**: In parallel with, or shortly after, the Microsoft track
  above — not strictly sequential, since Linux and Windows skills are
  being built concurrently (as reflected by this repo covering both)
- **Why**: Validates the Linux sysadmin fundamentals already demonstrated
  in `runbooks/linux/` and `scripts/bash/` — systemd service management,
  user/permission administration, cron, log management, SSH hardening.
  Choosing between LFCS and RHCSA will depend on which distro family
  ends up more relevant to whatever role this leads to; both are
  reasonable next steps from the Ubuntu-based material in this repo.

## Not currently planned, but noted for context

- Vendor-specific advanced certifications (e.g. CCNA, deeper Microsoft
  Expert-level tracks) are intentionally out of scope for now — the goal
  of this roadmap is a solid, verifiable entry-to-mid-level foundation
  across both platforms before specializing further.

## How this page will be updated

As each certification is actually completed, this entry will be updated
with the completion date and, where the certifying body provides one, a
link to the verifiable credential — nothing on this page should be read
as already-held until it's explicitly marked complete.
