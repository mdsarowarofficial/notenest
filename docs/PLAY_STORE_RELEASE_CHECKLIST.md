# NoteNest — Play Store release checklist

State on 2026-11-04, version 1.0.2+4. "Verified" means run, not just read.
(The earlier version of this file, from the October audit, said NOT READY for
reasons that have since been fixed; it was replaced rather than patched.)

## Code and build

| Item | State |
|---|---|
| Application ID `com.notenest.app`, Firebase registered for it | done |
| Release signed with the upload key, no debug fallback | done (verified: build fails without `key.properties`) |
| `flutter analyze` | clean (verified 2026-11-04) |
| Tests | 283 pass (verified 2026-11-04) |
| Firestore rules tests (`firestore-tests`, `npm test`) | 34 pass at last run; rules published by the owner |
| `targetSdk` 36, `minSdk` 24 (Flutter 3.47 defaults) | meets Play's current target requirement |
| `allowBackup=false` | done |
| Sign-in, offline sign-in message, offline sign-up, setup flow, note save, session restore | run on the emulator 2026-11-04 |
| Login/sign-up can no longer hang on an unexpected error | fixed 2026-11-04 |
| Release AAB | built 2026-11-04 as 1.0.2+4 |

## Policy

| Item | State |
|---|---|
| Privacy policy text | done, `docs/privacy-policy.html` — **owner must confirm GitHub Pages serves it** |
| In-app account deletion | done (Profile → Delete account) |
| Web page / URL for deletion requests | **owner**: Play asks for a link; the policy gives an email only |
| Report and block | done; rules published |
| Data safety form | **owner**: answers in `PRIVACY_DATA_INVENTORY.md` |
| Content rating | **owner**: chat/UGC changes the answers |
| Target audience | **owner**: 13+ |
| Reviewer test account (App access) | **owner**: make a real cloud account and put its login in the console |
| Contact email | **owner**: must be monitored and match the policy |
| Google logo on the Google button | not added; Google's branding guide wants their asset |

## Owner-only steps

1. Enable the Google Drive API in Google Cloud project `notenest-740b5` and add
   the `drive.file` scope to the OAuth consent screen.
2. Phone-test the cloud features with two accounts: email confirmation, Google
   sign-in, chat, message requests, classes and assignments, report/block,
   Drive backup and restore, account delete, fingerprint lock.
3. Back up the keystore and `key.properties` somewhere off this laptop.
4. Upload the AAB to **Internal testing** first.
5. After the first upload: add the Play app-signing SHA-1 in Firebase,
   re-download `google-services.json`, rebuild, upload again.
6. Listing text, phone screenshots (at least 2), feature graphic 1024×500.
7. Closed testing, then Production.

## Deliberately off

Push notifications (`PushService.enabled = false`). Turning them on needs the
Blaze plan, `firebase deploy --only functions`, and a two-phone test
(`docs/PUSH_SETUP.md`). Do not mention push in the listing.
