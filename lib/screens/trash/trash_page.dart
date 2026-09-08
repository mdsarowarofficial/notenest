import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/note_tile.dart';

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

  void _refresh() => setState(() => _future = _repo.trashedNotes());

  Future<void> _restore(Note note) async {
    await _repo.restoreNote(note);
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Note restored'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteForever(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Delete permanently?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.deleteNoteForever(note);
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Note deleted permanently'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trash',
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
            return const NestEmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              message: 'Deleted notes wait here so you can bring them back.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              Text(
                'Deleted notes stay here until you remove them permanently.',
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
                        tooltip: 'Restore',
                        icon: const Icon(Icons.restore_rounded,
                            size: 20, color: NestColor.pen),
                        onPressed: () => _restore(note),
                      ),
                      IconButton(
                        tooltip: 'Delete permanently',
                        icon: const Icon(Icons.delete_forever_rounded,
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
