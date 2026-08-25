# KB — Teams doesn't detect camera or microphone

> Lab/practice KB article, generic guidance not tied to a real
> environment.

## Symptom

Microsoft Teams shows "No camera found" or "No microphone found" in
meeting settings, even though the device's camera/mic works fine in
other applications (Windows Camera app, another video conferencing tool)
or worked in Teams previously without any hardware change.

## Likely causes, in order of frequency

1. **Windows privacy settings blocking app-level camera/mic access.**
   Windows has a per-app permission toggle separate from the device
   driver itself — the hardware can be fully functional while Teams
   specifically is denied access.
2. **Another application is holding an exclusive lock on the device.**
   Some older or misbehaving apps open the camera/mic in exclusive mode
   and don't release it properly on close, blocking every other
   application (including Teams) from accessing it until that app's
   process is fully terminated.
3. **Teams cache corruption.** Teams (especially the "classic" client)
   is known to develop a corrupted local cache that affects device
   enumeration specifically, resolved by clearing the cache.
4. **Driver issue** — outdated, corrupted, or recently-updated
   camera/mic driver, especially after a Windows Update that touched
   device drivers.

## Diagnostic steps

1. Confirm the device works outside Teams first, to isolate whether this
   is Teams-specific or a genuine hardware/driver problem:
   **Settings** → **Bluetooth & devices** → **Cameras**, or open the
   **Camera** app directly and confirm video appears.
2. Check Windows privacy settings for camera and microphone access:
   **Settings** → **Privacy & security** → **Camera** — confirm
   **Camera access** is on, **Let apps access your camera** is on, and
   specifically that **Microsoft Teams** is toggled on in the per-app
   list below. Repeat for **Settings** → **Privacy & security** →
   **Microphone**.
3. Check Task Manager for other processes that might be holding the
   device — close any other video/conferencing apps entirely (not just
   minimized) and retest Teams.
4. Check Device Manager for a driver error indicator:
   **Device Manager** → **Cameras** / **Audio inputs and outputs** —
   look for a yellow warning icon next to the device.

## Fix

- **Privacy settings**: toggle camera/mic access on for Teams
  specifically, per step 2 above. This resolves the majority of cases,
  especially after a Windows feature update, which has been known to
  silently reset per-app privacy toggles.
- **Conflicting app holding the device**: fully close the other
  application (check Task Manager, not just the visible window, since
  some apps keep a background process running after the window closes),
  then restart Teams.
- **Clear Teams cache**: fully quit Teams (right-click the Teams icon in
  the system tray → **Quit**, not just closing the window), then delete
  the cache folder:
  ```
  %appdata%\Microsoft\Teams\
  ```
  *(For the "new" Teams client, the equivalent path is under
  `%localappdata%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\`.)*
  Restart Teams — it will rebuild the cache on next launch, and typically
  re-detects devices correctly at that point.
- **Driver issue**: update or reinstall the camera/mic driver via Device
  Manager, or roll back to the previous driver version if the problem
  started immediately after a driver update
  (**Device Manager** → device → **Properties** → **Driver** →
  **Roll Back Driver**, if available).

## Prevention

- If this becomes a recurring pattern fleet-wide after Windows feature
  updates specifically, flag it to the endpoint team as a pattern to
  proactively check for (re-verify camera/mic privacy toggles) as part
  of the post-feature-update device checklist, rather than waiting for
  individual tickets.
