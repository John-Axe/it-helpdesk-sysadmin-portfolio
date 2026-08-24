# TICKET-005 — VPN client failing to connect after Windows Update

> Lab scenario. Environment: fictitious `contoso.local` domain, Windows 11,
> a generic IKEv2-based always-on VPN client. Not a real employer/customer
> ticket, and not naming any specific commercial VPN product.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (remote worker blocked) |
| Category | VPN / Networking |
| Reported by | End user, remote employee |
| Affected system | Laptop `RMT-LT-008`, Windows 11 23H2 |

## Symptom

User applied the monthly Windows cumulative update the previous night. The
next morning, the corporate VPN client fails to connect with error
`Error 809: The network connection between your computer and the VPN server
was interrupted`. Home internet is confirmed working (browsing fine). No
other remote users reported issues at the time, which pointed at something
local to this machine rather than a VPN gateway outage.

## Triage steps

1. Confirmed basic connectivity: `ping 8.8.8.8` succeeded, DNS resolution
   worked (`nslookup contoso.local` from outside the VPN correctly failed
   as expected, since that's an internal-only zone).
2. Error 809 over IKEv2 is a well-known symptom of a Windows Update
   resetting the **IPsec UDP encapsulation** registry setting needed when
   the VPN client traverses NAT (as it does from a home router). Checked:

   ```
   Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent" -Name "AssumeUDPEncapsulationContextOnSendRule"
   ```

   The value was missing — consistent with the cumulative update having
   reset/removed a customization that was normally deployed via GPO
   Registry Preference.
3. Confirmed via `gpresult /r` that the GPO responsible for this registry
   key showed as **Applied**, meaning it *should* have re-applied the
   setting on next policy refresh — but the user hadn't had network
   connectivity to reach a DC since before the update (chicken-and-egg:
   needs VPN to reach the DC, needs the registry fix to get VPN).
4. Checked Windows Update history to confirm which cumulative update
   installed the previous night, to note it in the ticket for pattern
   tracking across other remote users.

## Root cause

The Windows cumulative update reset
`AssumeUDPEncapsulationContextOnSendRule` to its default (`0`), which
breaks IKEv2 VPN negotiation when the client is behind NAT (true for
virtually all home routers). The GPO that normally sets this value to `2`
couldn't reapply because the machine had no way to reach a domain
controller without VPN connectivity in the first place.

## Resolution

1. Manually set the registry value over a phone-guided remote session
   (user ran the command locally since the machine couldn't reach the
   DC):

   ```
   New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent" `
       -Name "AssumeUDPEncapsulationContextOnSendRule" -PropertyType DWord -Value 2 -Force
   ```

2. Rebooted the machine, VPN connected successfully on the next attempt.
3. Confirmed `gpresult /r` now showed the GPO reapplying cleanly once the
   machine had VPN/domain connectivity again, keeping the value in sync
   going forward.

## Follow-up / prevention

- Flagged the pattern to the networking team: any client-side Windows
  update has the potential to strand remote-only devices in this exact
  chicken-and-egg state. Recommended documenting a **local-only recovery
  registry command** (as used above) in the VPN troubleshooting KB article
  (`knowledge-base/vpn-connection-drops.md`) so future cases can be
  self-serviced by walking the user through the registry fix over the
  phone without needing DC connectivity.
- Suggested to the sysadmin team that this specific registry value be set
  via a **local Group Policy** or startup script baked into the device
  image, rather than relying solely on a domain GPO that requires network
  access to reapply.
