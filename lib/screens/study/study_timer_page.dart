import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../data/study_timer.dart';
import '../../l10n/strings.dart';
import '../../models/study_session.dart';
import '../../theme/nest_theme.dart';

/// A focus timer for study, with the day's and the week's totals under it.
class StudyTimerPage extends StatefulWidget {
  const StudyTimerPage({super.key});

  @override
  State<StudyTimerPage> createState() => _StudyTimerPageState();
}

class _StudyTimerPageState extends State<StudyTimerPage> {
  final _repo = NoteRepository.instance;
  final _timer = StudyTimer.instance;

  static const _presets = [15, 25, 45, 60];

  int _minutes = 25;
  int? _subjectId;

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    final text = h > 0 ? '$h:$m:$s' : '$m:$s';
    return AppLanguage.instance.isBangla ? banglaDigits(text) : text;
  }

  String _minutesText(int minutes) {
    final text = formatMinutes(minutes);
    return AppLanguage.instance.isBangla
        ? banglaDigits(
            text.replaceAll('min', 'মিনিট').replaceAll(' h', ' ঘণ্টা'))
        : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Study timer'))),
      body: ListenableBuilder(
        listenable: Listenable.merge([_timer, _repo]),
        builder: (context, _) {
          final running = _timer.running;
          final t = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Center(child: _Dial(timer: _timer, minutes: _minutes, clock: _clock)),
              const SizedBox(height: 22),
              if (_timer.finishedMinutes != null) ...[
                _Banner(
                  text: trp('Well done — {0} saved.', [
                    _minutesText(_timer.finishedMinutes!),
                  ]),
                  onClose: _timer.dismissFinished,
                ),
                const SizedBox(height: 18),
              ],
              if (!running) ...[
                Text(tr('HOW LONG'), style: nestEyebrow),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final m in _presets)
                      ChoiceChip(
                        label: Text(_minutesText(m)),
                        selected: _minutes == m,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _minutes = m),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(tr('WHAT FOR'), style: nestEyebrow),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ChoiceChip(
                      label: Text(tr('Anything')),
                      selected: _subjectId == null,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _subjectId = null),
                    ),
                    for (final s in _repo.subjects())
                      ChoiceChip(
                        label: Text(s.code),
                        selected: _subjectId == s.id,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _subjectId = s.id),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: () => _timer.start(
                    minutes: _minutes,
                    subjectId: _subjectId,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(tr('Start')),
                ),
              ] else ...[
                if (_timer.subjectId != null)
                  Center(
                    child: Text(
                      _repo.subjectById(_timer.subjectId!)?.name ?? '',
                      style: t.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await _timer.stop();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(saved > 0
                          ? trp('Stopped. {0} saved.', [_minutesText(saved)])
                          : tr('Stopped. Under a minute, so nothing saved.')),
                    ));
                  },
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(tr('Stop')),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    tr('You can leave this screen; the timer keeps going and '
                        'rings when it is done.'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 30),
              _Totals(repo: _repo, minutesText: _minutesText),
            ],
          );
        },
      ),
    );
  }
}

/// The countdown: a ring that fills as time passes, the time left inside it.
class _Dial extends StatelessWidget {
  const _Dial({required this.timer, required this.minutes, required this.clock});

  final StudyTimer timer;
  final int minutes;
  final String Function(Duration) clock;

  @override
  Widget build(BuildContext context) {
    final running = timer.running;
    final shown = running ? timer.remaining : Duration(minutes: minutes);
    return SizedBox(
      width: 250,
      height: 250,
      child: CustomPaint(
        painter: _RingPainter(
          progress: running ? timer.progress : 0,
          track: NestColor.paperDeep,
          fill: NestColor.pen,
        ),
        child: Center(
          child: Text(
            clock(shown),
            style: TextStyle(
              fontFamily: NestFont.display,
              fontSize: 54,
              fontWeight: FontWeight.w700,
              color: NestColor.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arc, 0, math.pi * 2, false, paint);
    if (progress > 0) {
      paint.color = fill;
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * progress, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.fill != fill;
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      decoration: BoxDecoration(
        color: NestColor.tintMint,
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration_rounded, color: NestColor.mintDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: NestFont.body,
                fontWeight: FontWeight.w600,
                color: NestColor.mintDeep,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: NestColor.mintDeep),
          ),
        ],
      ),
    );
  }
}

/// Today's total, the run of days, and a bar for each of the last seven.
class _Totals extends StatelessWidget {
  const _Totals({required this.repo, required this.minutesText});

  final NoteRepository repo;
  final String Function(int) minutesText;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final sessions = repo.studySessions();
    final week = minutesPerDay(sessions, DateTime.now());
    final peak = week.fold<int>(1, math.max);
    final streak = repo.studyStreakDays;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: tr('TODAY'),
                  value: minutesText(repo.studiedToday),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: tr('THIS WEEK'),
                  value: minutesText(week.fold(0, (a, b) => a + b)),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: tr('STREAK'),
                  value: trp('{0} days', [streak]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 18,
                          height: week[i] == 0 ? 4 : 8 + 56 * week[i] / peak,
                          decoration: BoxDecoration(
                            color: week[i] == 0
                                ? NestColor.paperDeep
                                : (i == week.length - 1
                                    ? NestColor.pen
                                    : NestColor.o(NestColor.pen, 0.45)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dayLetter(DateTime(today.year, today.month,
                              today.day - (week.length - 1 - i))),
                          style: TextStyle(
                            fontFamily: NestFont.body,
                            fontSize: 11,
                            color: NestColor.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dayLetter(DateTime d) => AppLanguage.instance.isBangla
      ? const ['সো', 'ম', 'বু', 'বৃ', 'শু', 'শ', 'র'][d.weekday - 1]
      : _weekdays[d.weekday - 1];
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: nestEyebrow),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
