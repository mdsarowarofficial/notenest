import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/attachment_store.dart';
import '../../data/note_repository.dart';
import '../../models/attachment.dart';
import '../../models/course_file.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/note_row.dart';
import '../classroom/class_files.dart' show formatSize, iconForFile;
import '../notes/note_detail.dart';
import '../notes/note_editor.dart';
import '../subjects/subject_form.dart';
import '../tasks/tasks_page.dart';
import '../viewer/pdf_viewer.dart';

/// One course in one place: its notes, its tasks and its files.
///
/// Reached from a course card. Going back returns to the course overview, so
/// there is no second "active course" to keep in step.
class CoursePage extends StatefulWidget {
  const CoursePage({super.key, required this.subjectId, this.onSeeNotes});

  final int subjectId;

  /// Switches the shell to the Notes tab filtered to this course.
  final ValueChanged<String>? onSeeNotes;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  final _repo = NoteRepository.instance;
  bool _uploading = false;

  Subject? get _course => _repo.allSubjects().cast<Subject?>().firstWhere(
        (s) => s?.id == widget.subjectId,
        orElse: () => null,
      );

  Future<void> _addFile() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Add to this course',
        type: FileType.custom,
        allowedExtensions: courseFileExtensions,
      );
      for (final f in picked) {
        final length = await f.length();
        if (length != null && length > maxCourseFileBytes) {
          throw '${f.name} is larger than 25 MB.';
        }
        final added = await _repo.addCourseFile(
          subjectId: widget.subjectId,
          name: f.name,
          bytes: await f.readAsBytes(),
        );
        messenger.showSnackBar(SnackBar(
          content: Text(added.driveId != null
              ? '${added.fileName} saved to your Google Drive.'
              : '${added.fileName} is on this phone. It will go to Google '
                  'Drive when Drive is connected.'),
        ));
      }
    } on String catch (message) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file could not be added.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(CourseFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (file.isPdf) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerPage(
              attachment: Attachment(
                noteId: 0,
                type: AttachmentType.pdf,
                fileName: file.fileName,
                storedName: file.storedName,
                sizeBytes: file.sizeBytes,
                createdAt: file.createdAt,
              ),
            ),
          ),
        );
      } else {
        // Word, PowerPoint and the rest open in whichever app the phone has
        // for them; the share sheet is the way to reach it.
        final path = await AttachmentStore.fullPath(file.storedName);
        if (!await File(path).exists()) {
          messenger.showSnackBar(
            const SnackBar(content: Text('That file is missing.')),
          );
          return;
        }
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            fileNameOverrides: [file.fileName],
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file could not be opened.')),
      );
    }
  }

  Future<void> _removeFile(CourseFile file) async {
    final ok = await _confirm(
      'Remove this file?',
      file.driveId != null
          ? '"${file.fileName}" will be deleted from this phone and from '
              'your Google Drive.'
          : '"${file.fileName}" will be deleted from this phone.',
      'Remove',
    );
    if (ok) await _repo.removeCourseFile(file);
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _archive(Subject course) async {
    final ok = await _confirm(
      'Archive ${course.code}?',
      'It is hidden from your course lists. Its notes, tasks and files are '
          'kept, and you can restore it from All courses.',
      'Archive',
    );
    if (!ok) return;
    await _repo.archiveSubject(course.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final course = _course;
        if (course == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This course no longer exists.')),
          );
        }
        final t = Theme.of(context).textTheme;
        final notes = _repo.notesForSubject(course.id);
        final tasks = _repo
            .tasks()
            .where((x) => x.subjectId == course.id && !x.isDone)
            .toList();

        return Scaffold(
          backgroundColor: NestColor.paper,
          appBar: AppBar(
            title: Text(course.code.toUpperCase()),
            actions: [
              IconButton(
                tooltip: 'Edit course',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showSubjectForm(context, existing: course),
              ),
              if (!course.archived)
                IconButton(
                  tooltip: 'Archive course',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () => _archive(course),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Text(course.name, style: t.headlineSmall),
              if (course.archived)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Archived', style: t.bodySmall),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              NoteEditorPage(initialSubjectId: course.id),
                        ),
                      ),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text('Note'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          showTaskForm(context, subjectId: course.id),
                      icon: const Icon(Icons.add_task_rounded, size: 18),
                      label: const Text('Task'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _addFile,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(_uploading ? 'Adding…' : 'File'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text('Notes (${notes.length})',
                        style: t.titleMedium),
                  ),
                  if (widget.onSeeNotes != null && notes.length > 4)
                    TextButton(
                      onPressed: () {
                        widget.onSeeNotes!(course.code);
                        Navigator.pop(context);
                      },
                      child: const Text('See all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                Text('No notes in this course yet.', style: t.bodySmall)
              else
                for (final n in notes.take(4)) ...[
                  NoteRow(
                    note: n,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NoteDetailPage(noteId: n.id!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 14),
              Text('To do (${tasks.length})', style: t.titleMedium),
              const SizedBox(height: 8),
              if (tasks.isEmpty)
                Text('Nothing to do for this course.', style: t.bodySmall)
              else
                for (final task in tasks) TaskTile(task: task),
              const SizedBox(height: 14),
              Text('Files', style: t.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<CourseFile>>(
                // The repository notifies on every add and remove, which
                // rebuilds this and re-reads the list.
                future: _repo.courseFilesFor(course.id!),
                builder: (context, snap) {
                  final files = snap.data ?? const <CourseFile>[];
                  if (files.isEmpty) {
                    return Text(
                      AttachmentStore.isSupported
                          ? 'Add slides, handouts or past papers (PDF, Word, '
                              'PowerPoint, Excel, text, images up to 25 MB).'
                          : 'Files need the phone app.',
                      style: t.bodySmall,
                    );
                  }
                  return Column(
                    children: [
                      for (final f in files)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          color: NestColor.card,
                          child: ListTile(
                            leading: Icon(iconForFile(f.fileName)),
                            title: Text(
                              f.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(formatSize(f.sizeBytes)),
                            onTap: () => _open(f),
                            trailing: IconButton(
                              tooltip: 'Remove file',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _removeFile(f),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
