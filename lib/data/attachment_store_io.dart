import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked files into the application's own folder.
///
/// A picked image or PDF lives in a cache the system may clear at any time, so
/// every attachment is copied somewhere the app controls before its name is
/// written to the database.
class AttachmentStore {
  AttachmentStore._();

  static bool get isSupported => true;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _newName(String extension) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return 'a_$stamp$ext';
  }

  /// The name part of a path, used to turn the recorder's output path back
  /// into the bare name the database stores.
  static String nameOf(String path) => p.basename(path);

  /// A full path for a file that is about to be written, inside the attachment
  /// folder.
  ///
  /// The recorder writes its audio straight here, so a finished recording does
  /// not have to be copied in afterwards the way a picked image does.
  static Future<String> newFilePath(String extension) async {
    final dir = await _dir();
    return p.join(dir.path, _newName(extension));
  }

  /// Copies a file in and returns the name it was stored under.
  static Future<String> saveFile(String sourcePath, String extension) async {
    final dir = await _dir();
    final name = _newName(extension);
    await File(sourcePath).copy(p.join(dir.path, name));
    return name;
  }

  static Future<String> saveBytes(Uint8List bytes, String extension) async {
    final dir = await _dir();
    final name = _newName(extension);
    await File(p.join(dir.path, name)).writeAsBytes(bytes);
    return name;
  }

  static Future<String> fullPath(String storedName) async {
    final dir = await _dir();
    return p.join(dir.path, storedName);
  }

  /// Reads a stored file back, or null if it is no longer there.
  ///
  /// Needed when packing a note to share: the bytes have to travel inside the
  /// shared file, because the receiving phone has no access to this one.
  static Future<Uint8List?> readBytes(String storedName) async {
    final file = File(await fullPath(storedName));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<int> sizeOf(String storedName) async {
    final file = File(await fullPath(storedName));
    return await file.exists() ? await file.length() : 0;
  }

  static Future<void> delete(String storedName) async {
    final file = File(await fullPath(storedName));
    if (await file.exists()) await file.delete();
  }
}
