# KB — Browser certificate warning on an internal site

> Lab/practice KB article, generic guidance not tied to a real
> environment. See also
> `scripts/bash/ssl-cert-expiry-checker.sh`, which proactively catches
> the most common cause of this ticket (an expired cert) before a user
> ever hits the warning page.

## Symptom

A user reports a browser warning when accessing an internal site or
application — "Your connection is not private," "NET::ERR_CERT_DATE
INVALID," "This site is not secure," or similar, depending on browser.
Sometimes reported as "the internal wiki looks broken" without the user
recognizing the actual warning screen for what it is.

## Likely causes, in order of frequency

1. **Certificate has expired.** By far the most common cause for an
   internal site that was working fine previously and suddenly isn't —
   certificates have a fixed validity period and, unlike a public site
   behind something like a managed CDN with auto-renewal, an internal
   service's cert renewal is often a manual or semi-manual process that
   can be missed.
2. **Certificate doesn't match the hostname being used to access the
   site** (e.g. cert issued for `wiki.contoso.local` but the user is
   accessing it via a different hostname, an IP address, or a legacy
   alias not covered by the cert's Subject Alternative Names).
3. **Self-signed or internal-CA certificate not trusted by the client.**
   Common for internal-only services using a private/internal
   certificate authority — the warning is expected unless the internal
   CA's root certificate has been distributed to and trusted by client
   devices (typically via Group Policy).
4. **Certificate chain incomplete** — the server is presenting its own
   certificate but not the intermediate CA certificate(s) needed for the
   client to build a full trust chain back to a trusted root.

## Diagnostic steps

1. Click through to view the actual certificate details in the browser
   (in Chrome/Edge: click the warning icon in the address bar → **Not
   secure** → certificate details, or on the warning page itself, an
   **Advanced** or similar link often exposes the specific reason).
2. Note the specific error shown — expired, hostname mismatch, and
   untrusted-issuer each have a different fix, so don't skip straight to
   "renew the cert" without confirming that's actually the cause.
3. Check the certificate's actual expiry and subject directly from the
   command line rather than relying only on the browser's summary:
   ```
   echo | openssl s_client -connect <hostname>:443 -servername <hostname> 2>/dev/null | \
       openssl x509 -noout -dates -subject -issuer
   ```
4. If the issue is untrusted-issuer specifically, confirm whether it's
   isolated to one user/device (their machine is missing the internal
   CA root — a device provisioning gap) or affects everyone (the
   internal CA root genuinely isn't being distributed org-wide, a bigger
   issue).

## Fix

- **Expired certificate**: renew and reinstall the certificate on the
  affected service/server. If this is a recurring pattern, this is the
  signal to set up proactive expiry monitoring (see
  `scripts/bash/ssl-cert-expiry-checker.sh`) rather than waiting for
  users to report it after the fact.
- **Hostname mismatch**: either have the user access the site via the
  hostname the certificate is actually issued for, or — the better
  long-term fix — reissue the certificate with all hostnames/aliases
  actually in use included in the Subject Alternative Names.
- **Untrusted internal CA, isolated to one device**: confirm the
  device is receiving the internal root CA certificate via Group Policy
  (**Computer Configuration → Windows Settings → Security Settings →
  Public Key Policies → Trusted Root Certification Authorities**) and
  run `gpupdate /force` on the affected device, then retest.
- **Untrusted internal CA, org-wide**: escalate to the PKI/sysadmin team
  — this indicates the root CA distribution GPO itself has an issue
  (wrong OU scope, not linked, or the cert itself needs updating), not
  something resolvable on a single device.
- **Incomplete certificate chain**: reconfigure the web server to
  present the full chain (leaf + intermediate certificate(s)), not just
  the leaf certificate — a config issue on the server side, not
  something the client/browser can work around.

## When to escalate

If the certificate looks valid, correctly matched, and chain-complete
via the `openssl` check above but the browser still shows a warning,
escalate rather than continuing to troubleshoot blind — this can
indicate a client-side issue (system clock significantly wrong, breaking
validity-period checks; a intercepting proxy/AV product doing its own
TLS inspection with an outdated or misconfigured cert) that needs a
different diagnostic path than the certificate itself.
