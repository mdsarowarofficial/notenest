# Activity 06 — Voice & Smart Notes

Gantt Week 5–6 (10 days) — the largest activity in the plan. Gantt deliverables:
lecture recording, speech-to-text, transcript editor, structured-note workflow.
All four are in this build.

## How to install

Unzip over `C:\project\notenest`, letting it overwrite. This one touches more
than `lib\`, so read the two steps below.

```powershell
cd C:\project\notenest
flutter pub get      # pubspec.yaml changed — three new packages
flutter analyze
flutter test
flutter run -d chrome          # dictation works here
# or, for recording and playback:
flutter emulators --launch Pixel_Flutter
flutter run
```

If `flutter pub get` complains that a package needs a newer Dart, run this
instead and send me the output — pub will pick versions that match your SDK:

```powershell
flutter pub add record audioplayers speech_to_text
```

### Files outside `lib\` that changed

| File | Why |
|---|---|
| `pubspec.yaml` | Adds `record`, `audioplayers`, `speech_to_text`. Also raises the Dart floor from 3.0.0 to 3.6.0 — left at 3.0.0, pub resolves those three to old versions whose API is different. |
| `android\app\src\main\AndroidManifest.xml` | Microphone and internet permission, and a `<queries>` entry for the recognition service. |

The manifest entry is the one that is easy to miss. From Android 11 an app can
only see other apps it has declared an interest in, so without

```xml
<intent>
    <action android:name="android.speech.RecognitionService"/>
</intent>
```

the speech plugin cannot find the device recogniser at all and dictation
reports that none is available — on a phone that plainly has one.

## New files (8)

| File | What it is |
|---|---|
| `lib/models/transcript.dart` | The structuring rules: sentence splitting, cue detection, title suggestion, note layout. Pure Dart, no plugins, unit-tested. |
| `lib/data/voice_recorder.dart` | Wraps the `record` plugin. Start/pause/resume/stop, elapsed time, microphone level, and writing the file into the attachment folder. |
| `lib/data/dictation.dart` | Wraps `speech_to_text`, and keeps it alive across the pauses in a lecture. |
| `lib/screens/capture/record_page.dart` | The recording screen: timer, live level trace, pause, save or discard. |
| `lib/screens/capture/dictation_page.dart` | Live transcript, language picker, restart counter. |
| `lib/screens/notes/transcript_editor.dart` | Fix what was misheard, then lay it out as a study note. |
| `lib/widgets/audio_player_bar.dart` | Playback for a recording attached to a note. |
| `lib/widgets/nest_level_meter.dart` | The microphone trace and the mic pulse, both `CustomPainter`. |

## Changed files (10)

| File | Change |
|---|---|
| `lib/data/app_database.dart` | Schema v4: `duration_ms` on `attachments`. |
| `lib/models/attachment.dart` | `durationMs` / `duration`, and a `label` for each type. |
| `lib/data/note_repository.dart` | `addAttachment` takes `durationMs`. |
| `lib/data/attachment_store_io.dart` + `_web.dart` | `newFilePath()` and `nameOf()`, so the recorder writes straight into the attachment folder. |
| `lib/screens/capture/capture_sheet.dart` | Record and Dictate are now separate options, and the sheet says which are phone-only. |
| `lib/screens/shell/home_shell.dart` | Wires both. |
| `lib/screens/notes/note_editor.dart` | Record / Dictate buttons, plus two correctness fixes described below. |
| `lib/screens/notes/attachment_strip.dart` | A recording shows a player across the width instead of a thumbnail. |
| `test/widget_test.dart` | 16 more unit tests over the transcript rules (34 in total). |

## Two decisions worth defending in the viva

**Recording and dictation are separate choices, not two steps.** It would be
neater to record the lecture and transcribe the file afterwards. The device
recogniser cannot do that: on Android it reads the live microphone only, and
the plugin's own documentation says transcribing a file "doesn't appear to be"
possible there. Both also want the microphone, so they cannot run at once. So
the student picks before the lecture — audio to play back, or words in the
note — and the capture sheet says which is which.

**The recogniser has to be restarted, and the screen admits it.** The platform
recogniser is built for short commands. Android ends a session after roughly
five seconds of silence with no setting to change it; Apple cuts a task off
after about a minute. A single `listen` call would therefore stop the first
time the lecturer drew breath. `Dictation` treats each session as one piece of
a longer dictation and starts a new one whenever the platform ends it, keeping
the text from before. The footer counts the restarts, because a word spoken
during the handover is the one thing this approach loses, and a counter is a
more honest interface than silence.

## The structuring is rules, not AI

`structureTranscript` splits the dictation into sentences, lifts any sentence
containing a cue such as "important", "remember" or "for the exam" into a
**Key points** block, turns sentences that open with "first", "next" or
"finally" into bullets, and groups the rest. The cue lists are at the top of
`lib/models/transcript.dart` and nothing leaves the device.

This is a deliberate limit rather than a shortcut. It works offline, it costs
nothing to run, and the student can point at the exact word that made a line a
key point. What it cannot do is understand a sentence that carries no cue —
a lecturer who says "this one always shows up" gets no key point, because
"always shows up" is not in the list.

A flagged sentence appears in both Key points and the transcript. That is on
purpose: Key points is a summary to revise from, and cutting the line out of
the transcript would leave a gap where the lecturer actually said it. There is
a test pinning that behaviour, so nobody later "fixes" it by accident.

## Two bugs found and fixed while wiring this up

**The editor could undo an attachment.** `note_editor` held the copy of the
note it was opened with. Attaching a photo, a PDF or a recording changes the
note's `type` in the database behind the editor's back, so the next autosave
wrote the stale copy back and a note full of lecture photos reverted to a
plain text note. The editor now re-reads the row before saving over it. This
was already true of Activity 04's photo and PDF buttons, not just the new ones.

**Dictating into an open note could lose the transcript.** The transcript
editor appends to the same note the editor has open. Its text controllers knew
nothing about the appended text, so the autosave would overwrite it on the
next keystroke. The editor now reloads the note when the transcript editor
reports that it saved, and the transcript editor returns there rather than
pushing another screen on top.

## Future work — speaker separation, and why it is not here

The obvious next step is the one a student actually wants: start recording, and
have the app work out on its own that the lecturer is speaking, then a student,
and lay the class out as a dialogue. It was investigated and deliberately not
built. The reasons are worth stating, because "why didn't you do it" is a fair
question to ask of this feature.

**The device recogniser cannot do it at all.** It returns text and nothing
else — `recognizedWords`, `finalResult`, `confidence`. No speaker, no
timestamps, no audio characteristics. Separating voices is not a matter of
writing better code against this plugin; the information needed to do it never
reaches the app. The recogniser also holds the microphone, so audio cannot be
analysed in parallel.

**A cloud service can do it, but not in Bengali.** AssemblyAI, Deepgram and
Google Cloud all offer speaker labels, and the free credit would cover far more
than a demo needs — AssemblyAI gives $50 without a card, and speaker labels add
$0.02 to a $0.15 hour. The blocker is the language. AssemblyAI's own supported
languages page places Bengali in its lowest band, **"Fair accuracy (>50% WER)"**
— more than half the words wrong — and does not confirm that speaker labels work
for Bengali at all. A transcript of a Bengali class would not be usable, at any
price.

**Classroom audio is the hard case for diarization anyway.** It works well with
a few speakers close to one microphone. A phone on a desk, a room with echo, and
several students talking at once is the situation these systems handle worst.

**Shipping an API key inside the app is not safe.** Anyone can pull a key out of
an APK and spend the credit. Doing it properly needs a server that holds the key
and proxies the request, which is Activity 09 work and a project of its own.

**Filling in misheard words with a language model was also rejected.** It is
possible, but when a model has not understood something it does not leave a gap
— it writes something plausible. In a lecture note that is the worst failure
there is: the student revises from a sentence the lecturer never said and has no
way of telling. A visible gap is safer than an invented fact, which is why the
transcript editor shows exactly what was heard and lets the student fix it.

What would make this feasible: on-device diarization models reaching phones, or
Bengali accuracy on a cloud service improving to the level English is at now.
Neither is a code change in this project.

## Known limitations

- **Dictation needs the device recogniser.** On Chrome that is the browser's
  Web Speech API, which needs an internet connection. On Android it is usually
  the Google app, which must be installed and allowed to use the microphone —
  on an emulator it often is not, and the error message now says so.
- **Recording needs the phone build.** The browser has no file system the app
  can write to, which is already true of photos and PDFs. The capture sheet
  marks those three options `PHONE` when running in Chrome.
- **Accuracy is the platform's, not ours.** Bengali and English both depend on
  the language pack installed on the device. The transcript editor exists
  because the recogniser will get words wrong.
- **No speaker separation and no timestamps.** A transcript is one voice with
  no times against it, so a recording and its transcript cannot be played back
  in step. That would need word-level timing, which this plugin does not give.
