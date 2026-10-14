/// A note sent from one account to another, waiting to be accepted.
///
/// No Firebase import here either. What travels is the same `NoteBundle` JSON
/// the `.notenest` file format already uses — see [NoteShare.payload] — so a
/// note that arrives over the network is read back by exactly the code that
/// reads one off a file, validation and all.
library;

/// Where a share has got to.
enum ShareState { pending, accepted, declined }

extension ShareStateData on ShareState {
  String get key => name;

  String get label {
    switch (this) {
      case ShareState.pending:
        return 'Waiting';
      case ShareState.accepted:
        return 'Accepted';
      case ShareState.declined:
        return 'Declined';
    }
  }

  /// Anything unrecognised is treated as still waiting, which is the state
  /// that shows the person a choice. Guessing "accepted" for a value this
  /// version does not understand would silently swallow a note.
  static ShareState fromKey(String? key) {
    switch (key) {
      case 'accepted':
        return ShareState.accepted;
      case 'declined':
        return ShareState.declined;
      default:
        return ShareState.pending;
    }
  }
}

/// One `shares/{shareId}` document: one note, one recipient.
///
/// A note sent to a group of eight becomes eight of these, written in one
/// batch. That is more documents than keeping a single one with a list of
/// recipients, and it is worth it: accepting is personal. With one shared
/// document, every member's decision would have to be recorded inside a
/// document they all write to, and the rule allowing that is far harder to make
/// safe than `toUid == request.auth.uid`.
class NoteShare {
  const NoteShare({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.title,
    required this.payload,
    this.groupId = '',
    this.groupName = '',
    this.message = '',
    this.subjectCode = '',
    this.fileCount = 0,
    this.state = ShareState.pending,
    this.createdAt,
    this.respondedAt,
  });

  final String id;
  final String fromUid;

  /// The sender's display name, copied in at send time rather than looked up.
  ///
  /// A share should still say who sent it when the sender has since changed
  /// their name or deleted their account — and reading a profile per row would
  /// turn one inbox into forty reads.
  final String fromName;

  final String toUid;

  /// Shown in the inbox without unpacking the payload.
  final String title;

  /// The `NoteBundle.encode()` JSON. Opaque here on purpose: this class knows
  /// how to carry it and nothing about what is inside it.
  final String payload;

  /// Set when the note was sent to a whole group, for the "via Thesis group"
  /// line. Empty for a share sent to one person.
  final String groupId;
  final String groupName;

  final String message;
  final String subjectCode;
  final int fileCount;
  final ShareState state;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  bool get isPending => state == ShareState.pending;
  bool get viaGroup => groupId.isNotEmpty;

  String get fromLabel => fromName.trim().isEmpty ? 'Someone' : fromName.trim();

  /// A line under the title: who sent it, through what, with what attached.
  String get subtitle {
    final bits = <String>[fromLabel];
    if (viaGroup && groupName.trim().isNotEmpty) {
      bits.add('via ${groupName.trim()}');
    }
    if (fileCount > 0) {
      bits.add('$fileCount ${fileCount == 1 ? 'file' : 'files'}');
    }
    return bits.join(' · ');
  }

  Map<String, Object?> toMap() => {
        'fromUid': fromUid,
        'fromName': fromName.trim(),
        'toUid': toUid,
        'title': title.trim(),
        'payload': payload,
        'groupId': groupId,
        'groupName': groupName.trim(),
        'message': message.trim(),
        'subjectCode': subjectCode.trim(),
        'fileCount': fileCount,
        'state': state.key,
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        if (respondedAt != null)
          'respondedAt': respondedAt!.millisecondsSinceEpoch,
      };

  factory NoteShare.fromMap(String id, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    final files = m['fileCount'];

    return NoteShare(
      id: id,
      fromUid: text('fromUid'),
      fromName: text('fromName'),
      toUid: text('toUid'),
      title: text('title'),
      payload: text('payload'),
      groupId: text('groupId'),
      groupName: text('groupName'),
      message: text('message'),
      subjectCode: text('subjectCode'),
      fileCount: files is int && files > 0 ? files : 0,
      state: ShareStateData.fromKey(text('state')),
      createdAt: at('createdAt'),
      respondedAt: at('respondedAt'),
    );
  }
}

// ------------------------------------------------------------- size budget

/// Firestore's hard limit on one document, in bytes.
///
/// Not a number to design up to. Everything below leaves room under it.
const firestoreDocumentLimit = 1048576;

/// The most payload JSON one share may carry.
///
/// Well under [firestoreDocumentLimit], and the gap is deliberate. The payload
/// is not the only thing in the document — the title, the sender's name, the
/// message and the field names themselves all count — and Firestore measures
/// its own overhead in ways this app cannot see. A budget that only just fitted
/// in testing would start failing on a long note with a long title, which is
/// the worst kind of limit: one that holds until the day it matters.
const sharePayloadBudget = 700 * 1024;

/// base64 carries three bytes in four characters, so attaching a file to a
/// share costs a third more than the file itself.
const base64Overhead = 4 / 3;

/// Roughly how much payload a set of attachments will add.
///
/// Approximate by design, and the caller treats it as such: the real encoded
/// size is measured before sending. This is for the sentence shown *while*
/// choosing, where an answer that is right to the nearest few bytes is worth
/// nothing and an answer that arrives after a wait is worth less.
int estimatedPayloadBytes({
  required int textBytes,
  required int attachmentBytes,
}) =>
    textBytes + (attachmentBytes * base64Overhead).round();

/// Whether a payload of this size can be sent through the cloud.
bool sharePayloadFits(int bytes) => bytes <= sharePayloadBudget;

/// Human-readable size, for the line that explains why files were left behind.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

/// What to tell someone about the files on a note they are about to send.
///
/// Returns null when there is nothing worth saying — no files, or they fit.
///
/// The reason this exists at all: Firebase Storage, which is where attachments
/// would properly live, needs a billing account. Without one, a file can only
/// travel inside the document itself, and documents are capped at a megabyte.
/// So some notes can carry their files through the cloud and some cannot, and
/// the person deserves to know which *before* they press send rather than after
/// a failure they cannot interpret.
String? attachmentWarning({
  required int fileCount,
  required int textBytes,
  required int attachmentBytes,
}) {
  if (fileCount == 0) return null;
  final total = estimatedPayloadBytes(
    textBytes: textBytes,
    attachmentBytes: attachmentBytes,
  );
  if (sharePayloadFits(total)) return null;

  final files = '$fileCount ${fileCount == 1 ? 'file' : 'files'}';
  return 'The text will be sent, but $files '
      '(${formatBytes(attachmentBytes)}) will not fit. '
      'Send the note as a file instead to include them.';
}
