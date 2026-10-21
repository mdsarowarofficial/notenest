/// One note packed into a single file so it can be handed to another student.
///
/// NoteNest has no server, so sharing is done the way students already share
/// everything else: a file sent through WhatsApp, Messenger, Bluetooth or
/// email. The whole note travels in one file — text, tags, which subject it
/// belongs to, and the photos or PDFs attached to it — so nothing arrives
/// half-complete.
///
/// Two rules shape the format:
///
/// **No database ids travel.** The sender's `subject_id` 4 is somebody else's
/// subject 4, or nobody's. The subject is carried by name and code instead and
/// matched up on the other side.
///
/// **Everything arriving is untrusted.** The file came off another student's
/// phone and may have been edited, truncated, or built by something that is
/// not NoteNest at all. [decode] therefore checks every field and refuses the
/// file rather than letting bad data into the database.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'attachment.dart';
import 'note.dart';
import 'note_query.dart';
import '../l10n/strings.dart';

/// Why a file could not be opened as a shared note.
enum BundleError { notJson, wrongFormat, tooNew, missingNote, tooBig, corrupt }

extension BundleErrorMessage on BundleError {
  String get message {
    switch (this) {
      case BundleError.notJson:
        return tr('This file is not a NoteNest note. Pick the .notenest file your '
            'classmate sent you.');
      case BundleError.wrongFormat:
        return tr('This file is not a NoteNest note, or it was damaged on the '
            'way. Ask for it to be sent again.');
      case BundleError.tooNew:
        return tr('This note was shared from a newer version of NoteNest. Update '
            'the app and try again.');
      case BundleError.missingNote:
        return tr('The file opened but holds no note.');
      case BundleError.tooBig:
        return tr('This note is larger than NoteNest will import. Ask for it to '
            'be shared without its attachments.');
      case BundleError.corrupt:
        return tr('Part of this file could not be read. Ask for it to be sent '
            'again.');
    }
  }
}

/// Thrown by [NoteBundle.decode] when a file cannot be trusted.
class BundleException implements Exception {
  const BundleException(this.error);

  final BundleError error;

  String get message => error.message;

  @override
  String toString() => 'BundleException(${error.name})';
}

/// One attachment travelling inside a bundle.
class BundleFile {
  const BundleFile({
    required this.type,
    required this.fileName,
    required this.bytes,
    this.durationMs,
  });

  final AttachmentType type;
  final String fileName;
  final Uint8List bytes;
  final int? durationMs;

  int get sizeBytes => bytes.length;

  /// The extension to store the file under, taken from the name but never
  /// trusted: anything that is not plain letters and digits is dropped, so a
  /// crafted name cannot steer where the file is written.
  String get safeExtension {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return _defaultExtension;
    final raw = fileName.substring(dot + 1).toLowerCase();
    final clean = raw.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty || clean.length > 5) return _defaultExtension;
    return clean;
  }

  String get _defaultExtension {
    switch (type) {
      case AttachmentType.image:
        return 'jpg';
      case AttachmentType.pdf:
        return 'pdf';
      case AttachmentType.audio:
        return 'm4a';
    }
  }
}

/// A note packed for sharing, or just unpacked from a file.
class NoteBundle {
  const NoteBundle({
    required this.title,
    required this.body,
    this.topic,
    this.tags = const [],
    this.type = NoteType.text,
    this.subjectName,
    this.subjectCode,
    required this.sharedBy,
    this.policy = SharePolicy.open,
    this.files = const [],
    required this.writtenAt,
  });

  final String title;
  final String body;
  final String? topic;
  final List<String> tags;
  final NoteType type;

  /// The sender's subject, by name and code rather than by id.
  final String? subjectName;
  final String? subjectCode;

  /// Who shared it. Taken from the sender's profile name.
  final String sharedBy;

  final SharePolicy policy;
  final List<BundleFile> files;

  /// When the note was originally written, so the receiver can see it is not
  /// new even though it has just arrived.
  final DateTime writtenAt;

  int get fileBytes =>
      files.fold<int>(0, (sum, f) => sum + f.sizeBytes);

  bool get hasFiles => files.isNotEmpty;

  // ------------------------------------------------------------------ limits

  /// The format name written into every file, so a file picked by mistake is
  /// recognised as not ours before anything else is read.
  static const formatName = 'notenest.note';

  /// Raised only when the format changes in a way older apps cannot read. A
  /// file from a newer version is refused with an explanation rather than
  /// being half-read.
  static const formatVersion = 1;

  static const maxFiles = 40;
  static const maxTotalBytes = 25 * 1024 * 1024;
  static const maxTitle = 200;
  static const maxBody = 200000;
  static const maxTopic = 100;
  static const maxName = 120;

  /// The file name offered to the share sheet.
  String get suggestedFileName {
    final base = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = base.isEmpty ? tr('note') : base;
    return '${stem.length > 40 ? stem.substring(0, 40) : stem}.notenest';
  }

  // ----------------------------------------------------------------- encode

  String encode() {
    final map = <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'sharedBy': sharedBy,
      'policy': policy.key,
      'note': {
        'title': title,
        'body': body,
        'topic': topic,
        'tags': tags,
        'type': type.key,
        'subjectName': subjectName,
        'subjectCode': subjectCode,
        'writtenAt': writtenAt.millisecondsSinceEpoch,
      },
      'attachments': [
        for (final f in files)
          {
            'type': f.type.key,
            'fileName': f.fileName,
            'durationMs': f.durationMs,
            'sizeBytes': f.sizeBytes,
            'data': base64Encode(f.bytes),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  // ----------------------------------------------------------------- decode

  /// Reads a file back into a bundle, refusing anything that does not add up.
  ///
  /// Every branch here exists because the file came from outside this app.
  static NoteBundle decode(String source) {
    final Object? parsed;
    try {
      parsed = jsonDecode(source);
    } catch (_) {
      throw const BundleException(BundleError.notJson);
    }
    if (parsed is! Map) throw const BundleException(BundleError.wrongFormat);

    if (parsed['format'] != formatName) {
      throw const BundleException(BundleError.wrongFormat);
    }

    final version = _asInt(parsed['version']);
    if (version == null || version < 1) {
      throw const BundleException(BundleError.wrongFormat);
    }
    if (version > formatVersion) {
      throw const BundleException(BundleError.tooNew);
    }

    final note = parsed['note'];
    if (note is! Map) throw const BundleException(BundleError.missingNote);

    final title = _text(note['title'], maxTitle);
    final body = _text(note['body'], maxBody);
    if (title.isEmpty && body.isEmpty) {
      throw const BundleException(BundleError.missingNote);
    }

    final rawTags = note['tags'];
    final tags = normalizeTags(
      rawTags is List
          ? rawTags.whereType<String>()
          : const <String>[],
    );

    final files = _decodeFiles(parsed['attachments']);

    final topic = _text(note['topic'], maxTopic);
    final subjectName = _text(note['subjectName'], maxName);
    final subjectCode = _text(note['subjectCode'], 24);
    final sharedBy = _text(parsed['sharedBy'], maxName);

    return NoteBundle(
      title: title.isEmpty ? tr('Shared note') : title,
      body: body,
      topic: topic.isEmpty ? null : topic,
      tags: tags,
      type: NoteTypeData.fromKey(_string(note['type'])),
      subjectName: subjectName.isEmpty ? null : subjectName,
      subjectCode: subjectCode.isEmpty ? null : subjectCode,
      sharedBy: sharedBy.isEmpty ? tr('A classmate') : sharedBy,
      policy: SharePolicyData.fromKey(_string(parsed['policy'])),
      files: files,
      writtenAt: _date(note['writtenAt']),
    );
  }

  static List<BundleFile> _decodeFiles(Object? raw) {
    if (raw is! List || raw.isEmpty) return const [];
    if (raw.length > maxFiles) throw const BundleException(BundleError.tooBig);

    final out = <BundleFile>[];
    var total = 0;

    for (final entry in raw) {
      if (entry is! Map) continue;
      final data = _string(entry['data']);
      if (data == null || data.isEmpty) continue;

      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } catch (_) {
        throw const BundleException(BundleError.corrupt);
      }

      total += bytes.length;
      if (total > maxTotalBytes) {
        throw const BundleException(BundleError.tooBig);
      }

      out.add(BundleFile(
        type: AttachmentTypeData.fromKey(_string(entry['type'])),
        // Only the name part is kept. A name carrying directories — the
        // "../../" trick — must never reach the file system, and the stored
        // name is generated locally anyway.
        fileName: _fileName(entry['fileName']),
        bytes: bytes,
        durationMs: _asInt(entry['durationMs']),
      ));
    }
    return out;
  }

  static String _fileName(Object? raw) {
    var name = _text(raw, 80);
    name = name.split(RegExp(r'[/\\]')).last;
    name = name.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    // A name of only dots would be meaningless and is what a traversal
    // attempt tends to leave behind once the separators are gone.
    if (name.isEmpty || RegExp(r'^\.+$').hasMatch(name)) return 'attachment';
    return name;
  }

  static String _text(Object? raw, int limit) {
    if (raw is! String) return '';
    final t = raw.trim();
    return t.length > limit ? t.substring(0, limit) : t;
  }

  static String? _string(Object? raw) => raw is String ? raw : null;

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  static DateTime _date(Object? raw) {
    final ms = _asInt(raw);
    if (ms == null || ms <= 0) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// A size in a form a student reads at a glance, for the share screen.
String readableBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
