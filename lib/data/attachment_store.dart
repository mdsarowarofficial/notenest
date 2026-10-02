library;

/// Where attachment files live on disk.
///
/// The browser has no file system the app can write to, so the web build gets
/// a stub that reports attachments as unsupported rather than failing to
/// compile. Everything else uses the real implementation.
export 'attachment_store_web.dart'
    if (dart.library.io) 'attachment_store_io.dart';
