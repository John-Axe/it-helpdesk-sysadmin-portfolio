# KB — Slow sign-in times caused by roaming profile bloat

> Lab/practice KB article, generic guidance, not tied to a real
> environment.

## Symptom

A user reports Windows sign-in taking several minutes, showing "Applying
user settings" or "Welcome" for an unusually long time compared to
colleagues. Often more noticeable when the user switches machines (shared
workstation environments, hot-desking) since a roaming profile has to be
downloaded fresh on an unfamiliar machine.

## Likely cause

In an environment using **roaming user profiles** (profile follows the
user between machines, stored centrally on a file server), sign-in time is
directly proportional to profile size — the entire profile has to copy
down from the server on login and back up on logout. A profile that's
grown large (browser cache, Downloads folder, Outlook OST/PST files, or
just years of accumulated desktop/documents clutter not covered by
folder redirection) causes proportionally slower logins.

## Diagnostic steps

1. Check the profile's actual size on the file server:
   ```
   Get-ChildItem "\\fileserver\profiles$\jsmith" -Recurse -ErrorAction SilentlyContinue |
       Measure-Object -Property Length -Sum |
       Select-Object @{N='SizeGB';E={[math]::Round($_.Sum / 1GB, 2)}}
   ```
2. Break it down by subfolder to find the actual offender:
   ```
   Get-ChildItem "\\fileserver\profiles$\jsmith" -Directory |
       ForEach-Object {
           $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
           [PSCustomObject]@{ Folder = $_.Name; SizeGB = [math]::Round($size / 1GB, 2) }
       } | Sort-Object SizeGB -Descending
   ```
   Very commonly the largest offenders are `AppData\Local` (browser
   caches, application data that shouldn't roam at all) and a local
   Outlook OST file that ended up inside the roaming portion of the
   profile instead of being excluded.
3. Compare against the org's folder-redirection policy (if configured) —
   check whether Documents/Desktop/Downloads are actually being redirected
   to a network location (which keeps them out of the roaming profile
   proper) or if redirection silently isn't applying for this user
   (check `gpresult /r` for the relevant GPO).

## Fix

- **Exclude `AppData\Local`, browser cache folders, and the Outlook OST
  path from the roaming profile** via the `ExcludeProfileDirs` registry
  value or, more commonly, GPO setting under **Computer Configuration** →
  **Administrative Templates** → **System** → **User Profiles** →
  **Exclude directories in roaming profile**.
- Confirm **Folder Redirection** is applying correctly for this user — if
  it isn't, that's a separate, likely higher-impact issue: their Documents
  and Desktop files are bloating the *roaming* profile instead of living
  in redirected network folders that don't need to copy on every
  login/logout.
- One-time cleanup: have the user (or IT, with permission) clear browser
  cache and clean out an oversized Downloads folder — provides immediate
  relief while the policy-level fix (exclusions) takes effect for future
  growth.
- If Outlook is configured in cached mode with the OST inside the roaming
  profile path, relocate it to a local, non-roaming path
  (`AppData\Local\Microsoft\Outlook` is correct by default in modern
  Outlook — verify it hasn't been redirected incorrectly by a legacy
  policy).

## Prevention

- Set a profile size **warning and hard-cap quota** on the file server
  hosting roaming profiles, so bloat is caught proactively via alert
  rather than discovered via a slow-login complaint.
- Periodically audit the `ExcludeProfileDirs` GPO setting against actual
  application data folders in use — new applications sometimes write
  large local caches into paths not covered by the original exclusion
  list.
