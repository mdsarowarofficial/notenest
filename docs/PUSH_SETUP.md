# Push notifications: what to deploy

NoteNest can notify a phone that has the app closed about:

- a message in a chat or a class chat
- a message request
- a post in a class (announcement, material, assignment)
- a note someone sent you

The app side is built in. The part that has to run in the cloud is the Cloud
Function in `functions/index.js`, because a closed phone cannot hear Firestore.
Until it is deployed, nothing changes for anyone: the app registers each phone
quietly and no notification is ever sent.

**Status:** the app and the rules are tested (the rules by `npm test` in
`firestore-tests/`, 34 passing). The function has not been run against the real
project, because that needs your Firebase account. Try it once with two phones
before telling anyone it works.

## One-time setup

1. **Blaze plan.** Cloud Functions need the pay-as-you-go plan. Push for a class
   app is a handful of invocations a day, which sits inside the free quota, but
   the plan must be switched on (Firebase console → Usage and billing).
2. **Install and deploy** (from the project folder):

   ```
   cd functions
   npm install
   cd ..
   firebase deploy --only firestore:rules,functions
   ```

   The rules deploy is needed too: it adds `pushTokens/{uid}`, where each phone
   leaves its address. Only its owner can read or write that document.
3. **Turn it on in the app:** set `PushService.enabled = true` in
   `lib/data/push_service.dart`. It is off by default so nobody is asked to allow
   notifications that cannot arrive yet.
4. **Build and install the app** (a new build, because it now asks for the
   notification permission and uses Firebase Messaging).

## How to check it works

1. Sign in to the cloud on two phones as two different people who are allowed
   to talk (a class, or an accepted request).
2. Close the app on phone B (swipe it away).
3. Send a message from phone A. Phone B should show a notification within a few
   seconds.
4. If it does not, open Firebase console → Functions → Logs. A function that
   ran but sent nothing usually means phone B has no document in `pushTokens`
   (permission was refused, or the app was never opened signed in to the cloud).

## What is stored and sent

- `pushTokens/{uid}`: up to five phone addresses for that account, and a time.
  Removed when the person signs out of the cloud on that phone.
- The notification carries a short preview (a text message is cut at 120
  characters; a note, photo or voice message is shown as a label). It is
  visible on a lock screen, which is how every messaging app works; add that to
  the privacy policy if it is not there.
- People who have blocked the sender are skipped.

## Not done

- Tapping a notification opens the app but does not jump to the conversation.
- Assignment deadlines are not pushed. They are covered by the phone-side
  reminders in Settings, which need no server.
