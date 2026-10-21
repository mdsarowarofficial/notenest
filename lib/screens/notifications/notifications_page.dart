import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../data/reminder_service.dart';
import '../../models/app_notice.dart';
import '../../models/chat.dart';
import '../../models/exam.dart';
import '../../models/note_share.dart';
import '../../theme/nest_theme.dart';
import '../chat/message_request.dart';
import '../exam/exam_page.dart';
import '../shared/shared_page.dart';
import '../shell/home_shell.dart';
import '../../l10n/strings.dart';

/// Everything that needs the person's attention, worked out from what exists
/// right now. Nothing here is a copy that could go stale.
List<AppNotice> collectNotices({
  required List<MessageRequest> requests,
  required List<NoteShare> shares,
}) {
  final repo = NoteRepository.instance;
  final cloud = CloudService.instance;
  final out = <AppNotice>[];

  for (final r in requests) {
    if (r.state != RequestState.pending || cloud.isBlocked(r.fromUid)) continue;
    out.add(AppNotice(
      id: 'req:${r.id}',
      kind: NoticeKind.request,
      title: tr('New message request'),
      body: r.text,
      at: r.createdAt ?? DateTime.now(),
    ));
  }
  for (final s in shares) {
    if (!s.isPending || cloud.isBlocked(s.fromUid)) continue;
    out.add(AppNotice(
      id: 'share:${s.id}',
      kind: NoticeKind.share,
      title: trp('{0} sent you a note', [s.fromLabel]),
      body: s.title,
      at: s.createdAt ?? DateTime.now(),
    ));
  }
  for (final t in repo.overdueTasks) {
    out.add(AppNotice(
      id: 'over:${t.id}',
      kind: NoticeKind.taskOverdue,
      title: tr('Overdue'),
      body: t.title,
      at: t.dueAt!,
    ));
  }
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  for (final t in repo.tasksDueToday) {
    out.add(AppNotice(
      id: 'today:${t.id}',
      kind: NoticeKind.taskToday,
      title: tr('Due today'),
      body: t.title,
      // Not the due time: a task due at 6 pm is stamped after "now", so it
      // would still count as new after Mark all read. It became news when the
      // day began, and that is what clears once it has been seen.
      at: startOfToday,
    ));
  }
  for (final e in repo.dueReminders()) {
    final lead = e.remindDays ?? 0;
    out.add(AppNotice(
      id: 'exam:${e.id}',
      kind: NoticeKind.exam,
      title: e.isToday
          ? trp('{0} is today', [e.title])
          : trp('{0} in {1} days', [e.title, e.daysAway]),
      body: e.kind.label,
      at: e.date.subtract(Duration(days: lead)),
    ));
  }
  return visibleNotices(out, disabledGroups: repo.noticeOff);
}

/// Feeds [builder] the current notices, re-running when the requests, the
/// shares, or the local data change.
class NoticeBuilder extends StatelessWidget {
  const NoticeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext, List<AppNotice>) builder;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final repo = NoteRepository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([repo, cloud]),
      builder: (context, _) => StreamBuilder<List<MessageRequest>>(
        stream: cloud.watchIncomingRequests(),
        builder: (context, reqSnap) => StreamBuilder<List<NoteShare>>(
          stream: cloud.watchIncomingShares(),
          builder: (context, shareSnap) => builder(
            context,
            collectNotices(
              requests: reqSnap.data ?? const [],
              shares: shareSnap.data ?? const [],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bell on the Today screen, with the unread count.
class NoticeBell extends StatelessWidget {
  const NoticeBell({super.key});

  @override
  Widget build(BuildContext context) {
    return NoticeBuilder(
      builder: (context, notices) {
        final unread =
            unreadCount(notices, NoteRepository.instance.noticeSeenAt);
        return IconButton(
          tooltip: unread > 0 ? trp('Notifications, {0} new', [unread]) : tr('Notifications'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsPage()),
          ),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(trp('{0}', [unread])),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  void _open(BuildContext context, AppNotice n) {
    // Tasks live in a tab of the home shell, so go there and keep the bar.
    if (n.kind == NoticeKind.taskOverdue || n.kind == NoticeKind.taskToday) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      HomeShell.openTodo();
      return;
    }
    final Widget page;
    switch (n.kind) {
      case NoticeKind.request:
        page = const MessageRequestsPage();
      case NoticeKind.share:
        page = Scaffold(
          backgroundColor: NestColor.paper,
          appBar: AppBar(title: Text(tr('Shared with me'))),
          body: const SharedPage(),
        );
      case NoticeKind.taskOverdue || NoticeKind.taskToday:
        return; // handled above
      case NoticeKind.exam:
        page = const ExamPage();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  IconData _icon(NoticeKind k) => switch (k) {
        NoticeKind.request => Icons.mark_email_unread_outlined,
        NoticeKind.share => Icons.description_outlined,
        NoticeKind.taskOverdue => Icons.error_outline_rounded,
        NoticeKind.taskToday => Icons.today_rounded,
        NoticeKind.exam => Icons.event_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    return Scaffold(
      backgroundColor: NestColor.paper,
      appBar: AppBar(
        title: Text(tr('Notifications')),
        actions: [
          IconButton(
            tooltip: tr('Notification settings'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: NestColor.card,
              // Seven rows do not fit the default half-height sheet.
              isScrollControlled: true,
              builder: (_) => const _NoticeSettings(),
            ),
          ),
          NoticeBuilder(
            builder: (context, notices) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: unreadCount(notices, repo.noticeSeenAt) == 0
                    ? null
                    : repo.markNoticesSeen,
                child: Text(tr('Mark all read')),
              ),
            ),
          ),
        ],
      ),
      body: NoticeBuilder(
        builder: (context, notices) {
          if (notices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr("You're all caught up.\nRequests, shared notes, tasks and "
                  'exam reminders show up here.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final t = Theme.of(context).textTheme;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: notices.length + 1,
            itemBuilder: (context, i) {
              if (i == notices.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    tr('These appear while NoteNest is open. With notifications '
                    'allowed, new messages and class posts also reach you '
                    'when it is closed.'),
                    style: t.bodySmall,
                  ),
                );
              }
              final n = notices[i];
              final unread = n.isUnread(repo.noticeSeenAt);
              // Unread is a white card with an indigo edge and a dot; read ones
              // sink back into the page, so the two are told apart at a glance.
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: unread ? NestColor.card : NestColor.o(NestColor.card, 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NestRadius.card),
                  side: unread
                      ? BorderSide(
                          color: NestColor.o(NestColor.pen, 0.45), width: 1.5)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: Badge(
                    isLabelVisible: unread,
                    backgroundColor: NestColor.pen,
                    smallSize: 9,
                    child: Icon(_icon(n.kind)),
                  ),
                  title: Text(
                    n.title,
                    style: t.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    n.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(dayHeading(n.at), style: t.bodySmall),
                  onTap: () => _open(context, n),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NoticeSettings extends StatelessWidget {
  const _NoticeSettings();

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Show notifications for'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final entry in noticeGroups.entries)
                SwitchListTile(
                  title: Text(entry.value),
                  value: !repo.noticeOff.contains(entry.key),
                  onChanged: (on) =>
                      repo.setNoticeGroup(entry.key, enabled: on),
                ),
              const Divider(),
              SwitchListTile(
                title: Text(tr('Remind me when the app is closed')),
                subtitle: Text(
                  tr('Task and exam alerts on this phone. Quiet from 10 pm to 7 am.'),
                ),
                value: repo.remindersOn,
                onChanged: (on) async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (on) {
                    final ok =
                        await ReminderService.instance.requestPermission();
                    if (!ok) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(tr('Notifications are blocked. Allow them '
                              'in the phone settings.')),
                        ),
                      );
                      return;
                    }
                  }
                  await repo.setReminders(on: on, idle: on ? null : false);
                },
              ),
              SwitchListTile(
                title: Text(tr("Nudge me if I haven't visited for 3 days")),
                value: repo.idleReminder && repo.remindersOn,
                onChanged: repo.remindersOn
                    ? (on) => repo.setReminders(idle: on)
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
