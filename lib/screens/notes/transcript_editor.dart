import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_query.dart';
import '../../models/transcript.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_tags.dart';
import 'note_detail.dart';

/// Turns a dictation into a note worth revising from. Requirement 8.3.
///
/// A raw transcript is one unbroken run of words. This screen does two things
/// to it: it lets the student fix what the recogniser misheard, and it offers
/// to lay the text out — key points first, then the transcript grouped into
/// paragraphs and spoken lists.
///
/// The structuring is rule-based and the screen says so, because a student
/// defending this project should be able to explain exactly why a line was
/// treated as a key point. The rules live in `models/transcript.dart` and are
/// covered by unit tests.
class TranscriptEditorPage extends StatefulWidget {
  const TranscriptEditorPage({
    super.key,
    required this.transcript,
    this.existing,
    this.initialSubjectId,
  });

  final String transcript;

  /// When set the transcript is appended to that note instead of starting a
  /// new one, so dictating into an open note adds to it.
  final Note? existing;

  final int? initialSubjectId;

  @override
  State<TranscriptEditorPage> createState() => _TranscriptEditorPageState();
}

class _TranscriptEditorPageState extends State<TranscriptEditorPage> {
  final _repo = NoteRepository.instance;

  late final TextEditingController _title;
  late final TextEditingController _text;

  int? _subjectId;
  List<String> _tags = const [];
  bool _structure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final cleaned = cleanTranscript(widget.transcript);
    final structured = structureTranscript(cleaned);

    _text = TextEditingController(text: cleaned);
    _title = TextEditingController(
      text: widget.existing?.title ??
          (structured.suggestedTitle.isEmpty
              ? 'Dictated note'
              : structured.suggestedTitle),
    );
    _subjectId = widget.existing?.subjectId ??
        widget.initialSubjectId ??
        (_repo.subjects().isNotEmpty ? _repo.subjects().first.id : null);
    _tags = suggestedTagsFor(cleaned, _repo.allTags());

    _text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  String? _memoFor;
  StructuredNote? _memo;

  /// The structuring is read several times per build — for the word count, the
  /// switch caption, the preview and whether Save is enabled. Re-running the
  /// whole sentence pipeline each time would mean five passes over a long
  /// lecture on every keystroke, so the result is kept until the text changes.
  StructuredNote get _structured {
    if (_memoFor != _text.text) {
      _memoFor = _text.text;
      _memo = structureTranscript(_text.text);
    }
    return _memo!;
  }

  /// What will actually be written into the note body.
  String get _body =>
      _structure ? structuredBody(_structured) : cleanTranscript(_text.text);

  Future<void> _save() async {
    if (_saving || _body.trim().isEmpty) return;
    setState(() => _saving = true);

    final title =
        _title.text.trim().isEmpty ? 'Dictated note' : _title.text.trim();

    final old = widget.existing;

    if (old != null) {
      // Appending rather than replacing: the student dictated into a note that
      // already had something in it, and losing that would be unforgivable.
      final joined =
          old.body.trim().isEmpty ? _body : '${old.body.trim()}\n\n$_body';
      await _repo.updateNote(
        old.copyWith(
          title: title,
          body: joined,
          tags: normalizeTags({...old.tags, ..._tags}),
          subjectId: _subjectId,
          clearSubject: _subjectId == null,
        ),
      );

      if (!mounted) return;
      // Straight back to the note editor this came from. That screen holds the
      // note in its own text controllers and re-reads it on return, so it must
      // get control back rather than being buried under another route.
      Navigator.pop(context, true);
      return;
    }

    final note = await _repo.createNote(
      title: title,
      body: _body,
      subjectId: _subjectId,
      tags: _tags,
    );

    if (!mounted) return;
    // Nothing to go back to but the dictation screen, so this screen is
    // replaced by the finished note.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailPage(noteId: note.id!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final structured = _structured;
    final subjects = _repo.subjects();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Transcript',
          style: TextStyle(
            fontFamily: NestFont.display,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: NestColor.ink,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _body.trim().isEmpty ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
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
          const SizedBox(height: 4),
          Text(
            '${structured.wordCount} words  ·  '
            '${structured.sentenceCount} sentences',
            style: nestEyebrow,
          ),
          const SizedBox(height: 18),
          if (subjects.isNotEmpty) ...[
            const Text('SUBJECT', style: nestEyebrow),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: NestColor.paper,
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _subjectId,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(NestRadius.tile),
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
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _subjectId = v),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          const Text('TAGS', style: nestEyebrow),
          const SizedBox(height: 7),
          NestTagField(
            tags: _tags,
            suggestions: _repo.allTags(),
            onChanged: (next) => setState(() => _tags = next),
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: NestColor.rule),
          const SizedBox(height: 16),
          const Text('WHAT WAS HEARD', style: nestEyebrow),
          const SizedBox(height: 4),
          Text(
            'Fix anything the recogniser misheard. Everything below follows '
            'what you type here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            maxLines: null,
            minLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: NestColor.ink,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: NestColor.paper,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NestRadius.tile),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _StructureSwitch(
            on: _structure,
            keyPointCount: structured.keyPoints.length,
            onChanged: (v) => setState(() => _structure = v),
          ),
          const SizedBox(height: 18),
          const Text('HOW THE NOTE WILL READ', style: nestEyebrow),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NestColor.card,
              borderRadius: BorderRadius.circular(NestRadius.card),
              boxShadow: NestShadow.resting,
            ),
            child: _body.trim().isEmpty
                ? Text(
                    'Nothing to save yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Text(
                    _body,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: NestColor.ink,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The one control that decides whether the transcript is laid out or kept as
/// it was spoken, with an honest line about what the layout is doing.
class _StructureSwitch extends StatelessWidget {
  const _StructureSwitch({
    required this.on,
    required this.keyPointCount,
    required this.onChanged,
  });

  final bool on;
  final int keyPointCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.highlight, 0.18),
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lay it out as a study note',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Switch(value: on, onChanged: onChanged),
            ],
          ),
          Text(
            on
                ? keyPointCount > 0
                    ? 'Split into sentences and grouped. $keyPointCount '
                        '${keyPointCount == 1 ? 'line' : 'lines'} went to Key '
                        'points because of words like "important" or "for the '
                        'exam".'
                    : 'Split into sentences and grouped. No line used a word '
                        'like "important" or "remember", so there are no key '
                        'points.'
                : 'Saved exactly as it was dictated, in one block.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
