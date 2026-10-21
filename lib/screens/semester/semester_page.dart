import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/semester.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/nest_mark_tile.dart';
import '../notes/note_detail.dart';
import 'degree_sheet.dart';
import '../../l10n/strings.dart';

/// The degree, term by term: which courses each semester had, and what is
/// filed under them.
///
/// This is the screen the app did not have. A semester used to be one piece of
/// text in settings — change it and last term's courses became indistinguishable
/// from this term's, because nothing recorded which term a course belonged to.
/// A student at the end of four years had one undifferentiated pile.
///
/// Now a course carries its semester, and a note already carries its course, so
/// the whole record falls out: semester → course → notes.
class SemesterPage extends StatelessWidget {
  const SemesterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Semesters'))),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final plan = repo.semesterPlan;
          final semesters = repo.semestersWithCourses;
          final loose = repo.subjectsWithoutSemester;

          if (!plan.isDated && semesters.isEmpty && loose.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(22),
              child: NestEmptyState(
                icon: Icons.school_rounded,
                title: tr('Tell the app about your degree'),
                message: tr('When it started and how your university divides the '
                    'year. After that it works out which semester you are in '
                    'by itself, and every course you add is filed under the '
                    'term you took it in.'),
                actionLabel: tr('Set up my degree'),
                onAction: () => showDegreeSheet(context),
              ),
            );
          }

          final current = repo.settledSemester ?? repo.currentSemester;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              _DegreeCard(plan: plan, current: current),
              if (loose.isNotEmpty) ...[
                const SizedBox(height: 12),
                _LooseCourses(courses: loose, into: current),
              ],
              const SizedBox(height: 22),
              for (final number in semesters) ...[
                _SemesterBlock(
                  number: number,
                  isCurrent: number == current,
                  courses: repo.subjectsInSemester(number),
                ),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The degree itself, and where today falls in it.
class _DegreeCard extends StatelessWidget {
  const _DegreeCard({required this.plan, required this.current});

  final SemesterPlan plan;
  final int? current;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final computed = plan.semesterOn(DateTime.now());
    final overridden = plan.manualSemester != null &&
        computed != null &&
        plan.manualSemester != computed;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: NestColor.pen,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.glow(NestColor.pen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.university?.isNotEmpty == true
                      ? plan.university!
                      : tr('Your degree'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: NestFont.display,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => showDegreeSheet(context),
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.white),
                tooltip: tr('Edit degree dates'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                current == null ? '—' : num_(current!),
                style: TextStyle(
                  fontFamily: NestFont.display,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 0.95,
                  letterSpacing: ls(-1.4),
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  current == null
                      ? tr('no semester set')
                      : trp('of {0}\nsemesters', [plan.count]),
                  style: TextStyle(
                    fontFamily: NestFont.body,
                    fontSize: 13,
                    height: 1.35,
                    color: NestColor.penPale,
                  ),
                ),
              ),
            ],
          ),
          if (plan.isDated) ...[
            const SizedBox(height: 14),
            Text(
              _span(plan),
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 12,
                color: NestColor.penPale,
              ),
            ),
          ],
          if (overridden) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: NestColor.o(Colors.white, 0.16),
                borderRadius: BorderRadius.circular(NestRadius.tile),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      trp('You set this yourself. By the dates it would be semester {0}.', [computed]),
                      style: const TextStyle(
                        fontFamily: NestFont.body,
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        NoteRepository.instance.followTheCalendar(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text(tr('Use the dates')),
                  ),
                ],
              ),
            ),
          ],
          if (!plan.isDated) ...[
            const SizedBox(height: 14),
            Text(
              tr('No start date yet, so the semester cannot move on its own.'),
              style: t.bodySmall?.copyWith(color: NestColor.penPale),
            ),
          ],
        ],
      ),
    );
  }

  static String _span(SemesterPlan plan) {
    String month(DateTime d) {
      const names = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return localDate('${names[d.month - 1]} ${d.year}');
    }

    final from = plan.start;
    final to = plan.end;
    if (from == null) return '';
    if (to == null) return trp('Started {0}', [month(from)]);
    return '${month(from)} — ${month(to)}';
  }
}

/// Courses that pre-date the degree dates and have no term yet.
class _LooseCourses extends StatelessWidget {
  const _LooseCourses({required this.courses, required this.into});

  final List<Subject> courses;
  final int? into;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: NestColor.tintWarm,
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trp('{0} course{1} with no semester', [courses.length, courses.length == 1 ? '' : 's']),
            style: t.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            tr('These were added before the app knew about your degree, so it '
            'does not know which term they belong to. It will not guess — '
            'put them where they go.'),
            style: t.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final c in courses)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: NestColor.o(c.color, 0.32),
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                  ),
                  child: Text(
                    c.code,
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NestColor.ink,
                    ),
                  ),
                ),
            ],
          ),
          if (into != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final moved =
                    await NoteRepository.instance.fileLooseCoursesInto(into!);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      trp('Filed {0} course{1} under semester {2}.', [moved, moved == 1 ? '' : 's', into]),
                    ),
                  ),
                );
              },
              child: Text(trp('File them all under semester {0}', [into])),
            ),
          ],
        ],
      ),
    );
  }
}

/// One semester, with the courses it held and what is under each.
class _SemesterBlock extends StatelessWidget {
  const _SemesterBlock({
    required this.number,
    required this.isCurrent,
    required this.courses,
  });

  final int number;
  final bool isCurrent;
  final List<Subject> courses;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final notes = courses.fold<int>(0, (sum, c) => sum + c.noteCount);

    return Container(
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The default expansion tile draws its own dividers, which fight the
        // card's rounded edge.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isCurrent,
          tilePadding: const EdgeInsets.fromLTRB(18, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          title: Row(
            children: [
              Text(shownSemester(semesterLabelFor(number)), style: t.titleMedium),
              if (isCurrent) ...[
                const SizedBox(width: 9),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: NestColor.tintPen,
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                  ),
                  child: Text(
                    tr('NOW'),
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: ls(0.6),
                      color: NestColor.penDeep,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              courses.isEmpty
                  ? tr('No courses yet')
                  : trp('{0} course{1} · {2} note{3}', [courses.length, courses.length == 1 ? '' : 's', notes, notes == 1 ? '' : 's']),
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 12,
                color: NestColor.inkMeta,
              ),
            ),
          ),
          children: [
            if (courses.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Add a subject and it will be filed here.'),
                  style: t.bodySmall,
                ),
              )
            else
              for (final course in courses) _CourseRow(course: course),
          ],
        ),
      ),
    );
  }
}

/// One course inside a semester, opening to the notes filed under it.
class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course});

  final Subject course;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    final notes = repo.notesForSubject(course.id);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 52, bottom: 8),
        leading: MarkTile.subject(course, size: 38),
        title: Text(
          course.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          trp('{0} · {1} note{2}{3}', [course.code, notes.length, notes.length == 1 ? '' : 's', course.archived ? tr(' · archived') : '']),
          style: TextStyle(
            fontFamily: NestFont.body,
            fontSize: 11.5,
            color: NestColor.inkMeta,
          ),
        ),
        children: [
          if (notes.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Nothing filed under this course.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final note in notes)
              InkWell(
                onTap: note.id == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteDetailPage(noteId: note.id!),
                          ),
                        ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        _icon(note.type),
                        size: 15,
                        color: NestColor.inkFaint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          note.title.trim().isEmpty
                              ? tr('Untitled note')
                              : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 13,
                            color: NestColor.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static IconData _icon(NoteType type) => switch (type) {
        NoteType.image => Icons.photo_rounded,
        NoteType.pdf => Icons.picture_as_pdf_rounded,
        NoteType.voice => Icons.mic_rounded,
        NoteType.text => Icons.notes_rounded,
      };
}
