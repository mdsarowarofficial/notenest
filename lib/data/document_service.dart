import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart' as pdflib;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/doc_text.dart';
import '../l10n/strings.dart';

/// Why a conversion could not be done, in terms a student can act on.
enum DocumentError {
  cancelled,
  unknownType,
  notDocx,
  notPdf,
  emptyDocument,
  noTextInPdf,
  tooBig,
  failed,
}

class DocumentException implements Exception {
  const DocumentException(this.error);

  final DocumentError error;

  /// Written as a sentence rather than a code, because this string goes
  /// straight onto the screen.
  String get message {
    switch (error) {
      case DocumentError.cancelled:
        return tr('Nothing was picked.');
      case DocumentError.unknownType:
        return tr('That is not a PDF or a Word file. Pick a .pdf or a .docx.');
      case DocumentError.notDocx:
        return tr('That file is not a Word document NoteNest can read. A .doc '
            'saved by an old version of Word is a different format — open it '
            'in Word and save it again as .docx.');
      case DocumentError.notPdf:
        return tr('That PDF could not be opened. It may be damaged, or locked '
            'with a password.');
      case DocumentError.emptyDocument:
        return tr('There was nothing in that document to convert.');
      case DocumentError.noTextInPdf:
        return tr('That PDF has no text in it — it is probably scanned pages, '
            'which are pictures as far as a computer is concerned. Reading '
            'the words off a picture needs OCR, which NoteNest does not do.');
      case DocumentError.tooBig:
        return tr('That file is too large to convert on a phone.');
      case DocumentError.failed:
        return tr('The conversion did not finish. Try a different file.');
    }
  }

  @override
  String toString() => 'DocumentException(${error.name}): $message';
}

/// What came back from the picker, already identified.
enum PickedKind { pdf, docx }

class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.bytes,
    required this.kind,
  });

  final String name;
  final Uint8List bytes;
  final PickedKind kind;

  /// The name without its extension, used to name whatever comes out.
  String get stem {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}

/// Reading and writing documents: PDF in, Word out, and back again.
///
/// Nothing here touches `dart:io`. Files arrive as bytes from the picker and
/// leave as bytes through the share sheet, which is what keeps all of this
/// working in the browser build as well as on the phone.
class DocumentService {
  DocumentService._();

  /// 20 MB. Everything here holds the whole document in memory at once, and a
  /// student's phone should not be asked to hold more than that.
  static const maxBytes = 20 * 1024 * 1024;

  // -------------------------------------------------------------- picking

  static Future<PickedDocument> pickDocument() async {
    // Filtered by extension rather than FileType.custom alone, because some
    // Android file managers report a .docx with no MIME type at all and a
    // type filter then hides it.
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
      dialogTitle: tr('Pick a PDF or a Word file'),
    );
    if (picked == null) throw const DocumentException(DocumentError.cancelled);

    final length = await picked.length();
    if (length != null && length > maxBytes) {
      throw const DocumentException(DocumentError.tooBig);
    }

    final ext = (picked.extension ?? _extensionOf(picked.name)).toLowerCase();
    final kind = switch (ext) {
      'pdf' => PickedKind.pdf,
      'docx' => PickedKind.docx,
      _ => null,
    };
    if (kind == null) {
      throw const DocumentException(DocumentError.unknownType);
    }

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      throw const DocumentException(DocumentError.failed);
    }
    if (bytes.length > maxBytes) {
      throw const DocumentException(DocumentError.tooBig);
    }

    return PickedDocument(name: picked.name, bytes: bytes, kind: kind);
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1 ? '' : name.substring(dot + 1);
  }

  // ----------------------------------------------------------- pdf → blocks

  /// Pulls the text out of a PDF and guesses its structure.
  ///
  /// A PDF stores glyphs at positions, not paragraphs, so what comes back is
  /// text and nothing else. [blocksFromPlainText] then makes conservative
  /// guesses about which lines were headings.
  static List<DocBlock> blocksFromPdf(Uint8List bytes) {
    final sf.PdfDocument document;
    try {
      document = sf.PdfDocument(inputBytes: bytes);
    } catch (_) {
      throw const DocumentException(DocumentError.notPdf);
    }

    final String text;
    try {
      text = sf.PdfTextExtractor(document).extractText();
    } catch (_) {
      throw const DocumentException(DocumentError.notPdf);
    } finally {
      document.dispose();
    }

    if (text.trim().isEmpty) {
      // Almost always a scan. Saying so is more useful than "empty".
      throw const DocumentException(DocumentError.noTextInPdf);
    }

    final blocks = blocksFromPlainText(text);
    if (blocks.isEmpty) {
      throw const DocumentException(DocumentError.emptyDocument);
    }
    return blocks;
  }

  // ---------------------------------------------------------- docx → blocks

  static List<DocBlock> blocksFromDocx(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      // A .docx is a zip. If it will not unzip, it is not one — most often an
      // old binary .doc that was simply renamed.
      throw const DocumentException(DocumentError.notDocx);
    }

    final entry = archive.find('word/document.xml');
    if (entry == null) {
      throw const DocumentException(DocumentError.notDocx);
    }

    final data = entry.readBytes();
    if (data == null || data.isEmpty) {
      throw const DocumentException(DocumentError.notDocx);
    }

    final List<DocBlock> blocks;
    try {
      blocks = blocksFromWordXml(utf8.decode(data, allowMalformed: true));
    } catch (_) {
      throw const DocumentException(DocumentError.notDocx);
    }

    if (blocks.isEmpty) {
      throw const DocumentException(DocumentError.emptyDocument);
    }
    return blocks;
  }

  // ---------------------------------------------------------- blocks → docx

  /// Builds the smallest package Word will open: the content types, one
  /// relationship, and the document itself.
  ///
  /// No `styles.xml`, which is why [buildWordDocumentXml] writes the
  /// formatting onto each run directly.
  static Uint8List buildDocx(List<DocBlock> blocks) {
    final archive = Archive()
      ..add(_textEntry('[Content_Types].xml', contentTypesXml))
      ..add(_textEntry('_rels/.rels', rootRelsXml))
      ..add(_textEntry('word/document.xml', buildWordDocumentXml(blocks)));

    return ZipEncoder().encodeBytes(archive);
  }

  /// UTF-8 explicitly. A cover page or a note may well be in Bengali, and a
  /// zip entry written in any other encoding would arrive as mojibake.
  static ArchiveFile _textEntry(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile.bytes(name, bytes);
  }

  // ----------------------------------------------------------- images → pdf

  /// Assembles rendered pages into a PDF, one image per A4 page.
  ///
  /// The pages arrive already drawn, because Flutter's own text engine is what
  /// shapes them. See `page_renderer.dart` for why that matters.
  static Future<Uint8List> pdfFromPageImages(List<Uint8List> pages) async {
    if (pages.isEmpty) {
      throw const DocumentException(DocumentError.emptyDocument);
    }

    final document = pw.Document();
    // Margins zeroed: each image is already a whole page, margins included.
    final format = pdflib.PdfPageFormat.a4.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );

    for (final png in pages) {
      final image = pw.MemoryImage(png);
      document.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }

    return document.save();
  }

  // -------------------------------------------------------------- sharing

  static Future<bool> sharePdf(Uint8List bytes, String fileName) =>
      _shareBytes(bytes, fileName, 'application/pdf');

  static Future<bool> shareDocx(Uint8List bytes, String fileName) => _shareBytes(
        bytes,
        fileName,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

  static Future<bool> _shareBytes(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType)],
        // XFile.fromData's own `name` is ignored on most platforms; this is
        // the one that names the file the student ends up with.
        fileNameOverrides: [fileName],
      ),
    );
    return result.status == ShareResultStatus.success;
  }
}
