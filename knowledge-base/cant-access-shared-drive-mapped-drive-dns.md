# KB — "Can't access shared drive" (mapped drive / DNS issue)

> Lab/practice KB article, generic guidance for a `contoso.local`-style AD
> environment, not tied to a real environment.

## Symptom

User reports a mapped network drive (e.g. `S:` for `\\fileserver\shared`)
shows a red X in File Explorer, or attempting to open it returns
"Windows cannot access \\fileserver\shared" with a vague network error.
Other mapped drives on the same machine may or may not be affected.

## Likely causes, in order of frequency

1. **DNS resolution failure for the file server name.** The single most
   common cause — the mapped drive references the server by hostname, and
   something (a DNS server change, a stale cached record, a VPN split-DNS
   misconfiguration) is preventing that name from resolving.
2. **Expired/invalid cached credentials** for the file server, especially
   after a recent password change (same underlying pattern as
   `tickets/windows/TICKET-002-outlook-o365-not-syncing.md`, applied to
   SMB shares instead of Exchange).
3. **The file server itself is down or the specific share was removed/
   renamed.**
4. **User is off-VPN and the share is only reachable from inside the
   corporate network**, but no clear error indicates this — looks
   identical to a DNS failure from the user's point of view.

## Diagnostic steps

1. Isolate DNS vs. connectivity vs. auth by testing each layer
   separately:
   ```
   nslookup fileserver.contoso.local
   ```
   If this fails to resolve, it's a DNS issue — skip to the DNS fix
   below.
   ```
   ping fileserver.contoso.local
   ```
   If DNS resolves but ping fails (and ICMP isn't blocked by policy on
   this network — confirm that first), it's likely a VPN/connectivity
   issue, not DNS.
   ```
   net use \\fileserver.contoso.local\shared
   ```
   If this specifically fails with an authentication error rather than a
   network error, it's a credentials issue.
2. Check for stale cached credentials:
   ```
   cmdkey /list
   ```
   Look for an entry for the file server with a credential that predates
   a recent password change.
3. Confirm the share still exists and the user still has permission, from
   an unaffected admin machine:
   ```
   Get-SmbShare -CimSession fileserver | Where-Object Name -eq "shared"
   ```

## Fix

- **DNS issue**: flush the client's DNS cache first, since a stale
  negative-cache entry is common after a DNS record change:
  ```
  ipconfig /flushdns
  ```
  If that doesn't resolve it, confirm the client's configured DNS servers
  are correct (`ipconfig /all`) — should point to internal DNS servers,
  not a public resolver, when on the corporate network or VPN.
- **Stale credentials**: remove the cached entry and let Windows re-prompt:
  ```
  cmdkey /delete:fileserver.contoso.local
  ```
  Reconnect the drive; Windows will prompt for fresh credentials.
- **VPN/off-network**: confirm the user is connected to VPN if working
  remotely and the share isn't published externally — this is a
  configuration/expectation issue, not a fault to fix technically.
- **Share genuinely moved/renamed**: update the mapped drive's target path
  (`net use S: \\newserver\shared /persistent:yes`) or push an updated
  drive-mapping GPO if this was an organization-wide change rather than
  fixing it one user at a time.

## Prevention

- Use **DFS Namespaces** for file shares where practical — abstracts the
  actual server name behind a namespace path, so a server migration or
  rename doesn't break every user's mapped drive letter across the
  organization.
- When rotating a service or user's password that has cached credentials
  tied to file share access, include a step in the rotation runbook to
  proactively clear `cmdkey` entries rather than waiting for a support
  ticket.
