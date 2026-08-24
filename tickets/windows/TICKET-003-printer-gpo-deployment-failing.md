# TICKET-003 — Printer deployment via GPO failing for one OU

> Lab scenario. Environment: fictitious `contoso.local` AD domain, print server
> `PRINT01`, Windows 11 clients. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P3 — Normal |
| Category | Print Services / Group Policy |
| Reported by | Multiple users, `OU=Accounting,DC=contoso,DC=local` |
| Affected system | Deployed printer `\\PRINT01\ACCT-3F-COLOR` |

## Symptom

A newly added color printer on the 3rd floor was pushed out via **Group
Policy Printer Deployment** to the Accounting OU. Users in Accounting report
the printer never appears in their printer list, even after a full reboot.
Users in the neighboring Sales OU, deployed the same way to a different
printer, are unaffected — ruling out a print-server-wide problem.

## Triage steps

1. Confirmed the GPO (`Deploy-Printer-ACCT-3F`) existed, was linked to the
   Accounting OU, and had **Enforced** unset (not overridden elsewhere) —
   checked with `gpresult` on an affected machine:

   ```
   gpresult /r /scope computer
   ```

   The GPO did **not** show up under "Applied Group Policy Objects" on the
   test machine, only under "Denied Group Policy Objects."

2. `gpresult /r` listed the reason: `Access Denied (Security)`. This meant
   the GPO's security filtering didn't include the computer or a group the
   computer was a member of.
3. Checked the GPO's **Delegation** tab in Group Policy Management Console
   (GPMC) — Security Filtering was scoped to a specific security group,
   `GG-Printers-Accounting`. Checked AD group membership for the affected
   users' computer objects:

   ```
   Get-ADGroupMember -Identity "GG-Printers-Accounting" |
       Select-Object Name, ObjectClass
   ```

   Result: the group only contained **user** objects, no **computer**
   objects. Printer deployment GPOs that deploy at the *computer* level
   need the computer accounts in scope, not just the users.
4. Confirmed the GPO's printer deployment was configured under **Computer
   Configuration** (not **User Configuration**), which is why the missing
   computer-object membership mattered.

## Root cause

The security-filtering group for the printer-deployment GPO only had user
accounts as members. Since the printer was deployed via Computer
Configuration, the GPO required the *computer* accounts to have Read +
Apply Group Policy permissions, and none did — so the policy silently never
applied to any Accounting workstation.

## Resolution

1. Added the affected computer objects to `GG-Printers-Accounting`:

   ```
   Get-ADComputer -Filter * -SearchBase "OU=Accounting,DC=contoso,DC=local" |
       ForEach-Object { Add-ADGroupMember -Identity "GG-Printers-Accounting" -Members $_ }
   ```

2. Forced a Group Policy update on a test machine and confirmed the printer
   applied:

   ```
   gpupdate /force
   gpresult /r /scope computer
   ```

   `Deploy-Printer-ACCT-3F` now appeared under "Applied Group Policy
   Objects," and the printer showed up in **Devices and Printers**.
3. Ran `gpupdate /force` remotely against the rest of the OU using
   `Invoke-GPUpdate` from the DC to avoid waiting for the normal 90-120
   minute background refresh cycle:

   ```
   Invoke-GPUpdate -Computer (Get-ADComputer -Filter * -SearchBase "OU=Accounting,DC=contoso,DC=local").Name -Force
   ```

## Follow-up / prevention

- Updated the printer-deployment SOP (`runbooks/windows-ad-m365/`) to state
  explicitly: for **Computer Configuration** printer deployment GPOs, the
  security-filtering group must contain computer objects, not user
  objects — and to add a step verifying `gpresult /r /scope computer`
  shows the GPO as **Applied** before closing any printer-deployment
  ticket.
- Recommended switching future printer deployment groups to include
  computer objects by default, populated automatically via an OU-based
  dynamic group script rather than manual membership.
