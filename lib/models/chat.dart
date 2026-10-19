/// Conversations and the messages in them.
///
/// No Firebase import, like the rest of the models. What is here is the shape
/// of a thread, the arithmetic of a read receipt, and — the part worth reading
/// twice — how a conversation's address is worked out.
library;

/// What kind of conversation this is.
///
/// Both kinds live in the same collection and use the same message code. The
/// difference is only in who is allowed in: a group thread asks the group, a
/// direct thread carries its two members itself.
enum ChatKind { direct, group }

extension ChatKindData on ChatKind {
  String get key => this == ChatKind.group ? 'group' : 'direct';

  /// An unknown kind is treated as direct, which is the one that cannot borrow
  /// anybody else's membership.
  static ChatKind fromKey(String? key) =>
      key == 'group' ? ChatKind.group : ChatKind.direct;
}

/// What a message carries.
enum MessageKind { text, note, image, voice, system }

extension MessageKindData on MessageKind {
  String get key => name;

  static MessageKind fromKey(String? key) {
    switch (key) {
      case 'note':
        return MessageKind.note;
      case 'image':
        return MessageKind.image;
      case 'voice':
        return MessageKind.voice;
      case 'system':
        return MessageKind.system;
      default:
        // Anything a newer version sends arrives as plain text rather than as
        // nothing. A message from the future should still show its words.
        return MessageKind.text;
    }
  }
}

// ------------------------------------------------------------- addresses

/// The address of the conversation between two people.
///
/// Built from the two uids, sorted, so it does not matter who opens it first:
/// both ends compute the same string and land in the same thread. That removes
/// a whole class of problem — there is no "start a conversation" step to get
/// wrong, and no way for two people to end up messaging each other in two
/// separate threads that each only one of them can see.
///
/// The sort is also what makes the rule checkable: the server can rebuild this
/// id from the two member uids and refuse anything that does not match, so a
/// thread cannot be created at an address that has nothing to do with the
/// people in it.
String directChatId(String a, String b) {
  final pair = [a, b]..sort();
  return 'dm_${pair[0]}_${pair[1]}';
}

/// The address of a group's conversation. Derived, so a group always has
/// exactly one chat and it never has to be created separately.
String groupChatId(String groupId) => 'grp_$groupId';

/// True when an id is a well-formed direct address for exactly these two.
bool isDirectChatId(String id, String a, String b) => id == directChatId(a, b);

/// The other person in a direct conversation, read off its address, or '' when
/// [chatId] is not a direct address that includes [me].
///
/// Firebase uids are letters and digits, so the underscore that joins them
/// cannot appear inside one.
String directChatOther(String chatId, String? me) {
  if (me == null || !chatId.startsWith('dm_')) return '';
  final parts = chatId.substring(3).split('_');
  if (parts.length != 2) return '';
  if (parts[0] == me) return parts[1];
  if (parts[1] == me) return parts[0];
  return '';
}

/// One `chats/{chatId}` document.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.kind,
    this.groupId = '',
    this.title = '',
    this.memberUids = const [],
    this.lastText = '',
    this.lastFromUid = '',
    this.lastFromName = '',
    this.lastAt,
    this.readAt = const {},
    this.typingAt = const {},
  });

  final String id;
  final ChatKind kind;

  /// Set for a group thread. The group, not this document, decides who is in
  /// it — see the security rules.
  final String groupId;

  /// Shown in the list. For a direct thread this is left empty and the other
  /// person's name is used instead, because a title written at creation time
  /// would be whatever their name was that day.
  final String title;

  /// Only meaningful for a direct thread.
  final List<String> memberUids;

  final String lastText;
  final String lastFromUid;
  final String lastFromName;
  final DateTime? lastAt;

  /// uid → when they last read this thread.
  final Map<String, DateTime> readAt;

  /// uid → when they were last seen typing.
  final Map<String, DateTime> typingAt;

  bool get isGroup => kind == ChatKind.group;

  /// The other person in a direct thread.
  String otherMember(String me) =>
      memberUids.firstWhere((u) => u != me, orElse: () => '');

  /// Whether there is something here this person has not seen.
  ///
  /// Their own message never counts as unread — they wrote it. Without that
  /// check every thread you spoke in last would sit there with a dot on it.
  bool isUnreadFor(String? me) {
    if (me == null) return false;
    final last = lastAt;
    if (last == null) return false;
    if (lastFromUid == me) return false;
    final seen = readAt[me];
    return seen == null || seen.isBefore(last);
  }

  /// Everyone except [me] who has been typing within [window].
  ///
  /// A typing flag is never cleared by the person who set it — a phone that
  /// loses signal mid-word would leave "typing…" on everyone else's screen for
  /// good. So it expires by age instead, which needs nothing from the writer.
  List<String> typingNow(
    String? me, {
    Duration window = const Duration(seconds: 6),
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return typingAt.entries
        .where((e) => e.key != me)
        .where((e) => at.difference(e.value) < window)
        .map((e) => e.key)
        .toList();
  }

  Map<String, Object?> toMap() => {
        'kind': kind.key,
        'groupId': groupId,
        'title': title.trim(),
        'memberUids': memberUids,
        'lastText': lastText,
        'lastFromUid': lastFromUid,
        'lastFromName': lastFromName,
        if (lastAt != null) 'lastAt': lastAt!.millisecondsSinceEpoch,
      };

  factory ChatThread.fromMap(String id, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    Map<String, DateTime> stamps(String key) {
      final v = m[key];
      if (v is! Map) return const {};
      final out = <String, DateTime>{};
      v.forEach((k, value) {
        if (k is String && value is int) {
          out[k] = DateTime.fromMillisecondsSinceEpoch(value);
        }
      });
      return out;
    }

    final raw = m['memberUids'];

    return ChatThread(
      id: id,
      kind: ChatKindData.fromKey(text('kind')),
      groupId: text('groupId'),
      title: text('title'),
      memberUids: raw is List
          ? raw.whereType<String>().where((s) => s.isNotEmpty).toList()
          : const [],
      lastText: text('lastText'),
      lastFromUid: text('lastFromUid'),
      lastFromName: text('lastFromName'),
      lastAt: at('lastAt'),
      readAt: stamps('readAt'),
      typingAt: stamps('typingAt'),
    );
  }
}

/// One `chats/{chatId}/messages/{messageId}` document.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromUid,
    required this.fromName,
    this.kind = MessageKind.text,
    this.text = '',
    this.title = '',
    this.subjectCode = '',
    this.fileCount = 0,
    this.blobId = '',
    this.thumb = '',
    this.durationMs = 0,
    this.createdAt,
  });

  final String id;
  final String fromUid;
  final String fromName;
  final MessageKind kind;

  /// The words, for a text message, or the line written with a note.
  final String text;

  /// For a note post: what it is, without unpacking the payload.
  final String title;
  final String subjectCode;
  final int fileCount;

  /// Where the heavy part lives, in the thread's `blobs` subcollection.
  ///
  /// Kept out of the message on purpose. A note's payload can run to several
  /// hundred kilobytes, and if it sat in the message then scrolling back
  /// through a term's conversation would download every note anybody had ever
  /// posted — for a person who may want none of them. This way the list stays
  /// light and the payload is fetched by whoever actually asks for it.
  final String blobId;

  /// A small inline preview for an image message, so the bubble can draw
  /// something without fetching the blob.
  final String thumb;

  final int durationMs;
  final DateTime? createdAt;

  bool get isNote => kind == MessageKind.note;
  bool get hasBlob => blobId.isNotEmpty;

  String get fromLabel =>
      fromName.trim().isEmpty ? 'Someone' : fromName.trim();

  /// The one line shown in the conversation list.
  String get preview {
    switch (kind) {
      case MessageKind.text:
        return text.trim();
      case MessageKind.note:
        return '📄 ${title.trim().isEmpty ? 'A note' : title.trim()}';
      case MessageKind.image:
        return '🖼 Photo';
      case MessageKind.voice:
        return '🎤 Voice message';
      case MessageKind.system:
        return text.trim();
    }
  }

  Map<String, Object?> toMap() => {
        'fromUid': fromUid,
        'fromName': fromName.trim(),
        'kind': kind.key,
        'text': text,
        'title': title.trim(),
        'subjectCode': subjectCode.trim(),
        'fileCount': fileCount,
        'blobId': blobId,
        'thumb': thumb,
        'durationMs': durationMs,
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(String id, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    int count(String key) {
      final v = m[key];
      return v is int && v > 0 ? v : 0;
    }

    final created = m['createdAt'];

    return ChatMessage(
      id: id,
      fromUid: text('fromUid'),
      fromName: text('fromName'),
      kind: MessageKindData.fromKey(text('kind')),
      text: text('text'),
      title: text('title'),
      subjectCode: text('subjectCode'),
      fileCount: count('fileCount'),
      blobId: text('blobId'),
      thumb: text('thumb'),
      durationMs: count('durationMs'),
      createdAt: created is int
          ? DateTime.fromMillisecondsSinceEpoch(created)
          : null,
    );
  }
}

// ----------------------------------------------------------------- limits

const maxMessageLength = 2000;

/// How long a typing flag counts for before it is ignored.
const typingWindow = Duration(seconds: 6);

/// How often the app is willing to write a typing flag.
///
/// Not a cosmetic number. Every one of these is a document write, and the free
/// Firestore allowance is twenty thousand a day. Writing on each keystroke
/// would spend a day's allowance on a few minutes of conversation — so it is
/// written at most this often, and expires on its own [typingWindow] later.
const typingWriteEvery = Duration(seconds: 3);

/// What is wrong with a message about to be sent, or null when nothing is.
String? messageProblem(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'Nothing to send.';
  if (text.length > maxMessageLength) {
    return 'That is longer than a message can be '
        '($maxMessageLength characters).';
  }
  return null;
}

/// A short clock for a message bubble: `09:41`.
String clockLabel(DateTime at) {
  final h = at.hour.toString().padLeft(2, '0');
  final m = at.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// The heading above a run of messages from one day: "Today", "Yesterday", or
/// a date such as "12 Oct" (with the year once it is not this year).
String dayHeading(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Compared in UTC so a daylight-saving change cannot make two calendar days
  // look like 23 hours apart.
  final days = DateTime.utc(today.year, today.month, today.day)
      .difference(DateTime.utc(at.year, at.month, at.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final base = '${at.day} ${months[at.month - 1]}';
  return at.year == today.year ? base : '$base ${at.year}';
}

/// True when two moments fall on different calendar days.
bool isNewDay(DateTime a, DateTime b) =>
    a.year != b.year || a.month != b.month || a.day != b.day;

/// A message time as people say it: `8:35 PM`.
String clockLabel12(DateTime at) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  return '$h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
}

/// When a conversation last had something in it, for the list.
///
/// Deliberately coarse. "11:42" is what you want for today and useless for
/// last month, and a date is the reverse.
String whenLabel(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final sameDay = at.year == today.year &&
      at.month == today.month &&
      at.day == today.day;
  if (sameDay) return clockLabel(at);

  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (at.year == yesterday.year &&
      at.month == yesterday.month &&
      at.day == yesterday.day) {
    return 'Yesterday';
  }

  if (at.year == today.year) {
    return '${at.day}/${at.month}';
  }
  return '${at.day}/${at.month}/${at.year}';
}

/// "Rafi is typing…", or "Rafi and 2 others are typing…".
///
/// Returns null when nobody is, so the caller shows the usual line instead of
/// an empty one that pushes the layout about.
String? typingLabel(List<String> names) {
  final people = names.where((n) => n.trim().isNotEmpty).toList();
  if (people.isEmpty) return null;
  if (people.length == 1) return '${people.first} is typing…';
  if (people.length == 2) {
    return '${people.first} and ${people[1]} are typing…';
  }
  return '${people.first} and ${people.length - 1} others are typing…';
}

// ------------------------------------------------------ message requests

/// Where a message request stands.
enum RequestState { pending, accepted, declined }

extension RequestStateData on RequestState {
  String get key => name;

  /// Anything unrecognised is treated as pending, the state that grants
  /// nothing: an unknown value can never open a conversation.
  static RequestState fromKey(String? key) {
    switch (key) {
      case 'accepted':
        return RequestState.accepted;
      case 'declined':
        return RequestState.declined;
      default:
        return RequestState.pending;
    }
  }
}

/// A request to start a one-to-one conversation. Its id is the conversation's
/// address, so there is at most one per pair of people.
class MessageRequest {
  const MessageRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    this.text = '',
    this.state = RequestState.pending,
    this.createdAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final String text;
  final RequestState state;
  final DateTime? createdAt;

  String otherUid(String me) => fromUid == me ? toUid : fromUid;

  Map<String, Object?> toMap() => {
        'fromUid': fromUid,
        'toUid': toUid,
        'text': text,
        'state': state.key,
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory MessageRequest.fromMap(String id, Map<String, Object?> m) {
    String s(String k) => m[k] is String ? m[k] as String : '';
    final at = m['createdAt'];
    return MessageRequest(
      id: id,
      fromUid: s('fromUid'),
      toUid: s('toUid'),
      text: s('text'),
      state: RequestStateData.fromKey(m['state'] as String?),
      createdAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}
