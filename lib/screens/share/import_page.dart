import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../data/share_service.dart';
import '../../models/note.dart';
import '../../models/note_bundle.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_tags.dart';
import '../notes/note_detail.dart';

/// Takes a note a classmate sent and puts it in the notebook. Requirement 9.2.
///
/// Nothing is written until the student has seen what is in the file. The file
/// came off someone else's phone, and importing it blind would mean trusting a
/// stranger's data with the notebook — so it is shown first, in full, with who
/// it came from and what it will bring with it.
class ImportNotePage extends StatefulWidget {
  const ImportNotePage({super.key});

  @override
  State<ImportNotePage> createState() => _ImportNotePageState();
}

class _ImportNotePageState extends State<ImportNotePage> {
  final _repo = NoteRepository.instance;

  NoteBundle? _bundle;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pick();
    });
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = await ShareService.pickBundle();
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _busy = false;
      });
    } on BundleException catch (e) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _error = 'That file could not be opened.';
        _busy = false;
      });
    }
  }

  Future<void> _add() async {
    final bundle = _bundle;
    if (bundle == null || _busy) return;
    setState(() => _busy = true);

    final Note note;
    try {
      note = await _repo.importBundle(bundle);
    } catch (_) {
      // Without this the button stayed on its spinner for good.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That note could not be saved on this phone. Check '
              'there is free space and try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailPage(noteId: note.id!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Import a note',
          style: TextStyle(
            fontFamily: NestFont.display,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: NestColor.ink,
          ),
        ),
      ),
      body: _body(context),
      bottomNavigationBar: _bundle == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _pick,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 54),
                        ),
                        child: const Text('Pick another'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.library_add_rounded, size: 18),
                        label: Text(_busy ? 'Adding…' : 'Add to my notes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context) {
    if (_busy && _bundle == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final bundle = _bundle;
    if (bundle == null) return _chooser(context);

    final t = Theme.of(context).textTheme;
    final subject = bundle.subjectCode;
    final mine = subject == null ? null : _repo.subjectByCode(subject);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        _FromCard(bundle: bundle),
        const SizedBox(height: 20),
        Text(bundle.title, style: t.displaySmall),
        const SizedBox(height: 8),
        Text(
          'Written ${relativeDay(bundle.writtenAt)}',
          style: nestEyebrow.copyWith(
            letterSpacing: 0.3,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (bundle.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          NestTagChips(tags: bundle.tags),
        ],
        const SizedBox(height: 20),
        _Row(
          icon: Icons.folder_outlined,
          label: 'Subject',
          value: subject == null
              ? 'None — it will sit outside your subjects'
              : mine == null
                  ? '$subject will be created in your notebook'
                  : 'Goes into your existing $subject',
        ),
        if (bundle.topic != null)
          _Row(
            icon: Icons.label_outline_rounded,
            label: 'Topic',
            value: bundle.topic!,
          ),
        _Row(
          icon: Icons.attach_file_rounded,
          label: 'Files',
          value: bundle.hasFiles
              ? '${bundle.files.length} '
                  '${bundle.files.length == 1 ? 'file' : 'files'}  ·  '
                  '${readableBytes(bundle.fileBytes)}'
              : 'None',
        ),
        const SizedBox(height: 22),
        Container(height: 1, color: NestColor.rule),
        const SizedBox(height: 18),
        const Text('WHAT IT SAYS', style: nestEyebrow),
        const SizedBox(height: 10),
        if (bundle.body.trim().isEmpty)
          Text('This note has no text, only its title.', style: t.bodySmall)
        else
          Text(
            bundle.body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: NestColor.ink,
            ),
          ),
      ],
    );
  }

  Widget _chooser(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _error == null
                  ? Icons.download_rounded
                  : Icons.error_outline_rounded,
              size: 34,
              color: _error == null ? NestColor.inkFaint : NestColor.redPen,
            ),
            const SizedBox(height: 16),
            Text(
              _error == null ? 'Pick the file' : 'That did not work',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              _error ??
                  'Save the .notenest file your classmate sent you, then pick '
                      'it here. Everything in it is shown before anything is '
                      'added to your notebook.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(_error == null ? 'Choose a file' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who sent it and what they asked for, kept at the top where it is read
/// before anything else.
class _FromCard extends StatelessWidget {
  const _FromCard({required this.bundle});

  final NoteBundle bundle;

  @override
  Widget build(BuildContext context) {
    final reference = bundle.policy == SharePolicy.reference;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.highlight, 0.20),
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: NestColor.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'From ${bundle.sharedBy}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reference
                ? '${bundle.sharedBy} asked that you keep this as reference '
                    'rather than pass it on. NoteNest cannot enforce that — it '
                    'is a request, and the copy will be yours to edit.'
                : '${bundle.sharedBy} is happy for you to edit this and pass '
                    'it on. Their name stays on it either way.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: NestColor.inkFaint),
          const SizedBox(width: 12),
          SizedBox(
            width: 68,
            child: Text(label.toUpperCase(), style: nestEyebrow),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
