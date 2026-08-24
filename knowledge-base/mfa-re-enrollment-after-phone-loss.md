# KB — MFA re-enrollment after a lost/replaced phone

> Lab/practice KB article, generic guidance for an Entra ID/M365-style MFA
> setup, not tied to a real environment.

## Symptom

User lost their phone (or it was replaced/factory reset) and can no
longer approve MFA push notifications or generate authenticator codes.
They can't sign in to anything requiring MFA, including — often — the
self-service portal that would normally let them manage their own
authentication methods, since that portal itself requires MFA to access
in most configurations.

## Why this needs identity verification, not just a quick reset

This is a case where the "fix" (removing MFA methods and letting the user
re-register) is itself a security-sensitive action — it's a common social
engineering target (an attacker claiming to have "lost their phone" to get
MFA reset onto a device they control). **Always verify identity through an
out-of-band channel before proceeding** — a callback to a known phone
number on file (not one the caller provides in the moment), a video call
with camera on and badge/ID visible, or an in-person visit, depending on
what the org's policy specifies. Do not skip this step because the
requester sounds legitimate or is in a hurry.

## Resolution steps (after identity verification)

1. Sign in to **entra.microsoft.com** (or **admin.microsoft.com** for a
   lighter-weight path) as a Global Administrator or Authentication
   Administrator.
2. Navigate to **Users** → select the affected user → **Authentication
   methods**.
3. Review the currently registered methods. If the lost phone had both
   Authenticator app and SMS registered, both may need removal if the
   phone number itself was also on that device (a replaced phone often
   keeps the same number — a factory-reset or genuinely lost/stolen phone
   may not).
4. **Require re-registration of security info** at next sign-in — the
   cleanest approach, rather than manually deleting individual methods:
   select the user → **Authentication methods** → **Require re-register
   multifactor authentication**. This forces the user to set up new
   methods on their next successful sign-in.
5. If the account has a temporary access need before the user can get to
   a machine to re-register (e.g. they need to check email right now from
   a borrowed device), issue a **Temporary Access Pass (TAP)**:
   **Authentication methods** → **Temporary Access Pass** → set a short
   validity window (e.g. one-time use, expires in 1 hour) and give the
   code to the verified user through a secure channel — never over an
   unverified inbound call.
6. Have the user sign in with the TAP (or their existing password if not
   fully passwordless) and complete MFA re-registration immediately,
   using the actual replacement device this time.

## Verification

- Confirm the old device's Authenticator registration no longer appears
  under the user's **Authentication methods** list.
- Confirm the user can successfully complete an MFA challenge with the
  newly registered method before closing the ticket.
- If a TAP was issued, confirm it has actually expired/been consumed —
  don't leave an active TAP outstanding longer than necessary.

## Related

- If the org has **Self-Service Password Reset** configured (see
  `runbooks/windows-ad-m365/self-service-password-reset-setup.md`), note
  that SSPR and MFA re-enrollment are separate flows serving different
  problems — losing a phone affects MFA methods, not necessarily the
  user's password, so don't conflate the two when scoping a fix.
