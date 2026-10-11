import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note_bundle.dart';

/// Getting a note out of this phone and into another one.
///
/// There is no server behind NoteNest, so a note is handed over the way
/// students already hand over everything else: as a file sent through whatever
/// app they are already using — WhatsApp, Messenger, email, Bluetooth. This
/// class deals only with the file and the operating system. What goes inside
/// the file is [NoteBundle]'s job, and writing an arriving note into the
/// notebook is the repository's.
///
/// Nothing here touches `dart:io`. The file is handed to the share sheet as
/// bytes and the plugin writes its own temporary copy, which keeps the whole
/// feature working in the browser build as well as on the phone.
class ShareService {
  ShareService._();

  static const fileExtension = 'notenest';

  /// Writes the bundle into the system share sheet.
  ///
  /// Returns false when the student backed out, so the caller can stay quiet
  /// rather than claim the note was sent.
  static Future<bool> shareBundle(
    NoteBundle bundle, {
    String? message,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(bundle.encode()));

    final result = await SharePlus.instance.share(
      ShareParams(
        text: message ?? _defaultMessage(bundle),
        files: [XFile.fromData(bytes, mimeType: 'application/json')],
        // The `name` on XFile.fromData is ignored on most platforms; this is
        // the one that actually names the file the classmate receives.
        fileNameOverrides: [bundle.suggestedFileName],
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Shares plain text. Used by note requests, which need no file.
  static Future<bool> shareText(String text) async {
    final result = await SharePlus.instance.share(ShareParams(text: text));
    return result.status == ShareResultStatus.success;
  }

  static String _defaultMessage(NoteBundle bundle) {
    final code = bundle.subjectCode;
    final where = code == null || code.isEmpty ? '' : ' ($code)';
    return '${bundle.title}$where — a note from NoteNest. '
        'Open NoteNest and use Shared → Import to add it to your notebook.';
  }

  /// Lets the student pick a received file and reads it as a note.
  ///
  /// Returns null when the picker was dismissed. Throws [BundleException] when
  /// a file was picked but cannot be trusted; the caller shows that message.
  static Future<NoteBundle?> pickBundle() async {
    // Deliberately not filtered to the .notenest extension. Several Android
    // file managers hand a file with an unrecognised type over fine but hide
    // it behind a custom-extension filter, which looks to the student like the
    // note never arrived. Letting any file be picked and deciding from the
    // contents is also the safer order: the extension was never a guarantee of
    // what is inside.
    final picked = await FilePicker.pickFile();
    if (picked == null) return null;

    // A note is text. Something far larger than the bundle limit is not one,
    // and refusing it here avoids reading a video into memory to find out.
    final length = await picked.length();
    if (length != null && length > NoteBundle.maxTotalBytes * 2) {
      throw const BundleException(BundleError.tooBig);
    }

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      throw const BundleException(BundleError.corrupt);
    }

    // allowMalformed, because a file that is not UTF-8 at all should fail as
    // "not a note" in the decoder rather than throwing something unreadable
    // out of the decoder for text.
    return NoteBundle.decode(utf8.decode(bytes, allowMalformed: true));
  }
}
