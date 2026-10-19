import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';
import '../subjects/subject_form.dart';
import 'course_page.dart';

/// Every course, searchable and filterable by semester, with archived ones
/// kept at the bottom where they can be restored.
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key, this.onSeeNotes});

  final ValueChanged<String>? onSeeNotes;

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final _repo = NoteRepository.instance;
  final _search = TextEditingController();
  int? _semester;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Subject s) {
    final q = _search.text.trim().toLowerCase();
    if (_semester != null && s.semesterNo != _semester) return false;
    return q.isEmpty ||
        s.name.toLowerCase().contains(q) ||
        s.code.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NestColor.paper,
      appBar: AppBar(title: const Text('All courses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSubjectForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add course'),
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final all = _repo.allSubjects();
          final semesters = {
            for (final s in all)
              if (s.semesterNo != null) s.semesterNo!,
          }.toList()
            ..sort();
          final active = all.where((s) => !s.archived && _matches(s)).toList();
          final archived = all.where((s) => s.archived && _matches(s)).toList();
          final t = Theme.of(context).textTheme;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search courses',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
              if (semesters.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _semester == null,
                          onSelected: (_) => setState(() => _semester = null),
                        ),
                      ),
                      for (final n in semesters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('Semester $n'),
                            selected: _semester == n,
                            onSelected: (_) => setState(() => _semester = n),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (active.isEmpty && archived.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    all.isEmpty
                        ? 'No courses yet. Tap "Add course".'
                        : 'No courses match.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium,
                  ),
                ),
              for (final s in active) _tile(context, s),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('ARCHIVED', style: nestEyebrow),
                const SizedBox(height: 8),
                for (final s in archived) _tile(context, s),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Subject s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: NestColor.card,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.color,
          child: Text(
            s.code.isEmpty ? '?' : s.code[0].toUpperCase(),
            style: const TextStyle(color: NestColor.ink),
          ),
        ),
        title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${s.code} · ${s.noteCount} ${s.noteCount == 1 ? 'note' : 'notes'}'
          '${s.semesterNo == null ? '' : ' · Semester ${s.semesterNo}'}',
        ),
        trailing: s.archived
            ? TextButton(
                onPressed: () => _repo.unarchiveSubject(s.id!),
                child: const Text('Restore'),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                CoursePage(subjectId: s.id!, onSeeNotes: widget.onSeeNotes),
          ),
        ),
      ),
    );
  }
}
