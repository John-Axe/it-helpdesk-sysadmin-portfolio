# KB — Outlook search not returning results (or returning stale/incomplete results)

> Lab/practice KB article, generic guidance for Outlook desktop on
> Windows, not tied to a real environment.

## Symptom

Searching within Outlook desktop returns no results, or clearly
incomplete results, for emails the user can confirm exist (visible when
scrolling manually, or findable via webmail search for the same mailbox).
Sometimes accompanied by a yellow bar at the top of search results:
"Search Results may be incomplete because items are still being indexed."

## Likely cause

Outlook desktop search relies on the **Windows Search (Windows Search
indexer)** service to build and maintain a local index of mailbox
content. When the index is incomplete, corrupted, or simply hasn't caught
up (common after a large mailbox migration, a new PC setup, or after
Outlook was closed/crashed during indexing), search returns partial or no
results even though the actual data is present in the mailbox/OST.

## Diagnostic steps

1. Confirm the mailbox/folder is actually included in the search index
   scope: **File** → **Options** → **Search** → **Indexing Options** →
   confirm Outlook and the relevant mailbox/data file are checked under
   **Modify** → included locations.
2. Check indexing status directly in Outlook: click into the search box,
   the ribbon shows a **Search Tools** context tab — check for an
   indexing-in-progress indicator, or check **Indexing Options** in
   Control Panel, which shows an item count and whether indexing is
   currently running or complete.
3. Confirm whether the issue is isolated to Outlook or affects Windows
   Search generally (search the Start menu for a known file) — if Windows
   Search is broadly broken, the fix is at the OS service level rather
   than an Outlook-specific setting.

## Fix

### If indexing is simply behind (most common)

Let it catch up — for a large mailbox or a freshly cached OST, initial
indexing can genuinely take hours. Confirm progress is moving (item count
increasing in **Indexing Options**) rather than assuming it's stuck.

### If indexing is stuck or the index appears corrupted

1. **Control Panel** → **Indexing Options** → **Advanced** → **Rebuild**.
2. This is disruptive — rebuilding a full index from scratch on a large
   mailbox can take several hours in the background. Set expectations
   with the user accordingly; don't do this as a first-line fix for a
   simple "index is just behind" case.

### If Outlook itself isn't correctly registered with Windows Search

Sometimes caused by an Office repair being needed, or the search
component getting out of sync after certain updates:

1. Close Outlook completely.
2. **Control Panel** → **Indexing Options** → **Modify** → uncheck the
   Outlook data file location, **Apply**, then re-check it and **Apply**
   again — forces Windows Search to re-register that location as a
   fresh source.
3. Alternatively, a full **Quick Repair** via **Settings** → **Apps** →
   find Microsoft 365/Office → **Modify** → **Quick Repair** resolves
   cases where the Outlook search add-in/component itself is the problem
   rather than the index data.

### If search works in webmail but never in desktop Outlook

Points specifically at a local indexing problem rather than anything
server-side — don't spend time checking mailbox-side settings
(retention, archive policies) once webmail search is confirmed working
correctly for the same content.

## Related

This is a distinct root cause from
`tickets/windows/TICKET-002-outlook-o365-not-syncing.md`, which was a
credential-cache issue causing a full disconnection — that ticket's
symptom (Outlook not syncing at all) is more severe and has nothing to do
with search indexing specifically. Don't conflate "search doesn't find
things" with "mail isn't arriving" when triaging — they point in very
different directions.
