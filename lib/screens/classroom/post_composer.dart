import 'package:flutter/material.dart';

import '../../data/classroom_service.dart';
import '../../data/cloud_service.dart';
import '../../data/drive_service.dart';
import '../../models/classwork.dart';
import '../../models/study_group.dart';
import '../../theme/nest_theme.dart';
import 'class_files.dart';
import '../../l10n/strings.dart';

/// Writes one post to a class: an announcement, a material or an assignment.
class PostComposerPage extends StatefulWidget {
  const PostComposerPage({
    super.key,
    required this.classGroup,
    this.initialKind = PostKind.assignment,
  });

  final StudyGroup classGroup;
  final PostKind initialKind;

  @override
  State<PostComposerPage> createState() => _PostComposerPageState();
}

class _PostComposerPageState extends State<PostComposerPage> {
  late PostKind _kind = widget.initialKind;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _topic = TextEditingController();
  final _points = TextEditingController(text: '100');

  DateTime? _due;
  final List<PendingFile> _files = [];

  String? _error;
  String? _progress;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _topic.dispose();
    _points.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    try {
      final picked = await pickClassFiles();
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _files.addAll(picked);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
      helpText: tr('Due date'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _due == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_due!),
      helpText: tr('Due time'),
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    setState(
        () => _due = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  Future<void> _post() async {
    final points =
        _kind == PostKind.assignment && _points.text.trim().isNotEmpty
            ? int.tryParse(_points.text.trim())
            : null;
    if (_kind == PostKind.assignment &&
        _points.text.trim().isNotEmpty &&
        points == null) {
      setState(() => _error = tr('Points must be a whole number.'));
      return;
    }
    final problem = postProblem(
      kind: _kind,
      title: _title.text,
      body: _body.text,
      points: points,
      dueAt: _due,
      fileCount: _files.length,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _error = null;
      _progress = _files.isEmpty ? tr('Posting…') : tr('Uploading to Google Drive…');
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uploaded = _files.isEmpty
          ? const <ClassFile>[]
          : await ClassroomService.instance.uploadFiles(
              _files,
              folder: [widget.classGroup.name],
            );
      if (mounted) setState(() => _progress = 'Posting…');
      await ClassroomService.instance.createPost(
        classGroup: widget.classGroup,
        kind: _kind,
        // An announcement has no title of its own; its first line stands in,
        // so lists and the chat reminder have something to call it.
        title: _kind == PostKind.announcement
            ? _firstLine(_body.text)
            : _title.text,
        body: _body.text,
        topic: _kind == PostKind.announcement ? '' : _topic.text,
        dueAt: _due,
        points: points,
        files: uploaded,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(trp('{0} posted.', [_kind.label]))),
      );
    } on DriveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on CloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  static String _firstLine(String body) {
    final line = body.trim().split('\n').first.trim();
    if (line.isEmpty) return tr('Announcement');
    return line.length > 80 ? '${line.substring(0, 80)}…' : line;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = _progress != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(trp('New {0}', [_kind.label.toLowerCase()])),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: busy ? null : _post,
              child: Text(tr('Post')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          SegmentedButton<PostKind>(
            segments: [
              ButtonSegment(
                value: PostKind.announcement,
                label: Text(tr('Announce')),
              ),
              ButtonSegment(
                value: PostKind.material,
                label: Text(tr('Material')),
              ),
              ButtonSegment(
                value: PostKind.assignment,
                label: Text(tr('Assignment')),
              ),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: busy
                ? null
                : (s) => setState(() {
                      _kind = s.first;
                      _error = null;
                    }),
          ),
          const SizedBox(height: 18),
          if (_kind != PostKind.announcement) ...[
            TextField(
              controller: _title,
              maxLength: maxPostTitle,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Title'),
                hintText: _kind == PostKind.assignment
                    ? 'Lab 3: Linked lists'
                    : 'Week 4 slides',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 10,
            maxLength: maxPostBody,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _kind == PostKind.announcement
                  ? tr('Share with your class')
                  : _kind == PostKind.assignment
                      ? tr('Instructions (optional)')
                      : tr('Description (optional)'),
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          if (_kind != PostKind.announcement) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _topic,
              maxLength: maxTopic,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Topic (optional)'),
                hintText: tr('Week 4, Midterm, Lab'),
                counterText: '',
              ),
            ),
          ],
          if (_kind == PostKind.assignment) ...[
            const SizedBox(height: 18),
            Text(tr('DEADLINE AND POINTS'), style: nestEyebrow),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _pickDue,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      _due == null ? tr('Set a due date') : formatDue(_due!),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_due != null)
                  IconButton(
                    tooltip: tr('No due date'),
                    onPressed: busy ? null : () => setState(() => _due = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _points,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('Points'),
                      hintText: tr('None'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('Leave points empty for ungraded work. Work handed in after the '
              'deadline is still accepted and marked late.'),
              style: t.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text(tr('FILES'), style: nestEyebrow)),
              TextButton.icon(
                onPressed: busy ? null : _attach,
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(tr('Attach')),
              ),
            ],
          ),
          if (_files.isEmpty)
            Text(
              trp('Slides, PDFs, Word files, pictures — up to {0}. They are saved in your Google Drive (NoteNest → Classes) and shared by link with this class.', [maxFilesPerPost]),
              style: t.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _files)
                  PendingFileChip(
                    file: f,
                    onRemove: () => setState(() => _files.remove(f)),
                  ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: NestColor.redPen)),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(_progress!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
