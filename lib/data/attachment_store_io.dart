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

  static Future<int> sizeOf(String storedName) async {
    final file = File(await fullPath(storedName));
    return await file.exists() ? await file.length() : 0;
  }

  static Future<void> delete(String storedName) async {
    final file = File(await fullPath(storedName));
    if (await file.exists()) await file.delete();
  }
}
