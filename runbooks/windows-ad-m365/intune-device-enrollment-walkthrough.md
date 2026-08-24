# SOP — Intune device enrollment walkthrough

> Lab/practice SOP against a fictitious `contoso.onmicrosoft.com` tenant
> with Intune + Autopilot. Not a real employer's procedure.

## Scope

Covers two enrollment paths: (1) Windows Autopilot for new/reimaged
corporate devices, and (2) manual/BYOD enrollment for a device that needs
to be added after the fact. Also covers verifying compliance once enrolled.

## Prerequisites

- Intune license assigned to the user (bundled in the M365 E3/E5 SKUs used
  in this environment).
- MDM authority set to **Intune** (**Intune admin center** → **Tenant
  administration** → **Connectors and tokens** → confirm MDM/MAM scope is
  set to "Some" or "All", scoped to the correct group).

## Path A — Autopilot enrollment (new corporate device)

### 1. Register the device hardware hash

Before the device ships to the user, capture its hardware hash. On the
device (or via the OEM/reseller, if they support Autopilot registration
directly):

```powershell
Install-Script -Name Get-WindowsAutopilotInfo -Force
Get-WindowsAutopilotInfo.ps1 -OutputFile AutopilotHWID.csv
```

### 2. Upload to Intune

**Intune admin center** → **Devices** → **Enrollment** → **Windows
enrollment** → **Devices** → **Import** → upload `AutopilotHWID.csv`.
Wait for the sync to complete (a few minutes, sometimes up to an hour for
large batches).

### 3. Assign a deployment profile and group tag

1. **Devices** → **Enrollment** → **Windows Autopilot deployment
   profiles** → select the correct profile for the device's intended use
   (e.g. `Standard-CorpOwned-UserDriven`).
2. Set the **Group Tag** field on the imported device (or during CSV
   import) to match the department, e.g. `Sales`, so dynamic Azure AD
   groups scoped by group tag automatically pick up the right app/policy
   assignments.
3. Confirm the device shows **Profile status: Assigned** before shipping.

### 4. First-boot experience (what the end user sees)

1. Device powers on to OOBE, user connects to Wi-Fi/Ethernet.
2. Screen shows the org's branded Autopilot sign-in page (configured under
   **Enrollment** → **Windows enrollment** → **Enrollment Status Page**).
3. User signs in with their Entra ID/AD credentials (synced via AAD
   Connect).
4. Autopilot silently: joins the device to Entra ID (hybrid or cloud-only,
   per tenant config), enrolls in Intune, and applies assigned apps,
   compliance policies, and configuration profiles in the background,
   showing progress on the Enrollment Status Page.
5. Process typically completes in 15-40 minutes depending on how many apps
   are assigned; user is blocked from reaching the desktop until the
   ESP-tracked "required" apps finish, per whatever the ESP policy
   specifies.

## Path B — Manual/BYOD enrollment (existing device)

1. On the device: **Settings** → **Accounts** → **Access work or school** →
   **Connect**.
2. Enter the work email address; this triggers redirect to the org's
   Entra ID sign-in and, if configured, MFA.
3. Once signed in, Windows shows "You're all set!" — device is now
   Entra-ID-registered and MDM-enrolled.
4. On the device: **Settings** → **Accounts** → **Access work or school** →
   select the connected account → **Info** → **Sync** to force an
   immediate policy check-in rather than waiting for the default 8-hour
   check-in cycle.

## Verification

1. **Intune admin center** → **Devices** → **All devices** → search for
   the device or user name.
2. Confirm:
   - **Management state**: `Managed`
   - **Compliance**: `Compliant` (may show `In grace period` for up to the
     configured grace window if a required setting like BitLocker hasn't
     finished applying yet — not immediately alarming)
   - **Last check-in**: recent (within the last few hours)
3. Spot-check that an assigned required app installed:
   **Devices** → select the device → **Managed apps**, confirm status
   `Installed` rather than `Pending` or `Failed`.

## Troubleshooting common enrollment failures

| Symptom | Likely cause | Check |
|---|---|---|
| Stuck at "Just a few more things" on ESP for 1hr+ | A "required" app or profile is failing to install | Device → **Device install status**, find the failed item, check its error code against Microsoft's error code reference |
| Device enrolls but never shows Compliant | Compliance policy targets a group the device account isn't a member of yet (dynamic group evaluation lag) | Check dynamic group membership under **Groups** → the target group → **Dynamic membership rules**, and rule evaluation history |
| "This device is already enrolled" | Device was previously enrolled and re-imaged without being removed from Intune first | Delete the stale device record in **Intune admin center** → **Devices** → **All devices**, then retry |
| User can sign in to OOBE but Autopilot profile never applies | Hardware hash wasn't actually associated with an Autopilot profile before shipping | Confirm under **Enrollment** → **Devices**, check **Profile status** column |
