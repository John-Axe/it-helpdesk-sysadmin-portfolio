# SOP — Group Policy Object deployment procedure

> Lab/practice SOP against a fictitious `contoso.local` AD domain. Not a
> real employer's procedure.

## Scope

Standard, safe procedure for authoring, testing, and rolling out a new GPO
so a bad policy doesn't hit the whole domain at once. Written after
`tickets/windows/TICKET-003-printer-gpo-deployment-failing.md` surfaced a
gap in how deployment groups were being scoped.

## Steps

### 1. Author the GPO in a non-production scope first

1. Open **Group Policy Management Console** (`gpmc.msc`) on a
   domain-joined admin workstation with RSAT installed.
2. Right-click the domain (or a dedicated `OU=GPO-Staging` test OU
   containing 1-2 volunteer test machines) → **Create a GPO in this domain,
   and Link it here...**
3. Name it descriptively with a convention the team actually follows, e.g.
   `Deploy-Printer-<Location>` or `Config-<Area>-<ShortDesc>`.
4. Edit the GPO, configure the setting(s) under **Computer Configuration**
   or **User Configuration** as appropriate. Note which one you used — this
   determines whether security filtering needs computer or user accounts
   in scope (a gap that caused a real triage delay in TICKET-003).

### 2. Scope security filtering deliberately

1. In GPMC, select the GPO → **Scope** tab → **Security Filtering**.
2. Remove the default `Authenticated Users` entry if you intend to scope
   to a specific group instead (leaving both means it applies to
   everyone regardless of group membership — a common accidental
   org-wide rollout).
3. Add the intended security group. **If the GPO is under Computer
   Configuration, the group must contain computer objects.** If under
   User Configuration, it must contain user objects. Mixing this up is the
   single most common reason a GPO silently doesn't apply.
4. Confirm via **Delegation** tab → **Advanced** that the group has both
   **Read** and **Apply group policy** permissions (adding to Security
   Filtering normally sets both automatically, but verify after any manual
   permission edits).

### 3. Test on the staging OU/group only

1. Add only the 1-2 test machines/users to the scoping group.
2. Force a policy refresh on a test machine:

   ```
   gpupdate /force
   ```

3. Confirm the GPO applied:

   ```
   gpresult /r /scope computer
   gpresult /r /scope user
   ```

   Look for the GPO name under **Applied Group Policy Objects**. If it's
   under **Denied Group Policy Objects**, check the listed reason
   (commonly `Access Denied (Security)` — the exact issue from
   TICKET-003 — or `Filtered (WMI Filter)`).
4. For a full diagnostic HTML report:

   ```
   gpresult /h C:\Temp\gpresult.html /f
   ```

### 4. Stage the rollout

1. Expand the scoping group's membership incrementally — a pilot team,
   then a department, then the full target OU — rather than adding
   everyone at once.
2. At each stage, wait at least one full background refresh cycle
   (default: 90 minutes + random 0-30 minute offset for
   non-domain-controllers) or force it explicitly with
   `Invoke-GPUpdate` for immediate validation:

   ```powershell
   Invoke-GPUpdate -Computer (Get-ADComputer -Filter * -SearchBase "OU=Target,DC=contoso,DC=local").Name -Force
   ```

3. Watch the help-desk queue for a spike in related tickets after each
   stage before proceeding to the next.

### 5. Document and close out

- Record the GPO name, purpose, scoping group, and link location in the
  team's GPO inventory doc/wiki page.
- Note any WMI filters or item-level targeting used, since those are easy
  to forget about later and can cause confusing "works for some machines,
  not others" reports.

## Rollback

If a GPO causes unexpected issues:

1. Fastest safe rollback: **disable the GPO link** rather than deleting the
   GPO outright (right-click the link in GPMC → **Link Enabled** →
   uncheck). This preserves the GPO object and its settings for
   post-mortem review while immediately stopping it from applying further.
2. Force affected machines to pick up the change:
   `Invoke-GPUpdate -Force` against the affected scope.
3. Only delete the GPO object entirely once the rollback is confirmed
   resolved and there's no further need to reference its configuration.

## Common pitfalls (from real triage)

- Security-filtering group contains the wrong object type (user vs.
  computer) for the configuration section used — see TICKET-003.
- `Enforced` set on a parent OU link overriding a child OU's blocked
  inheritance in an unexpected way — check **Group Policy Inheritance**
  tab at the target OU.
- WMI filters silently excluding machines that don't match the filter's
  OS/architecture query — check the **WMI Filtering** section of the GPO's
  **Scope** tab.
