# SOP — Self-Service Password Reset (SSPR) setup and user enrollment

> Lab/practice SOP against a fictitious `contoso.onmicrosoft.com` Entra ID
> tenant. Not a real employer's procedure.

## Scope

Enable SSPR at the tenant level, scope it to the correct group, and walk a
user through registering their security methods so they can reset their own
password without opening a help-desk ticket.

## Prerequisites

- Global Administrator or Authentication Policy Administrator role in
  Entra ID.
- Decide license tier: **Basic SSPR** (password-only, no writeback to
  on-prem AD, works in cloud-only tenants) vs. **Premium SSPR** (requires
  Entra ID P1/P2, needed here because the environment is hybrid and must
  write the new password back to on-prem AD).

## Part 1 — Enable SSPR at the tenant level

1. Sign in to **entra.microsoft.com** as a Global Administrator.
2. Navigate to **Protection** → **Password reset** → **Properties**.
3. Set **Self service password reset enabled** to either:
   - `All` (org-wide) — simplest, but usually only appropriate for smaller
     orgs, or
   - `Selected` — scoped to a security group (recommended for staged
     rollout). Select `GG-SSPR-Pilot` for an initial pilot group before
     expanding org-wide.
4. Save.

## Part 2 — Configure authentication methods

1. **Protection** → **Password reset** → **Authentication methods**.
2. Set **Number of methods required to reset** to `2` (defense against a
   single compromised factor being enough to take over the account).
3. Enable at minimum:
   - Microsoft Authenticator app (push notification)
   - Phone (SMS or voice call)
   - Do **not** enable security questions alone as a sufficient method —
     they're the weakest factor and should only ever be a secondary
     option layered with something else, if used at all.

## Part 3 — Enable writeback to on-prem AD (hybrid environments)

Required so a password reset in the cloud actually changes the user's
on-prem AD password (which is what actually authenticates them via
Kerberos/NTLM against `contoso.local`), not just the cloud-side hash.

1. On the **Azure AD Connect** server, re-run the configuration wizard:

   ```
   Start-Process "C:\Program Files\Microsoft Azure AD Sync\bin\miisclient.exe"
   ```

   Or launch the AAD Connect wizard directly and choose
   **Customize synchronization options**.
2. Check **Password writeback** on the **Optional features** page, step
   through, and click **Configure**.
3. Confirm the writeback service account has the correct **Reset password**
   delegated permission on the relevant OUs — this must be granted
   explicitly in ADUC (**Delegate Control** wizard on each OU) if not
   already covered by an existing delegation.
4. Verify:

   ```powershell
   Get-ADSyncAADPasswordResetConfiguration
   ```

   Should report `Enabled: True`.

## Part 4 — Conditional Access exclusion check

Confirm SSPR's own registration flow (a first-time sign-in to
`aka.ms/ssprsetup`) isn't blocked by a Conditional Access policy requiring
MFA that the user hasn't registered for yet — this is the most common
"user can't even get to the registration page" support request. If needed,
create a scoped CA policy excluding the SSPR registration app during a
grace period, or rely on Entra ID's built-in **combined registration**
flow, which handles this correctly by default in most tenants.

## Part 5 — User enrollment walkthrough (what to tell the end user)

1. Go to **myaccount.microsoft.com** → **Security info** → **Add sign-in
   method**, or `aka.ms/ssprsetup` directly.
2. Add at least two methods: install **Microsoft Authenticator**, scan the
   QR code shown, approve the test notification; then add a phone number
   for SMS backup.
3. Confirm registration completed:
   `myaccount.microsoft.com` → **Security info** should list both methods
   with green checkmarks.
4. Test the actual reset flow once, from a private/incognito browser
   window, at `passwordreset.microsoftonline.com`, to confirm end-to-end
   before relying on it during an actual lockout.

## Verification checklist

- [ ] SSPR enabled for the correct scope (pilot group or org-wide)
- [ ] Two-method minimum enforced
- [ ] Password writeback confirmed enabled and delegation permissions
      granted (hybrid only)
- [ ] Conditional Access doesn't block the registration flow
- [ ] Test reset performed successfully end-to-end by at least one pilot
      user

## Common failure points

- Writeback silently fails if the AAD Connect service account lacks
  **Reset password**, **Write permissions**, and **Unexpire password**
  permissions on the target OU — check via **Delegate Control** in ADUC.
- Users report "I don't see the reset option" — almost always means they
  haven't completed registration yet, not an actual tenant
  misconfiguration; direct them to `aka.ms/ssprsetup` first.
