import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../data/classroom_service.dart';
import '../../data/note_repository.dart';
import '../../data/profile_photo.dart';
import '../../models/exam.dart';
import '../../models/semester.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import '../../widgets/note_row.dart';
import '../classroom/classes_page.dart';
import '../convert/convert_page.dart';
import '../cover/cover_page.dart';
import '../notes/note_detail.dart';
import '../profile/profile_page.dart';
import '../subjects/subject_form.dart';
import '../tasks/tasks_page.dart';
import '../courses/course_page.dart';
import '../courses/courses_page.dart';

/// The landing screen.
///
/// Built around one number: how much is left to master before the next exam.
/// Everything else here is subordinate to it, because that is the question a
/// student opens a notes app to answer at eleven at night.
///
/// Cover page and Convert sit here as two cards rather than in the drawer.
/// They are the two things NoteNest does that a notes app does not, and they
/// spent the whole project behind a hamburger menu where nobody found them.
class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.onOpenNotes,
    required this.onCapture,
    required this.onOpenExams,
    this.onOpenClasses,
    this.onOpenTasks,
    this.onOpenCourse,
    this.avatarKey,
  });

  final VoidCallback onOpenNotes;
  final VoidCallback onCapture;
  final VoidCallback onOpenExams;
  final VoidCallback? onOpenClasses;

  /// Switches to the To-do tab, so "See all" keeps the navigation bar.
  final VoidCallback? onOpenTasks;

  /// Opens Notes filtered to one course (by code). The shell owns the active
  /// course, so the cards set the same value the drawer and chips do.
  final ValueChanged<String>? onOpenCourse;

  /// Lets the first-run tour point at the profile picture.
  final GlobalKey? avatarKey;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return ListenableBuilder(
      // The cloud too, because the corner photo can arrive from the cloud
      // profile on a phone that has none of its own yet.
      listenable: Listenable.merge([repo, CloudService.instance]),
      builder: (context, _) {
        if (repo.isTeacher) {
          return _TeacherToday(
            greeting: _Greeting(name: repo.userName, avatarKey: avatarKey),
            onPost: onCapture,
            onOpenClasses: onOpenClasses,
            onOpenTasks: onOpenTasks,
          );
        }

        final recent = repo.recentNotes(limit: 4);
        final reminders = repo.dueReminders();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
          children: [
            _Greeting(name: repo.userName, avatarKey: avatarKey),
            const SizedBox(height: 20),

            // A term has begun that the student has not acknowledged. Asked
            // rather than done: university dates slip by weeks, and being
            // moved into semester 5 while you are still sitting semester 4's
            // exams is worse than being asked.
            if (repo.semesterAwaitingAcceptance != null) ...[
              _SemesterStrip(number: repo.semesterAwaitingAcceptance!),
              const SizedBox(height: 12),
            ],

            for (final exam in reminders) ...[
              _ReminderStrip(exam: exam, onTap: onOpenExams),
              const SizedBox(height: 12),
            ],

            if (repo.hasSubjects && onOpenCourse != null) ...[
              _CourseCards(onOpen: onOpenCourse!),
              const SizedBox(height: 14),
            ],
            TasksCard(onSeeAll: onOpenTasks),
            const SizedBox(height: 14),

            if (!repo.hasSubjects)
              _StartCard(
                eyebrow: 'FIRST STEP',
                title: 'Add a subject',
                body: 'Subjects give every note a colour and a place to live. '
                    'You can add more later.',
                actionLabel: 'Add a subject',
                onAction: () => showSubjectForm(context),
              )
            else if (!repo.hasNotes) ...[
              _StartCard(
                eyebrow: 'NEXT STEP',
                title: 'Write your first note',
                body: 'Give it a title, pick the subject and topic, and start '
                    'writing. It saves as you type.',
                actionLabel: 'Write a note',
                onAction: onCapture,
              ),
              const SizedBox(height: 14),
              const _Tools(),
            ] else ...[
              _RevisionCard(
                total: repo.unrevisedCount,
                important: repo.importantUnrevisedCount,
                allNotes: repo.notes().length,
                days: repo.daysToNextExam,
                subject: repo.nextExamSubject,
                onOpen: onOpenNotes,
              ),
              const SizedBox(height: 14),
              const _Tools(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Keep going',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenNotes,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The short row, not the full card. Today is a list of things
              // to pick up again, and four full cards with body text and tags
              // fill the screen with reading instead of choices.
              for (final note in recent) ...[
                NoteRow(
                  note: note,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NoteDetailPage(noteId: note.id!),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
              ],
            ],
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------- header

/// The greeting for a moment: morning until noon, afternoon until 5 pm,
/// evening until 9 pm, and night after that.
String greetingFor(DateTime at) {
  final hour = at.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Good night';
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, this.avatarKey});

  final String name;
  final GlobalKey? avatarKey;

  /// First name only. "Good evening, Md. Sarowar Hossain" wraps onto two lines
  /// and reads like a letter from a bank.
  String get _first {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '';
    for (final p in parts) {
      // Skip honorifics and initials — "Md." is not what anybody is called.
      if (p.length > 2 && !p.endsWith('.')) return p;
    }
    return parts.first;
  }

  String get _timeOfDay {
    return greetingFor(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(todayLabel(), style: nestEyebrow),
              const SizedBox(height: 4),
              Text(
                _first.isEmpty ? _timeOfDay : '$_timeOfDay, $_first',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.headlineSmall,
              ),
            ],
          ),
        ),
        // The bell lives in the app bar, beside search, so it is one tap from
        // every tab and not only from this screen.
        Semantics(
          key: avatarKey,
          button: true,
          label: 'Your profile',
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
            child: InitialsTile(name: name, size: 46, photo: myPhoto()),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- the number

class _RevisionCard extends StatelessWidget {
  const _RevisionCard({
    required this.total,
    required this.important,
    required this.allNotes,
    required this.days,
    required this.subject,
    required this.onOpen,
  });

  final int total;
  final int important;
  final int allNotes;
  final int? days;
  final String? subject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final done = total == 0;
    final mastered = allNotes - total;
    // Guarded rather than assumed: an empty notebook would divide by zero, and
    // a count that drifted could push this past one and overflow the bar.
    final share = allNotes == 0 ? 0.0 : (mastered / allNotes).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NestRadius.card + 2),
        boxShadow: NestShadow.glow(done ? NestColor.mint : NestColor.pen),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: done ? NestColor.mint : NestColor.pen,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        done ? 'All caught up' : 'Needs revision',
                        style: TextStyle(
                          fontFamily: NestFont.body,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: NestColor.o(Colors.white, 0.78),
                        ),
                      ),
                    ),
                    if (days != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: NestColor.o(Colors.white, 0.18),
                          borderRadius: BorderRadius.circular(NestRadius.pill),
                        ),
                        child: Text(
                          countdownLabel(days!),
                          style: const TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      done ? '$allNotes' : '$total',
                      style: const TextStyle(
                        fontFamily: NestFont.display,
                        fontSize: 46,
                        height: 0.95,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.6,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          done
                              ? '${allNotes == 1 ? 'note' : 'notes'} '
                                  'mastered.\nNothing waiting.'
                              : subject == null
                                  ? '${total == 1 ? 'note' : 'notes'} not '
                                      'yet\nmastered'
                                  : '${total == 1 ? 'note' : 'notes'} left\n'
                                      'for $subject',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 13,
                            height: 1.3,
                            color: NestColor.o(Colors.white, 0.8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 8,
                    backgroundColor: NestColor.o(Colors.white, 0.22),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      done ? Colors.white : NestColor.highlight,
                    ),
                  ),
                ),
                if (important > 0 && !done) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: NestColor.highlight,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$important marked important',
                        style: TextStyle(
                          fontFamily: NestFont.body,
                          fontSize: 12,
                          color: NestColor.o(Colors.white, 0.82),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- tools

class _Tools extends StatelessWidget {
  const _Tools();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ToolCard(
            icon: Icons.description_outlined,
            tint: NestColor.tintPen,
            colour: NestColor.pen,
            title: 'Cover page',
            body: 'Assignment, lab report',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CoverPageScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToolCard(
            icon: Icons.swap_horiz_rounded,
            tint: NestColor.tintMint,
            colour: NestColor.mint,
            title: 'Convert',
            body: 'Word and PDF',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConvertPage()),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.tint,
    required this.colour,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color colour;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile + 2),
        boxShadow: NestShadow.resting,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: Icon(icon, size: 21, color: colour),
                ),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: NestFont.body,
                    fontSize: 11.5,
                    color: NestColor.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- reminders

/// A reminder the student asked for, on the screen they open first.
class _ReminderStrip extends StatelessWidget {
  const _ReminderStrip({required this.exam, required this.onTap});

  final Exam exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                // A warm mark rather than the 5px coloured stripe down the
                // left edge this card used to carry: the stripe is not in the
                // design, and a bare icon beside white is no colour at all.
                MarkTile.tool(
                  Icons.notifications_active_rounded,
                  tint: NestColor.tintWarm,
                  ink: NestColor.warmDeep,
                  size: 40,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        countdownLabel(exam.daysAway),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NestColor.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- empty state

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.lifted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: nestEyebrow.copyWith(color: NestColor.pen)),
          const SizedBox(height: 8),
          Text(title, style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(body, style: t.bodySmall),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Semester 5 has started" — the one moment the app volunteers to move the
/// student through their degree.
class _SemesterStrip extends StatelessWidget {
  const _SemesterStrip({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Row(
        children: [
          MarkTile.tool(
            Icons.school_rounded,
            tint: NestColor.tintMint,
            ink: NestColor.mintDeep,
            size: 40,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${semesterLabelFor(number)} has started',
                    style: t.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Your courses so far stay where they are.',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => NoteRepository.instance.enterSemester(number),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 38),
            ),
            child: const Text('Move'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ teacher

/// Today for a teacher: the classes, and the two things done most often.
///
/// No revision number and no exam countdown — those answer a student's
/// question. A teacher opens the app to post something or to see what came
/// back, so those are the first two things on the page.
class _TeacherToday extends StatelessWidget {
  const _TeacherToday({
    required this.greeting,
    required this.onPost,
    this.onOpenClasses,
    this.onOpenTasks,
  });

  final Widget greeting;
  final VoidCallback onPost;
  final VoidCallback? onOpenClasses;
  final VoidCallback? onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
      children: [
        greeting,
        const SizedBox(height: 20),
        TasksCard(onSeeAll: onOpenTasks),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.assignment_add,
                label: 'Post to a class',
                onTap: onPost,
                primary: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.add_rounded,
                label: 'New class',
                onTap: () => showCreateClassSheet(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Your classes', style: t.titleMedium)),
            if (onOpenClasses != null)
              TextButton(
                  onPressed: onOpenClasses, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 6),
        if (!cloud.isSignedIn)
          _StartCard(
            eyebrow: 'FIRST STEP',
            title: 'Connect a cloud account',
            body: 'Classes live where your students\' phones can see them, so '
                'they need an account. Your own notes work either way.',
            actionLabel: 'Open Classes',
            onAction: onOpenClasses ?? () {},
          )
        else
          StreamBuilder<List<StudyGroup>>(
            stream: ClassroomService.instance.watchClasses(),
            builder: (context, snap) {
              final mine = (snap.data ?? const <StudyGroup>[])
                  .where((c) => c.isOwner(cloud.uid))
                  .toList();
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (mine.isEmpty) {
                return _StartCard(
                  eyebrow: 'FIRST STEP',
                  title: 'Make your first class',
                  body: 'Give it a name, then share its six-letter code with '
                      'your students so they can join.',
                  actionLabel: 'New class',
                  onAction: () => showCreateClassSheet(context),
                );
              }
              return Column(
                children: [
                  for (final c in mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: NestColor.card,
                        borderRadius: BorderRadius.circular(NestRadius.tile),
                        elevation: 2,
                        shadowColor: NestColor.o(NestColor.ink, 0.3),
                        surfaceTintColor: Colors.transparent,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(NestRadius.tile),
                          ),
                          leading: MarkTile.tool(Icons.co_present_rounded),
                          title: Text(c.name, style: t.titleSmall),
                          subtitle: Text(
                            '${c.subject.isEmpty ? '' : '${c.subject} · '}'
                            '${c.memberCount - 1} '
                            '${c.memberCount - 1 == 1 ? 'student' : 'students'}'
                            ' · code ${prettyJoinCode(c.joinCode)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => openClass(context, c),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 14),
        const _Tools(),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 54)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NestRadius.chip),
        ),
      ),
    );
    return primary
        ? FilledButton.icon(
            style: style,
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
          )
        : OutlinedButton.icon(
            style: style,
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

// ------------------------------------------------------------ course cards

/// The student's courses for the active semester, one tap from their notes.
class _CourseCards extends StatelessWidget {
  const _CourseCards({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    final t = Theme.of(context).textTheme;
    final subjects = repo.subjects();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your courses', style: t.titleMedium)),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CoursesPage(onSeeNotes: onOpen),
                ),
              ),
              child: const Text('All courses'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          // Room for a two-line course name plus the count line, with the
          // text sizes people actually use.
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = subjects[i];
              final open = repo
                  .tasks()
                  .where((task) => !task.isDone && task.subjectId == s.id)
                  .length;
              return Semantics(
                button: true,
                label: '${s.code}, ${s.name}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CoursePage(subjectId: s.id!, onSeeNotes: onOpen),
                    ),
                  ),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NestColor.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NestColor.rule),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.code.toUpperCase(),
                            style: t.labelSmall
                                ?.copyWith(color: NestColor.ink),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall,
                        ),
                        const Spacer(),
                        Text(
                          '${s.noteCount} ${s.noteCount == 1 ? 'note' : 'notes'}'
                          '${open > 0 ? ' · $open to do' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
