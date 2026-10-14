/// The account as it exists in the cloud, and the rules around it.
///
/// Deliberately free of any Firebase import. Firestore hands back plain maps,
/// so the shape of a profile, the wording of an error and the rules for a
/// valid email can all be written and tested as ordinary Dart — and the parts
/// that genuinely need a network stay in `cloud_service.dart`.
library;

/// What the account is for. Chosen when connecting, and it decides what the
/// app offers later: a teacher sets assignments, a student submits them.
enum CloudRole { student, teacher }

extension CloudRoleData on CloudRole {
  String get key => name;

  String get label {
    switch (this) {
      case CloudRole.student:
        return 'Student';
      case CloudRole.teacher:
        return 'Teacher';
    }
  }

  String get blurb {
    switch (this) {
      case CloudRole.student:
        return 'Share notes with classmates, join a class, hand work in.';
      case CloudRole.teacher:
        return 'Set assignments with a deadline and see what comes back.';
    }
  }

  static CloudRole fromKey(String? key) =>
      key == 'teacher' ? CloudRole.teacher : CloudRole.student;
}

/// One `users/{uid}` document.
class CloudProfile {
  const CloudProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.role = CloudRole.student,
    this.institution = '',
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String name;

  /// Always stored lowercased — see [normaliseEmail].
  final String email;

  final CloudRole role;
  final String institution;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isTeacher => role == CloudRole.teacher;

  /// Initials for an avatar, falling back to the email when there is no name.
  ///
  /// Only the part before the `@`: taking the whole address turns
  /// `sarowar.hossain@x.com` into "SC", the S of the name and the C of
  /// "com", which is not initials of anything.
  String get initials {
    final source =
        name.trim().isNotEmpty ? name.trim() : email.split('@').first;
    final parts = source.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  CloudProfile copyWith({
    String? name,
    CloudRole? role,
    String? institution,
    DateTime? updatedAt,
  }) =>
      CloudProfile(
        uid: uid,
        name: name ?? this.name,
        email: email,
        role: role ?? this.role,
        institution: institution ?? this.institution,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'uid': uid,
        'name': name.trim(),
        // The lowercase copy is what every lookup searches on. Firestore has
        // no case-insensitive query, so the only way to find a classmate who
        // typed their address with capitals is to have stored it folded.
        'email': normaliseEmail(email),
        'role': role.key,
        'institution': institution.trim(),
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updatedAt': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  /// Never throws. A profile written by a newer version of the app, or half
  /// written when a phone lost signal, should still produce something the
  /// screens can show.
  factory CloudProfile.fromMap(String uid, Map<String, Object?> m) {
    DateTime? at(String key) {
      final v = m[key];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    return CloudProfile(
      uid: uid,
      name: text('name'),
      email: normaliseEmail(text('email')),
      // Through `text`, not a cast. `m['role'] as String?` throws when the
      // value is a number, which is exactly the half-written document this
      // factory promises to survive.
      role: CloudRoleData.fromKey(text('role')),
      institution: text('institution'),
      createdAt: at('createdAt'),
      updatedAt: at('updatedAt'),
    );
  }
}

/// Folds an address to the form everything else compares against.
///
/// Only case and surrounding space. Deliberately *not* the clever
/// normalisation some services do — stripping dots, cutting everything after a
/// plus sign — because those rules belong to particular providers and
/// applying them everywhere would quietly merge two people who really do have
/// different addresses.
String normaliseEmail(String raw) => raw.trim().toLowerCase();

/// Whether an address is worth sending to Firebase at all.
///
/// Rejecting the obviously wrong here means the common typo gets an instant,
/// plain answer instead of a round trip and a error code.
bool looksLikeEmail(String raw) {
  final email = normaliseEmail(raw);
  if (email.isEmpty || email.length > 254) return false;
  if (email.contains(' ')) return false;
  return RegExp(r'^[^@]+@[^@.]+(\.[^@.]+)+$').hasMatch(email);
}

/// The shortest password Firebase will accept.
const minPasswordLength = 6;

/// What is wrong with a password, or null when nothing is.
String? passwordProblem(String password) {
  if (password.isEmpty) return 'Type a password.';
  if (password.length < minPasswordLength) {
    return 'At least $minPasswordLength characters.';
  }
  return null;
}

/// Turns a Firebase error code into something a student can act on.
///
/// Firebase returns codes like `weak-password`, and its own English messages
/// are written for developers. These are written for the person holding the
/// phone, and each one says what to *do*.
String describeAuthError(String? code) {
  switch (code) {
    case 'email-already-in-use':
      return 'There is already a cloud account on that email. '
          'Use Sign in instead.';
    case 'invalid-email':
      return 'That address does not look right. Check for a typo.';
    case 'weak-password':
      return 'That password is too short. Use at least '
          '$minPasswordLength characters.';
    case 'user-not-found':
      return 'No cloud account on that email yet. Use Create instead.';
    case 'wrong-password':
    case 'invalid-credential':
      // Firebase now returns the vaguer `invalid-credential` for both a wrong
      // password and an unknown account, so the message cannot promise which.
      return 'That email and password do not match an account.';
    case 'user-disabled':
      return 'That account has been disabled.';
    case 'too-many-requests':
      return 'Too many tries. Wait a minute and try again.';
    case 'network-request-failed':
      return 'No connection to Firebase. Check your internet and try again.';
    case 'operation-not-allowed':
      // Almost always the one Console switch nobody remembers.
      return 'Email and password sign-in is switched off in the Firebase '
          'console. Turn it on under Authentication → Sign-in method.';
    default:
      return 'That did not work. Try again in a moment.';
  }
}

/// What went wrong talking to Firestore, in the same spirit.
String describeStoreError(String? code) {
  switch (code) {
    case 'permission-denied':
      return 'Firestore refused that. The security rules may not be published '
          'yet, or you are signed out of the cloud.';
    case 'unavailable':
      return 'Firestore could not be reached. You are probably offline.';
    case 'not-found':
      return 'That is not there any more.';
    case 'failed-precondition':
      return 'Firestore needs an index for that query. The console error log '
          'has a link that creates it.';
    default:
      return 'The cloud did not answer. Try again in a moment.';
  }
}
