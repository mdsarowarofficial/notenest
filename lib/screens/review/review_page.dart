import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../l10n/strings.dart';
import '../../models/note.dart';
import '../../models/review_schedule.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/note_body.dart';
import '../notes/attachment_strip.dart';

/// Reviewing the notes that are due, one at a time.
///
/// Each note comes up as a card with only its title showing: try to recall
/// what it says, then reveal it and say how it went. The answer sets when the
/// note comes back, so the notes you know drift away and the ones you forget
/// keep returning until they stick.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _repo = NoteRepository.instance;

  /// Fixed when the page opens, so answering a card does not reshuffle the
  /// ones still waiting.
  late final List<int> _queue =
      _repo.dueForReview().map((n) => n.id!).toList();

  int _index = 0;
  bool _revealed = false;
  final _counts = {for (final r in Recall.values) r: 0};

  Note? get _note => _index < _queue.length ? _repo.noteById(_queue[_index]) : null;

  Future<void> _answer(Recall recall) async {
    final note = _note;
    if (note != null) await _repo.recordRecall(note, recall);
    if (!mounted) return;
    setState(() {
      _counts[recall] = _counts[recall]! + 1;
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index >= _queue.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Review today')),
        actions: [
          if (_queue.isNotEmpty && !finished)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  trp('{0} / {1}', [_index + 1, _queue.length]),
                  style: nestEyebrow,
                ),
              ),
            ),
        ],
      ),
      body: _queue.isEmpty
          ? _Message(
              icon: Icons.task_alt_rounded,
              title: tr('Nothing to review today'),
              body: tr('Notes you mark Read or Review come back here on a '
                  'schedule, each one just before you would forget it.'),
              action: tr('Back'),
              onAction: () => Navigator.of(context).pop(),
            )
          : finished
              ? _Message(
                  icon: Icons.celebration_rounded,
                  title: tr('All reviewed'),
                  body: trp('{0} remembered, {1} hard, {2} forgotten.', [
                    _counts[Recall.good],
                    _counts[Recall.hard],
                    _counts[Recall.forgot],
                  ]),
                  action: tr('Done'),
                  onAction: () => Navigator.of(context).pop(),
                )
              : _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final note = _note;
    if (note == null) {
      // The note was deleted while reviewing; move on.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index++);
      });
      return const SizedBox.shrink();
    }
    final subject =
        note.subjectId == null ? null : _repo.subjectById(note.subjectId!);
    final t = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NestRadius.pill),
            child: LinearProgressIndicator(
              value: _index / _queue.length,
              minHeight: 6,
              backgroundColor: NestColor.paperDeep,
              valueColor: AlwaysStoppedAnimation(NestColor.pen),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                decoration: BoxDecoration(
                  color: NestColor.card,
                  borderRadius: BorderRadius.circular(NestRadius.card),
                  boxShadow: NestShadow.lifted,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subject != null)
                      Text(
                        subject.code.toUpperCase(),
                        style: nestEyebrow.copyWith(color: NestColor.pen),
                      ),
                    if ((note.topic ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(note.topic!, style: t.bodySmall),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      note.title.isEmpty ? tr('Untitled note') : note.title,
                      style: t.displaySmall,
                    ),
                    const SizedBox(height: 22),
                    if (!_revealed) ...[
                      Text(
                        tr('Try to remember what this note says, then check.'),
                        style: t.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => setState(() => _revealed = true),
                          child: Text(tr('Show the note')),
                        ),
                      ),
                    ] else ...[
                      Container(height: 1, color: NestColor.rule),
                      const SizedBox(height: 16),
                      if (note.body.trim().isEmpty)
                        Text(tr('This note has no body yet.'),
                            style: t.bodySmall)
                      else
                        NoteBody(body: note.body),
                      const SizedBox(height: 14),
                      AttachmentStrip(note: note),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_revealed)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _AnswerButton(
                    label: tr('Forgot'),
                    gap: _gap(note, Recall.forgot),
                    tint: NestColor.tintRed,
                    ink: NestColor.redDeep,
                    onTap: () => _answer(Recall.forgot),
                  ),
                  const SizedBox(width: 10),
                  _AnswerButton(
                    label: tr('Hard'),
                    gap: _gap(note, Recall.hard),
                    tint: NestColor.tintWarm,
                    ink: NestColor.warmDeep,
                    onTap: () => _answer(Recall.hard),
                  ),
                  const SizedBox(width: 10),
                  _AnswerButton(
                    label: tr('Got it'),
                    gap: _gap(note, Recall.good),
                    tint: NestColor.tintMint,
                    ink: NestColor.mintDeep,
                    onTap: () => _answer(Recall.good),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// "tomorrow", "in 7 days": when this answer would bring the note back.
  String _gap(Note note, Recall recall) {
    final days = daysFor(note.reviewStep, DateTime.now(), recall);
    return days <= 1 ? tr('tomorrow') : trp('in {0} days', [days]);
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.gap,
    required this.tint,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final String gap;
  final Color tint;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: NestFont.display,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  gap,
                  style: TextStyle(
                    fontFamily: NestFont.body,
                    fontSize: 11.5,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: NestColor.pen),
            const SizedBox(height: 18),
            Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(body, style: t.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
