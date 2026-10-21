import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';
import '../../l10n/strings.dart';

/// Deleted notes, with restore and permanent delete. Requirement 13.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final _repo = NoteRepository.instance;

  late Future<List<Note>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.trashedNotes();
  }

  void _refresh() {
    // A block body, not an arrow: an arrow would hand setState the Future that
    // the assignment evaluates to, and Flutter rejects that.
    final next = _repo.trashedNotes();
    setState(() {
      _future = next;
    });
  }

  Future<void> _restore(Note note) async {
    await _repo.restoreNote(note);
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Note restored')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteForever(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Delete permanently?')),
        content: Text(tr('This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.deleteNoteForever(note);
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Note deleted permanently')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Trash'),
          style: TextStyle(
            fontFamily: NestFont.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: NestColor.ink,
          ),
        ),
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data ?? const <Note>[];
          if (notes.isEmpty) {
            return NestEmptyState(
              icon: Icons.delete_outline_rounded,
              title: tr('Trash is empty'),
              message: tr('Deleted notes wait here so you can bring them back.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              Text(
                tr('Deleted notes stay here until you remove them permanently.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final note in notes)
                NoteTile(
                  note: note,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('Restore'),
                        icon: Icon(Icons.restore_rounded,
                            size: 20, color: NestColor.pen),
                        onPressed: () => _restore(note),
                      ),
                      IconButton(
                        tooltip: tr('Delete permanently'),
                        icon: Icon(Icons.delete_forever_rounded,
                            size: 20, color: NestColor.redPen),
                        onPressed: () => _deleteForever(note),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
