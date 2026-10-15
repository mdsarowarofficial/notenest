import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/attachment_store.dart';
import '../../data/classroom_service.dart';
import '../../data/drive_service.dart';
import '../../data/note_repository.dart';
import '../../models/attachment.dart';
import '../../models/classwork.dart';
import '../../models/exam.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';

/// Files in a class: picking them, showing them, opening them, keeping them.

/// The largest single file a class post accepts. Drive takes far more, but the
/// whole file is held in memory on the way up, and a budget phone with a
/// 200 MB lecture recording in RAM is a phone that closes the app.
const maxClassFileBytes = 50 * 1024 * 1024;

/// Lets somebody pick files to attach. Returns an empty list if they backed
/// out, and throws a message-ready string for a file that is too large.
Future<List<PendingFile>> pickClassFiles() async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Attach files',
  );
  final out = <PendingFile>[];
  for (final f in picked) {
    final length = await f.length();
    if (length != null && length > maxClassFileBytes) {
      throw '${f.name} is larger than 50 MB. Share a smaller file, or put it '
          'in Drive and paste the link in the text.';
    }
    out.add(PendingFile(name: f.name, bytes: await f.readAsBytes()));
  }
  return out;
}

String formatSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData iconForFile(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
  if (n.endsWith('.ppt') || n.endsWith('.pptx')) return Icons.slideshow_rounded;
  if (n.endsWith('.doc') || n.endsWith('.docx') || n.endsWith('.txt')) {
    return Icons.description_rounded;
  }
  if (n.endsWith('.xls') || n.endsWith('.xlsx')) {
    return Icons.table_chart_rounded;
  }
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg')) {
    return Icons.image_rounded;
  }
  if (n.endsWith('.mp3') || n.endsWith('.m4a')) return Icons.audiotrack_rounded;
  if (n.endsWith('.mp4')) return Icons.movie_rounded;
  return Icons.insert_drive_file_rounded;
}

/// A file waiting to be uploaded, with a way to drop it.
class PendingFileChip extends StatelessWidget {
  const PendingFileChip(
      {super.key, required this.file, required this.onRemove});

  final PendingFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(iconForFile(file.name), size: 18, color: NestColor.pen),
      label: Text(
        '${file.name} · ${formatSize(file.bytes.length)}',
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onRemove,
    );
  }
}

/// A file already in a class, as a row that opens it.
class ClassFileTile extends StatelessWidget {
  const ClassFileTile({
    super.key,
    required this.file,
    this.saveTitle,
    this.saveTopic,
    this.onRemove,
  });

  final ClassFile file;

  /// When set, the row offers "Save to my notes" with this as the note title.
  final String? saveTitle;
  final String? saveTopic;

  /// When set, the row shows a remove button instead of the menu.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.chip),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: Icon(iconForFile(file.name), color: NestColor.pen),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: file.size > 0 ? Text(formatSize(file.size)) : null,
        onTap: () => openClassFile(context, file),
        trailing: onRemove != null
            ? IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onRemove,
              )
            : PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'drive') _openInDrive(context, file);
                  if (v == 'save') {
                    saveClassFileToNotes(
                      context,
                      file,
                      title: saveTitle ?? file.name,
                      topic: saveTopic,
                    );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'drive',
                    child: Text('Open in Google Drive'),
                  ),
                  if (saveTitle != null &&
                      (file.isPdf || file.isImage) &&
                      AttachmentStore.isSupported)
                    const PopupMenuItem(
                      value: 'save',
                      child: Text('Save to my notes (works offline)'),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> _openInDrive(BuildContext context, ClassFile file) async {
  final ok = await launchUrl(
    Uri.parse(DriveService.viewLink(file.driveId)),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open a browser for that file.')),
    );
  }
}

Future<Uint8List> _download(BuildContext context, ClassFile file) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text('Opening ${file.name}…'),
      duration: const Duration(seconds: 20),
    ),
  );
  try {
    return await DriveService.downloadShared(file.driveId);
  } finally {
    messenger.hideCurrentSnackBar();
  }
}

/// PDFs and pictures open inside the app; anything else goes to Drive's own
/// viewer, which already knows how to show slides and Word files.
Future<void> openClassFile(BuildContext context, ClassFile file) async {
  if (!file.isPdf && !file.isImage) {
    await _openInDrive(context, file);
    return;
  }
  try {
    final bytes = await _download(context, file);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BytesViewer(file: file, bytes: bytes),
      ),
    );
  } on DriveException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _BytesViewer extends StatelessWidget {
  const _BytesViewer({required this.file, required this.bytes});

  final ClassFile file;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open in Google Drive',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => _openInDrive(context, file),
          ),
        ],
      ),
      body: file.isPdf
          ? SfPdfViewer.memory(bytes)
          : InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
    );
  }
}

/// Copies a class file into the student's own notebook, under a subject they
/// choose, so it is there with no connection — the night before the exam, on
/// a bus, wherever the Wi-Fi is not.
///
/// This is the step Google Classroom leaves out: its files live in Classroom
/// and nowhere else, and studying from them means being online.
Future<void> saveClassFileToNotes(
  BuildContext context,
  ClassFile file, {
  required String title,
  String? topic,
}) async {
  final repo = NoteRepository.instance;
  final subject = await _pickSubject(context, repo.subjects());
  if (subject == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await _download(context, file);
    final ext = file.isPdf
        ? 'pdf'
        : (file.name.contains('.') ? file.name.split('.').last : 'jpg');
    final stored = await AttachmentStore.saveBytes(bytes, ext);
    final note = await repo.createNote(
      title: title,
      subjectId: subject.id == -1 ? null : subject.id,
      topic: topic,
    );
    await repo.addAttachment(
      note: note,
      type: file.isPdf ? AttachmentType.pdf : AttachmentType.image,
      fileName: file.name,
      storedName: stored,
      sizeBytes: bytes.length,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Saved to your notes as "$title".')),
    );
  } on DriveException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<Subject?> _pickSubject(BuildContext context, List<Subject> subjects) {
  return showModalBottomSheet<Subject>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 14),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('SAVE UNDER WHICH SUBJECT?', style: nestEyebrow),
            ),
            for (final s in subjects)
              ListTile(
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: s.color,
                ),
                title: Text(s.name),
                subtitle: Text(s.code),
                onTap: () => Navigator.pop(sheetContext, s),
              ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('No subject'),
              onTap: () => Navigator.pop(
                sheetContext,
                // A stand-in meaning "none", since null already means the
                // sheet was dismissed.
                Subject(
                  id: -1,
                  userId: 0,
                  name: '',
                  code: '',
                  colorIndex: 0,
                  createdAt: DateTime.now(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Puts an assignment's deadline in the student's own Exam countdown, where
/// every other date they care about already is.
Future<void> addDeadlineToExams(
  BuildContext context,
  ClassPost post, {
  required String className,
}) async {
  final due = post.dueAt;
  if (due == null) return;
  final repo = NoteRepository.instance;
  final already = repo.exams().any(
        (e) =>
            e.kind == ExamKind.assignment &&
            e.title == post.title &&
            e.date.year == due.year &&
            e.date.month == due.month &&
            e.date.day == due.day,
      );
  final messenger = ScaffoldMessenger.of(context);
  if (already) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Already in your Exam countdown.')),
    );
    return;
  }
  await repo.addExam(
    title: post.title,
    date: due,
    kind: ExamKind.assignment,
    note: className,
    remindDays: 1,
  );
  messenger.showSnackBar(
    const SnackBar(content: Text('Added to your Exam countdown.')),
  );
}
