# KB — Printer shows "offline" even though it's on and reachable

> Lab/practice KB article, generic guidance, not tied to a real environment.

## Symptom

A network printer that's powered on, connected to the network, and
reachable by other machines shows as **Offline** in one user's printer
list. Sending a print job either fails silently or queues indefinitely.
Toggling the printer's power doesn't help.

## Likely causes, in order of frequency

1. **Windows print spooler cached a stale printer status.** The most
   common cause by far — the spooler service polls printer status
   periodically and can get stuck showing stale state, especially after
   the printer briefly went offline for any reason (power blip, network
   hiccup) even if it's been back online for a while.
2. **Printer's IP address changed** (DHCP lease renewal assigned a new
   address) but the print queue is still configured to point at the old
   IP — very common for printers not on a DHCP reservation/static IP.
3. **"Use Printer Offline" got toggled on accidentally.** A genuine
   Windows setting, easy to trigger by right-clicking the printer icon at
   the wrong moment.
4. **SNMP status polling misreporting** — some printers report an
   inaccurate status via SNMP under specific firmware versions.

## Diagnostic steps

1. Confirm the printer's actual reachability first, independent of the
   Windows print queue:
   ```
   ping <printer-ip-or-hostname>
   ```
   If this fails, the issue is genuinely network/printer-side, not a
   Windows spooler caching issue — stop here and check the printer's
   physical network connection and its assigned IP from its own control
   panel.
2. Check whether "Use Printer Offline" is toggled: open **Settings** →
   **Bluetooth & devices** → **Printers & scanners** → select the
   printer → **Open print queue** → **Printer** menu → confirm
   **Use Printer Offline** is unchecked.
3. Compare the printer's actual current IP (from its own control panel or
   admin web page) against the IP configured in the Windows printer port:
   **Printer Properties** → **Ports** tab → note the configured IP,
   compare to the printer's actual current IP.

## Fix

- **Restart the Print Spooler service** — resolves the majority of "stuck
  offline" cases where the printer itself is actually fine:
  ```
  net stop spooler
  net start spooler
  ```
  (Or via `services.msc` → **Print Spooler** → **Restart**.)
- If the IP address changed: either update the port's IP directly
  (**Printer Properties** → **Ports** → **Configure Port**), or — better
  long-term — set a DHCP reservation for the printer's MAC address so its
  IP never changes again, and fix it once instead of repeatedly.
- If "Use Printer Offline" was checked, simply uncheck it.
- If none of the above resolves it, remove and re-add the printer port
  entirely (**Ports** tab → **Delete Port**, then **Add Port** with the
  correct current IP) — this clears out any corrupted port configuration
  the simpler fixes above didn't touch.

## Prevention

- Configure DHCP reservations for all networked printers so their IP
  never changes — eliminates the #2 cause entirely.
- For printers deployed via GPO (see
  `tickets/windows/TICKET-003-printer-gpo-deployment-failing.md`), use
  the print server's queue name rather than a direct IP-based port where
  possible, so an IP change is transparent to end users.
