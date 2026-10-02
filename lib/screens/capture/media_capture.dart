import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/attachment_store.dart';
import '../../data/note_repository.dart';
import '../../models/attachment.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';

/// Picking, cropping and filing the material a note is built from.
///
/// Each function copies the chosen file into the app's own folder, records it
/// against the note, and returns true when something was added. The note must
/// already exist, so an attachment always has an owner.
class MediaCapture {
  MediaCapture._();

  static final _picker = ImagePicker();

  /// Photograph a page, straighten it, and file it under [note].
  static Future<bool> captureHandwriting(
    BuildContext context, {
    required Note note,
    required ImageSource source,
  }) async {
    if (!_supported(context)) return false;

    final shot = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (shot == null) return false;

    final path = await _cropPage(shot.path);
    if (path == null) return false;

    final stored = await AttachmentStore.saveFile(path, _extension(path, 'jpg'));
    final size = await AttachmentStore.sizeOf(stored);

    await NoteRepository.instance.addAttachment(
      note: note,
      type: AttachmentType.image,
      fileName: shot.name,
      storedName: stored,
      sizeBytes: size,
    );
    return true;
  }

  /// Attach a PDF chosen from the device.
  static Future<bool> attachPdf(
    BuildContext context, {
    required Note note,
  }) async {
    if (!_supported(context)) return false;

    // file_picker 12 dropped FilePicker.platform and the result wrapper:
    // pickFile returns the chosen file directly, or null if nothing was taken.
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null || picked.path == null) return false;

    final stored = await AttachmentStore.saveFile(picked.path!, 'pdf');
    final size = await AttachmentStore.sizeOf(stored);

    await NoteRepository.instance.addAttachment(
      note: note,
      type: AttachmentType.pdf,
      fileName: picked.name,
      storedName: stored,
      sizeBytes: size,
    );
    return true;
  }

  /// Opens the cropper so a photographed page can be straightened and trimmed.
  ///
  /// Cropping is skipped in the browser, where the plugin has no native screen
  /// to show; the picked image is used as it is.
  static Future<String?> _cropPage(String sourcePath) async {
    if (kIsWeb) return sourcePath;

    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Straighten the page',
          toolbarColor: NestColor.pen,
          toolbarWidgetColor: Colors.white,
          backgroundColor: NestColor.ink,
          activeControlsWidgetColor: NestColor.pen,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Straighten the page',
          aspectRatioLockEnabled: false,
        ),
      ],
    );
    return cropped?.path;
  }

  static String _extension(String path, String fallback) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return fallback;
    return path.substring(dot + 1).toLowerCase();
  }

  /// Attachments need a file system, which the browser build does not have.
  static bool _supported(BuildContext context) {
    if (AttachmentStore.isSupported) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photos and PDFs need the phone app. Run it on a device or emulator.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
}

/// Asks whether a page should come from the camera or the gallery.
Future<ImageSource?> askImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: NestColor.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: NestColor.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add a page',
              style: Theme.of(sheetContext).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _SourceTile(
              icon: Icons.photo_camera_rounded,
              title: 'Take a photo',
              subtitle: 'Point at the page and shoot',
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            _SourceTile(
              icon: Icons.photo_library_rounded,
              title: 'Choose from gallery',
              subtitle: 'A photo you already took',
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(NestRadius.tile),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NestColor.paper,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: NestColor.pen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: NestColor.inkFaint),
          ],
        ),
      ),
    );
  }
}
