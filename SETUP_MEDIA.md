# Activity 04 — media capture

This finishes Note Management: photographed pages, cropping, and PDFs.

## 1. Add the packages

```
flutter pub add image_picker image_cropper file_picker path_provider
flutter pub add syncfusion_flutter_pdfviewer
```

## 2. Android configuration

The cropper runs in its own Android screen, which has to be declared.

Open `android/app/src/main/AndroidManifest.xml`. Inside `<application>`, just
before the closing `</application>`, add:

```xml
<activity
    android:name="com.yalantis.ucrop.UCropActivity"
    android:screenOrientation="portrait"
    android:theme="@style/Theme.AppCompat.Light.NoActionBar" />
```

Then open `android/app/build.gradle.kts` (or `build.gradle`) and make sure the
minimum SDK is at least 21:

```kotlin
minSdk = 21
```

Leave it alone if it is already higher.

No camera permission line is needed. `image_picker` opens the system camera
app, which carries its own permission, and declaring `CAMERA` yourself would
force you to request it at runtime for no benefit.

## 3. Place the files

New:

```
lib/models/attachment.dart
lib/data/attachment_store.dart
lib/data/attachment_store_io.dart
lib/data/attachment_store_web.dart
lib/screens/capture/media_capture.dart
lib/screens/notes/attachment_strip.dart
lib/screens/viewer/image_viewer.dart
lib/screens/viewer/pdf_viewer.dart
```

Replace: `lib/data/app_database.dart`, `lib/data/note_repository.dart`,
`lib/screens/capture/capture_sheet.dart`, `lib/screens/shell/home_shell.dart`,
`lib/screens/notes/note_editor.dart`, `lib/screens/notes/note_detail.dart`,
`lib/widgets/note_tile.dart`.

Easiest is to delete `lib/` and `test/` and drop in the ones from the archive.

## 4. Run on the emulator

Open Android Studio, Device Manager, create a Pixel device if you have none,
and start it. Then:

```
flutter devices
flutter run
```

The database migrates itself from version 2 to 3, so your account, subjects and
notes survive. Nothing needs clearing.

## What to try

1. Capture button, **Photograph handwriting**, Take a photo. The emulator
   camera shows a test scene; shoot it.
2. The cropper opens. Drag the corners, rotate, confirm.
3. The note editor opens with the page attached. Add a second page.
4. Capture button, **Add a PDF**. Pick any PDF. Open it from the note and page
   through it.
5. Delete a note, check Trash, restore it, confirm the pages are still there.

## Two things worth knowing

**Only the file name is stored, never the full path.** The folder an app owns
changes between installs and devices, so an absolute path would break every
attachment the first time the app is reinstalled. The folder is asked for at
runtime and the name is joined onto it.

**Files are copied, not referenced.** A picked image sits in a cache the system
can clear whenever it likes. Each one is copied into the app's own folder
before its name is written to the database, so a note never loses its pages.

**On Chrome, attachments are switched off.** The browser has no file system the
app can write to. The build still compiles and everything else works; the
photo and PDF options explain that they need the phone app. Run on the emulator
for this part.

**Syncfusion licensing.** `syncfusion_flutter_pdfviewer` is free under their
community licence for individuals and small companies, which covers a student
project. Worth a line in your report.
