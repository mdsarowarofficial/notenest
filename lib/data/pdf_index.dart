import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'attachment_store.dart';

/// Makes the words inside attached PDFs searchable.
///
/// The text is pulled out once, on the phone, and kept in the attachment's own
/// row. Searching then looks at it the same way it looks at a note's body. It
/// never leaves the device and is not part of a backup (it can always be read
/// out again from the PDF).
///
/// A scanned PDF is a picture of text, not text, so nothing comes out of it.
/// Reading words off a picture needs OCR, which NoteNest does not do; those
/// rows are marked as done with an empty string so they are not tried again.
class PdfIndex {
  PdfIndex._();

  /// Pages read per file, and characters kept. Enough to find anything in a
  /// lecture handout; a 600-page textbook is indexed from its first chapters
  /// rather than holding up the phone for a minute.
  static const maxPages = 80;
  static const maxChars = 400000;

  static bool _busy = false;

  /// Reads one stored PDF and saves its text into attachment [id].
  static Future<void> indexOne(Database db, int id, String storedName) async {
    if (!AttachmentStore.isSupported) return;
    try {
      final bytes = await AttachmentStore.readBytes(storedName);
      final text = bytes == null ? '' : await compute(extractPdfText, bytes);
      await db.update(
        'attachments',
        {'extracted_text': text},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Could not index a PDF: $e');
    }
  }

  /// Indexes every PDF that has not been read yet, one at a time. Safe to call
  /// more than once; a second call while one is running does nothing.
  static Future<void> indexPending(Database db) async {
    if (_busy || !AttachmentStore.isSupported) return;
    _busy = true;
    try {
      final rows = await db.query(
        'attachments',
        columns: ['id', 'stored_name'],
        where: "type = 'pdf' AND extracted_text IS NULL",
      );
      for (final r in rows) {
        await indexOne(db, r['id'] as int, r['stored_name'] as String);
        // A breath between files so the app stays smooth while it works.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _busy = false;
    }
  }
}

/// The text of a PDF, or an empty string if it has none (a scan) or cannot be
/// read. Top-level so it can run in a background isolate.
String extractPdfText(Uint8List bytes) {
  try {
    final document = sf.PdfDocument(inputBytes: bytes);
    try {
      final last = document.pages.count < PdfIndex.maxPages
          ? document.pages.count - 1
          : PdfIndex.maxPages - 1;
      if (last < 0) return '';
      var text = sf.PdfTextExtractor(document)
          .extractText(startPageIndex: 0, endPageIndex: last);
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.length > PdfIndex.maxChars
          ? text.substring(0, PdfIndex.maxChars)
          : text;
    } finally {
      document.dispose();
    }
  } catch (_) {
    return '';
  }
}

/// A short stretch of [text] around the first of [terms] found in it, for a
/// search result, or null if none of them is there.
String? pdfSnippet(String text, List<String> terms) {
  final lower = text.toLowerCase();
  for (final term in terms) {
    final at = lower.indexOf(term);
    if (at < 0) continue;
    final from = (at - 40).clamp(0, text.length);
    final to = (at + term.length + 70).clamp(0, text.length);
    return '${from > 0 ? '… ' : ''}${text.substring(from, to).trim()}'
        '${to < text.length ? ' …' : ''}';
  }
  return null;
}
