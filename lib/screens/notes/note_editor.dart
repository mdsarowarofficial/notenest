import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';

/// Write or edit a text note. Requirement 5.1.
///
/// The draft is saved while typing, so closing the app mid-sentence does not
/// lose work. A note with no title and no body is never saved.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.existing, this.initialSubjectId});

  final Note? existing;
  final int? initialSubjectId;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _repo = NoteRepository.instance;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _topic;

  int? _subjectId;
  Note? _note;
  Timer? _autosave;
  bool _dirty = false;
  bool _saving = false;
  DateTime? _savedAt;

  @override
  void initState() {
    super.initState();
    _note = widget.existing;
    _title = TextEditingController(text: _note?.title ?? '');
    _body = TextEditingController(text: _note?.body ?? '');
    _topic = TextEditingController(text: _note?.topic ?? '');
    _subjectId = _note?.subjectId ??
        widget.initialSubjectId ??
        (_repo.subjects().isNotEmpty ? _repo.subjects().first.id : null);

    for (final c in [_title, _body, _topic]) {
      c.addListener(_markDirty);
    }

    // Two seconds of quiet is enough to treat the draft as worth keeping.
    _autosave = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _persist(silent: true),
    );
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _title.dispose();
    _body.dispose();
    _topic.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool get _isEmpty =>
      _title.text.trim().isEmpty && _body.text.trim().isEmpty;

  Future<void> _persist({bool silent = false}) async {
    if (!_dirty || _isEmpty || _saving) return;
    _saving = true;

    final title =
        _title.text.trim().isEmpty ? 'Untitled note' : _title.text.trim();

    if (_note == null) {
      _note = await _repo.createNote(
        title: title,
        body: _body.text,
        subjectId: _subjectId,
        topic: _topic.text,
      );
    } else {
      final updated = _note!.copyWith(
        title: title,
        body: _body.text,
        topic: _topic.text.trim(),
        subjectId: _subjectId,
        clearSubject: _subjectId == null,
      );
      await _repo.updateNote(updated);
      _note = updated;
    }

    _saving = false;
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _savedAt = DateTime.now();
    });
  }

  Future<void> _saveAndClose() async {
    if (_isEmpty) {
      Navigator.pop(context);
      return;
    }
    await _persist();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _repo.subjects();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveAndClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _saveAndClose,
          ),
          title: Text(
            widget.existing == null ? 'New note' : 'Edit note',
            style: const TextStyle(
              fontFamily: NestFont.display,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: NestColor.ink,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  _dirty
                      ? 'Unsaved'
                      : _savedAt != null
                          ? 'Saved'
                          : '',
                  style: nestEyebrow.copyWith(
                    color: _dirty ? NestColor.redPen : NestColor.mint,
                  ),
                ),
              ),
            ),
            TextButton(onPressed: _saveAndClose, child: const Text('Done')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontFamily: NestFont.display,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: NestColor.ink,
              ),
              decoration: const InputDecoration(
                hintText: 'Note title',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SUBJECT', style: nestEyebrow),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: NestColor.paper,
                          borderRadius:
                              BorderRadius.circular(NestRadius.chip),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: _subjectId,
                            isExpanded: true,
                            borderRadius:
                                BorderRadius.circular(NestRadius.tile),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('No subject',
                                    style: TextStyle(fontSize: 14)),
                              ),
                              for (final s in subjects)
                                DropdownMenuItem<int?>(
                                  value: s.id,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: s.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          s.code,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _subjectId = v;
                              _dirty = true;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOPIC', style: nestEyebrow),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _topic,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Normalization',
                          filled: true,
                          fillColor: NestColor.paper,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(NestRadius.chip),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(height: 1, color: NestColor.rule),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              maxLines: null,
              minLines: 12,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.55,
                color: NestColor.ink,
              ),
              decoration: const InputDecoration(
                hintText: 'Write your note...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
