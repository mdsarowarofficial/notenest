import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../data/share_service.dart';
import '../../models/note.dart';
import '../../models/note_bundle.dart';
import '../../theme/nest_theme.dart';

/// Hands one note over to a classmate. Requirement 9.1.
///
/// The student sees exactly what is about to leave the phone before it leaves
/// — the subject it will arrive under, whether the photos and PDFs are going
/// with it, and how big the file will be. A share sheet that sends a 20 MB
/// file without saying so is how people end up out of mobile data.
Future<void> showShareNoteSheet(BuildContext context, Note note) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ShareNoteSheet(note: note),
  );
}

class _ShareNoteSheet extends StatefulWidget {
  const _ShareNoteSheet({required this.note});

  final Note note;

  @override
  State<_ShareNoteSheet> createState() => _ShareNoteSheetState();
}

class _ShareNoteSheetState extends State<_ShareNoteSheet> {
  final _repo = NoteRepository.instance;

  bool _withFiles = true;
  SharePolicy _policy = SharePolicy.open;
  bool _working = false;
  String? _error;

  /// The packed note, kept so the size can be shown before sharing.
  NoteBundle? _preview;
  int _fileBytes = 0;
  int _fileCount = 0;

  @override
  void initState() {
    super.initState();
    _policy = widget.note.sharePolicy ?? SharePolicy.open;
    _measure();
  }

  /// Packs the note once with its files so the sheet can show what the
  /// classmate will actually receive.
  Future<void> _measure() async {
    final withFiles = await _repo.packForSharing(widget.note);
    if (!mounted) return;
    setState(() {
      _preview = withFiles;
      _fileBytes = withFiles.fileBytes;
      _fileCount = withFiles.files.length;
    });
  }

  Future<void> _send() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final bundle = await _repo.packForSharing(
        widget.note,
        includeFiles: _withFiles,
      );
      final sent = await ShareService.shareBundle(
        NoteBundle(
          title: bundle.title,
          body: bundle.body,
          topic: bundle.topic,
          tags: bundle.tags,
          type: bundle.type,
          subjectName: bundle.subjectName,
          subjectCode: bundle.subjectCode,
          sharedBy: bundle.sharedBy,
          policy: _policy,
          files: bundle.files,
          writtenAt: bundle.writtenAt,
        ),
      );
      if (!mounted) return;
      if (sent) Navigator.pop(context);
      setState(() => _working = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'The note could not be prepared for sharing. Try again, or '
            'share it without its files.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.note.subjectId == null
        ? null
        : _repo.subjectById(widget.note.subjectId!);
    // Base size without files, so the two numbers below add up for the reader.
    final textBytes =
        (_preview?.encode().length ?? 0) - (_preview?.fileBytes ?? 0);
    final total = _withFiles ? textBytes + _fileBytes : textBytes;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Share this note',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                subject == null
                    ? 'It will arrive without a subject.'
                    : 'It will arrive under ${subject.code} — '
                        '${subject.name}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              if (_fileCount > 0)
                _Toggle(
                  title: 'Send the $_fileCount '
                      '${_fileCount == 1 ? 'file' : 'files'} too',
                  subtitle: _withFiles
                      ? 'Photos and PDFs travel inside the note, so it arrives '
                          'complete. Adds ${readableBytes(_fileBytes)}.'
                      : 'Only the text is sent. Much smaller, but the photos '
                          'and PDFs will be missing.',
                  value: _withFiles,
                  onChanged: (v) => setState(() => _withFiles = v),
                )
              else
                Text(
                  'This note has no files attached, so only its text is sent.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 18),
              const Text('WHAT YOU ARE ASKING FOR', style: nestEyebrow),
              const SizedBox(height: 8),
              for (final policy in SharePolicy.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PolicyTile(
                    policy: policy,
                    selected: _policy == policy,
                    onTap: () => setState(() => _policy = policy),
                  ),
                ),
              const SizedBox(height: 4),
              // Said once, plainly. A label that looks like a lock but is not
              // one is worse than no label at all.
              Text(
                'NoteNest cannot enforce this. Once the file is sent, the copy '
                'belongs to whoever has it — this travels with the note as a '
                'request, the way you would ask in person.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NestColor.o(NestColor.redPen, 0.08),
                    borderRadius: BorderRadius.circular(NestRadius.tile),
                    border: const Border(
                      left: BorderSide(color: NestColor.redPen, width: 3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _working || _preview == null ? null : _send,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(
                    _working
                        ? 'Preparing…'
                        : _preview == null
                            ? 'Measuring…'
                            : 'Send  ·  ${readableBytes(total)}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({
    required this.policy,
    required this.selected,
    required this.onTap,
  });

  final SharePolicy policy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? NestColor.o(NestColor.pen, 0.10)
              : NestColor.paper,
          borderRadius: BorderRadius.circular(NestRadius.chip),
          border: Border.all(
            color: selected ? NestColor.pen : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? NestColor.pen : NestColor.inkFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                policy.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: NestColor.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
