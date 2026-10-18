# Play Console → Data safety: answers

**Does your app collect or share any of the required user data types?** → **Yes** (only because of the optional Last.fm feature; everything else stays on the device and Google's definition of "collect" means sent off the device).

**Is all of the user data collected by your app encrypted in transit?** → Yes (Last.fm over HTTPS).

**Do you provide a way for users to request that their data is deleted?** → Yes — disconnecting Last.fm stops sending; the scrobbles themselves are deleted from the user's Last.fm account settings. All local data is deleted by uninstalling.

## Data types

| Category → type | Collected | Shared | Optional? | Purpose | Notes |
|---|---|---|---|---|---|
| App activity → **Other user-generated content / App interactions** ("music listening history") | Yes | Yes (with Last.fm) | **Optional** — only when the user connects Last.fm | App functionality | Title, artist, album and time of songs played |
| Personal info → **User IDs** (Last.fm username) | Yes | Yes (Last.fm) | Optional | App functionality, account management | Password used once to log in, never stored |

Everything else → **not collected**: location, contacts, photos/videos, audio files (they're read locally, never uploaded), files and docs, messages, financial info, health, device IDs, crash logs, diagnostics, web history.

Casting (Chromecast / DLNA) only sends the song to a device on the user's own Wi-Fi network — not "collection" under Play's definition (on-device / local network only).

If you'd rather answer **No data collected**, remove the Last.fm feature from the release build — otherwise the answer above is the honest one.
