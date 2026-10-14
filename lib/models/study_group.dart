/// Study groups and class groups, and the codes people join them with.
///
/// Deliberately free of any Firebase import, like [CloudProfile]. Firestore
/// hands back plain maps, so the shape of a group, the rules for a join code
/// and the arithmetic of membership are all ordinary Dart that can be tested
/// without a network or an emulator.
library;

/// What a group is for.
///
/// Both are the same shape — a name, an owner, a list of members — because a
/// teacher's class *is* a study group with one member who sets the work. Giving
/// them one model means chat and assignments only ever have to understand one
/// thing, and a group can never be half a class.
enum GroupKind { study, classroom }

extension GroupKindData on GroupKind {
  String get key => this == GroupKind.classroom ? 'class' : 'study';

  String get label =>
      this == GroupKind.classroom ? 'Class' : 'Study group';

  String get blurb => this == GroupKind.classroom
      ? 'A teacher sets assignments here. Students hand work in.'
      : 'Classmates share notes and talk about them.';

  /// Unknown keys fall back to a study group, which is the one that can do
  /// less. A group written by a newer version of the app should not quietly
  /// gain the power to set assignments.
  static GroupKind fromKey(String? key) =>
      key == 'class' ? GroupKind.classroom : GroupKind.study;
}

/// One `groups/{groupId}` document.
class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerUid,
    this.ownerName = '',
    this.kind = GroupKind.study,
    this.subject = '',
    this.memberUids = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Always stored uppercase — see [normaliseJoinCode].
  final String joinCode;

  final String ownerUid;
  final String ownerName;
  final GroupKind kind;

  /// Free text: "CSE 112", "Thesis group". Not a link to a local subject,
  /// because the people in a group do not share a subject table.
  final String subject;

  final List<String> memberUids;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isClass => kind == GroupKind.classroom;

  int get memberCount => memberUids.length;

  bool isOwner(String? uid) => uid != null && uid == ownerUid;

  bool hasMember(String? uid) => uid != null && memberUids.contains(uid);

  /// The owner cannot leave, because a group with no owner is a group nobody
  /// can delete or set work in. Handing it over is a separate thing, and it is
  /// honest to say so rather than to let the group quietly strand itself.
  bool canLeave(String? uid) => hasMember(uid) && !isOwner(uid);

  String get memberLabel =>
      memberCount == 1 ? '1 member' : '$memberCount members';

  /// Initials for the group avatar: at most two words, so "Data Structures
  /// Lab" shows DL rather than DSL.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  StudyGroup copyWith({
    String? name,
    String? subject,
    List<String>? memberUids,
    DateTime? updatedAt,
  }) =>
      StudyGroup(
        id: id,
        name: name ?? this.name,
        joinCode: joinCode,
        ownerUid: ownerUid,
        ownerName: ownerName,
        kind: kind,
        subject: subject ?? this.subject,
        memberUids: memberUids ?? this.memberUids,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The member list with [uid] appended, or the list unchanged if they are
  /// already in it.
  ///
  /// Appended at the end on purpose. The security rule that lets somebody join
  /// is written as `memberUids == resource.data.memberUids.concat([uid])`,
  /// and `concat` appends. Inserting anywhere else — sorting the list, say —
  /// would make a legitimate join fail the rule, which is a bug that only
  /// shows up against the real server.
  List<String> withMember(String uid) =>
      memberUids.contains(uid) ? memberUids : [...memberUids, uid];

  List<String> withoutMember(String uid) =>
      memberUids.where((m) => m != uid).toList();

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'joinCode': normaliseJoinCode(joinCode),
        'ownerUid': ownerUid,
        'ownerName': ownerName.trim(),
        'kind': kind.key,
        'subject': subject.trim(),
        'memberUids': memberUids,
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updatedAt': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  /// Never throws, for the same reason [CloudProfile.fromMap] does not: these
  /// documents come from a server that any version of the app — or the console
  /// — can write to.
  factory StudyGroup.fromMap(String id, Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    final raw = m['memberUids'];
    final members = raw is List
        ? raw.whereType<String>().where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return StudyGroup(
      id: id,
      name: text('name'),
      joinCode: normaliseJoinCode(text('joinCode')),
      ownerUid: text('ownerUid'),
      ownerName: text('ownerName'),
      kind: GroupKindData.fromKey(text('kind')),
      subject: text('subject'),
      memberUids: members,
      createdAt: at('createdAt'),
      updatedAt: at('updatedAt'),
    );
  }
}

// ---------------------------------------------------------------- join codes

/// The alphabet a join code is drawn from.
///
/// Missing on purpose: `O` and `0`, `I` and `1`. A join code's whole job is to
/// be read off one screen and typed into another, often from across a room, and
/// those four are the pairs people get wrong. Dropping them costs a little
/// space and removes the most common reason a correct code is rejected.
const joinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const joinCodeLength = 6;

/// Folds a typed code to the form stored and compared against.
///
/// Uppercases, and throws away everything that is not in the alphabet — so
/// `k3m-9fp`, `K3M 9FP` and `k3m9fp` are all the same code. People write codes
/// down with spaces and dashes; refusing those would be pedantry, not security.
String normaliseJoinCode(String raw) {
  final out = StringBuffer();
  for (final ch in raw.toUpperCase().split('')) {
    if (joinCodeAlphabet.contains(ch)) out.write(ch);
  }
  return out.toString();
}

/// What is wrong with a typed join code, or null when nothing is.
String? joinCodeProblem(String raw) {
  final code = normaliseJoinCode(raw);
  if (code.isEmpty) return 'Type the group code.';
  if (code.length != joinCodeLength) {
    return 'A group code is $joinCodeLength characters.';
  }
  return null;
}

/// Groups a code into two threes for display: `K3M9FP` reads as `K3M 9FP`.
String prettyJoinCode(String raw) {
  final code = normaliseJoinCode(raw);
  if (code.length != joinCodeLength) return code;
  return '${code.substring(0, 3)} ${code.substring(3)}';
}

/// Builds a code from a source of randomness supplied by the caller.
///
/// The randomness is passed in rather than taken from `Random()` inside, so a
/// test can pin the output exactly. A code generator that cannot be tested is
/// one nobody checks for a stuck digit.
String buildJoinCode(int Function(int max) nextInt) {
  final out = StringBuffer();
  for (var i = 0; i < joinCodeLength; i++) {
    out.write(joinCodeAlphabet[nextInt(joinCodeAlphabet.length)]);
  }
  return out.toString();
}

const maxGroupName = 60;
const maxGroupSubject = 60;

/// What is wrong with a group name, or null when nothing is.
String? groupNameProblem(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Give the group a name.';
  if (name.length > maxGroupName) {
    return 'Keep the name under $maxGroupName characters.';
  }
  return null;
}
