/// One line in the notification centre.
///
/// Notices are not stored: they are worked out from things that already exist
/// (a waiting request, an unanswered share, a task past its due time), so a
/// notice can never outlive the thing it points at. What is stored is only
/// when the person last looked, which decides what counts as new.
library;

enum NoticeKind { request, share, taskOverdue, taskToday, exam }

extension NoticeKindData on NoticeKind {
  /// The preference group a kind belongs to.
  String get group {
    switch (this) {
      case NoticeKind.request:
        return 'messages';
      case NoticeKind.share:
        return 'shares';
      case NoticeKind.taskOverdue:
      case NoticeKind.taskToday:
        return 'tasks';
      case NoticeKind.exam:
        return 'exams';
    }
  }
}

const noticeGroups = {
  'messages': 'Messages and message requests',
  'shares': 'Notes shared with me',
  'tasks': 'Task reminders',
  'exams': 'Exam and deadline reminders',
};

class AppNotice {
  const AppNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
  });

  /// Stable across rebuilds: kind plus the id of the thing it is about.
  final String id;
  final NoticeKind kind;
  final String title;
  final String body;

  /// When the underlying thing happened or falls due.
  final DateTime at;

  bool isUnread(DateTime? seenAt) => seenAt == null || at.isAfter(seenAt);
}

/// Newest first, with the kinds the person switched off removed.
List<AppNotice> visibleNotices(
  Iterable<AppNotice> all, {
  required Set<String> disabledGroups,
}) {
  final list = all.where((n) => !disabledGroups.contains(n.kind.group)).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  return list;
}

int unreadCount(Iterable<AppNotice> notices, DateTime? seenAt) =>
    notices.where((n) => n.isUnread(seenAt)).length;
