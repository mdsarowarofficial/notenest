import 'dart:typed_data';
import '../l10n/strings.dart';

/// Stub used when the app is compiled for the browser.
class AttachmentStore {
  AttachmentStore._();

  static bool get isSupported => false;

  static String nameOf(String path) => path;

  static Future<String> newFilePath(String extension) =>
      throw UnsupportedError(tr('Attachments need the mobile app'));

  static Future<String> saveFile(String sourcePath, String extension) =>
      throw UnsupportedError(tr('Attachments need the mobile app'));

  static Future<String> saveBytes(Uint8List bytes, String extension) =>
      throw UnsupportedError(tr('Attachments need the mobile app'));

  static Future<String> fullPath(String storedName) =>
      throw UnsupportedError(tr('Attachments need the mobile app'));

  static Future<Uint8List?> readBytes(String storedName) async => null;

  static Future<int> sizeOf(String storedName) async => 0;

  static Future<void> delete(String storedName) async {}
}
