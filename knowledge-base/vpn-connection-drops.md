# KB — VPN connection drops intermittently

> Lab/practice KB article, generic guidance not tied to a specific
> commercial VPN product or real environment.

## Symptom

Corporate VPN connects successfully but drops every 10-30 minutes,
requiring the user to manually reconnect. Most common on home Wi-Fi or
public networks, less common on wired office connections.

## Likely causes, in order of frequency

1. **Wi-Fi power-saving mode on the client.** Windows' default adapter
   power management can suspend the wireless radio briefly during idle
   periods, breaking the VPN's underlying UDP/IKE session even though the
   OS reconnects Wi-Fi almost instantly — the VPN doesn't always recover
   from the brief gap on its own.
2. **NAT keepalive interval too long for the user's router.** Some
   consumer routers aggressively expire idle UDP NAT mappings (sometimes
   under 30 seconds) — shorter than the VPN client's default keepalive,
   so the tunnel's NAT mapping expires between keepalives.
3. **Underlying network instability** (weak Wi-Fi signal, ISP flapping) —
   rule this out first since it's the simplest explanation, before
   chasing a VPN-specific cause.
4. **Split tunneling / DNS conflict** causing the client to think the
   tunnel is unhealthy and tear it down defensively, even though the
   underlying connection is fine.

## Diagnostic steps

1. Check Windows' power plan for the wireless adapter:
   `Device Manager` → network adapter → **Properties** → **Power
   Management** tab → uncheck **Allow the computer to turn off this
   device to save power**.
2. Confirm which VPN protocol is in use (IKEv2, OpenVPN/UDP, WireGuard,
   etc.) — UDP-based protocols are more sensitive to NAT mapping timeouts
   than TCP-based ones.
3. If IKEv2 specifically, check for Error 809 (see
   `tickets/windows/TICKET-005-vpn-client-failing-post-update.md` for a
   related but distinct root cause — a Windows Update resetting the
   UDP encapsulation registry key).
4. Ask the user to try a wired connection if possible, to isolate Wi-Fi
   instability from a VPN-specific issue.

## Fix

- Disable Wi-Fi adapter power saving (step above) — resolves the most
  common case.
- If the client software exposes a keepalive interval setting, lower it
  below the router's observed NAT timeout (commonly 20-25 seconds is safe
  for most consumer routers; 45+ seconds is where drops start becoming
  common).
- If on IKEv2 specifically and drops started right after a Windows
  Update, check the `AssumeUDPEncapsulationContextOnSendRule` registry
  value per TICKET-005 — a different mechanism than the keepalive issue
  above, but a similarly common trigger.

## When to escalate

If drops persist on a stable wired connection with power-saving disabled
and keepalive tuned, escalate to networking to check the VPN
concentrator/gateway logs for the same time window — could indicate a
gateway-side session limit or health-check issue rather than anything
client-side.
