import 'dart:typed_data';

/// Stub used when the app is compiled for the browser.
class AttachmentStore {
  AttachmentStore._();

  static bool get isSupported => false;

  static Future<String> saveFile(String sourcePath, String extension) =>
      throw UnsupportedError('Attachments need the mobile app');

  static Future<String> saveBytes(Uint8List bytes, String extension) =>
      throw UnsupportedError('Attachments need the mobile app');

  static Future<String> fullPath(String storedName) =>
      throw UnsupportedError('Attachments need the mobile app');

  static Future<int> sizeOf(String storedName) async => 0;

  static Future<void> delete(String storedName) async {}
}
