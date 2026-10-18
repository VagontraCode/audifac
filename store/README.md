# Publishing audifac on Google Play

Everything Play Console asks for, prepared. You need a Google Play developer account ($25 once) — the steps below are done in your account.

## 1. Host the privacy policy

Play needs a public URL. The policy is in `docs/privacy.html` (same text as `privacy-policy.md`).
GitHub → the audifac repo → Settings → Pages → Source: *Deploy from a branch*, branch `main`, folder `/docs` → Save.
The URL becomes `https://vagontracode.github.io/audifac/privacy.html` (it can take a few minutes; the repo must be public, or use any other host).

## 2. Create the app

Play Console → Create app: name **audifac**, default language English (US), App, Free.

## 3. App content (Policy → App content)

| Section | Answer |
|---|---|
| Privacy policy | the URL from step 1 |
| Ads | No, the app has no ads |
| App access | All functionality is available without special access |
| Content rating | Questionnaire → category *Music / audio / reference*; answer **No** to everything (no violence, user-generated content, gambling…). Expected rating: Everyone / PEGI 3 |
| Target audience | 13+ (not designed for children) |
| News app | No |
| Data safety | see `data-safety.md` |
| Government app / financial features / health | No |
| Foreground service permissions | `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: *Media playback — the user plays their music with the screen off; playback controls are in the notification.* Attach a short screen recording of background playback if asked |

## 4. Store listing

Texts (English + French), graphics and screenshots: see `listing.md`.

## 5. Release

1. Make sure the GitHub secrets for signing are set (see PLAN.md → Release & CI).
2. Push a tag, e.g. `git tag v0.2.0 && git push origin v0.2.0` → the CI builds the signed **AAB** (`app-release.aab`) and attaches it to the GitHub release.
3. Play Console → Testing → Internal testing → Create release → upload the AAB. Play App Signing: accept (Google re-signs with its key; your upload key is the one in `key.properties`).
4. Add testers (your Gmail) → test on your phone from the Play link.
5. When happy: Production → Create release → same AAB → roll out. New personal accounts must run a **closed test with 12 testers for 14 days** before production access is granted.

## Notes

- Versions: `version:` in `pubspec.yaml` (e.g. `0.2.0+N`); CI sets the build number from the run number, so each upload is higher.
- Android Auto: Play reviews Auto apps separately (Release → Advanced settings → Android Auto). The app declares the media-app descriptor; opt in when you've tried it in a car or the Desktop Head Unit.
