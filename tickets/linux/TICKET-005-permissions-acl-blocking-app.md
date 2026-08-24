# TICKET-005 — File permissions/ACL issue blocking application writes

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `files01` in
> a small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High |
| Category | Filesystem / Permissions |
| Reported by | Application team, upload feature broken |
| Affected system | `files01`, shared upload directory `/srv/uploads` |

## Symptom

A file-upload feature in an internal app started failing for some users but
not others, with `PermissionError: [Errno 13] Permission denied:
'/srv/uploads/reports/'`. The app runs as service account `svc-uploader`.
Standard `ls -l` permissions on the directory looked fine
(`drwxrwxr-x svc-uploader uploaders`), which made it confusing at first —
group ownership and mode both looked correct for the service account to
write there.

## Triage steps

1. Confirmed the basic permission bits looked right:

   ```
   ls -ld /srv/uploads/reports
   ```

   ```
   drwxrwxr-x  2 svc-uploader uploaders 4096 Aug 10 09:00 /srv/uploads/reports
   ```

   `svc-uploader` owns it, group has write — should work.
2. Reproduced directly as the service account:

   ```
   sudo -u svc-uploader touch /srv/uploads/reports/test.txt
   ```

   Failed with `Permission denied`, confirming it wasn't an app-layer bug.
3. Since standard permission bits looked correct, checked for a POSIX ACL
   overriding them:

   ```
   getfacl /srv/uploads/reports
   ```

   Found an explicit ACL entry:

   ```
   user:svc-uploader:r-x
   ```

   An ACL had been added (during a prior, unrelated troubleshooting
   session weeks earlier) that explicitly granted `svc-uploader`
   **read+execute only**, no write. Because a named-user ACL entry takes
   precedence over the group permission bits shown by `ls -l`, the `rwx`
   group bit was effectively irrelevant for this specific user — `ls -l`
   doesn't surface ACLs at all (only the trailing `+` after the mode string
   hints one exists), which is why the plain permission bits looked fine.
4. Checked why only *some* users were affected: the app impersonates the
   uploading end user for some code paths but runs as `svc-uploader` for
   others (a background reprocessing job). Only the background job, which
   always ran as `svc-uploader`, was failing — interactive uploads by
   individual users (who have their own ACL entries or fall under the
   group permission) worked fine.

## Root cause

A stale POSIX ACL entry explicitly restricting `svc-uploader` to read+execute
was left over from an earlier, unrelated debugging session and was never
removed. Because named-user ACL entries take precedence over the standard
group permission bits, it silently blocked writes for that one account
while leaving other users unaffected — and was invisible to a plain
`ls -l` check.

## Resolution

1. Removed the stale ACL entry:

   ```
   setfacl -x u:svc-uploader /srv/uploads/reports
   ```

2. Verified with `getfacl` that no conflicting entry remained and that the
   standard group-write permission was now what actually applied:

   ```
   getfacl /srv/uploads/reports
   sudo -u svc-uploader touch /srv/uploads/reports/test.txt   # succeeded
   rm /srv/uploads/reports/test.txt
   ```

3. Audited the rest of `/srv/uploads` recursively for other leftover ACL
   entries from the same earlier session:

   ```
   getfacl -R /srv/uploads | grep -B2 "svc-uploader"
   ```

   Found and removed one more affected subdirectory.

## Follow-up / prevention

- Added `ls -l` reminder to the team's troubleshooting notes: a trailing
  `+` after the permission string (e.g. `drwxrwxr-x+`) means an ACL is in
  play and `getfacl` should always be checked before concluding permission
  bits alone explain a `Permission denied` error.
- Recommended that any temporary ACL applied for one-off debugging be
  tagged with a comment in the change ticket and removed at the end of the
  same maintenance window, rather than left in place indefinitely.
