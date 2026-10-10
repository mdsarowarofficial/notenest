import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// The microphone level drawn as a pen trace across the page.
///
/// A recording screen has to answer one question at a glance: is it actually
/// hearing me? A number cannot do that and a spinner lies, because it keeps
/// turning in silence. So the levels are drawn as a line that moves with the
/// voice and flattens when the room goes quiet.
///
/// [history] is oldest-first and may be any length; the trace scrolls left as
/// it fills, the way a seismograph does.
class NestLevelMeter extends StatelessWidget {
  const NestLevelMeter({
    super.key,
    required this.history,
    this.live = true,
    this.height = 92,
  });

  final List<double> history;

  /// False while paused, which greys the trace rather than hiding it.
  final bool live;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LevelPainter(
          history: List.of(history),
          live: live,
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter({required this.history, required this.live});

  final List<double> history;
  final bool live;

  static const _bars = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final ink = live ? NestColor.pen : NestColor.inkFaint;

    // The centre line is the ruled line of the page: always there, so a silent
    // room reads as "listening and hearing nothing" rather than "broken".
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = NestColor.rule
        ..strokeWidth = 1,
    );

    if (history.isEmpty) return;

    final slot = size.width / _bars;
    final barWidth = math.max(2.0, slot * 0.46);

    // Newest on the right, so the trace reads the way writing does.
    final shown = history.length > _bars
        ? history.sublist(history.length - _bars)
        : history;
    final offset = _bars - shown.length;

    for (var i = 0; i < shown.length; i++) {
      final level = shown[i].clamp(0.0, 1.0);

      // A little height even at zero, so the trace stays a line and does not
      // break into gaps.
      final amplitude = (midY - 6) * (0.06 + level * 0.94);
      final x = (offset + i) * slot + slot / 2;

      // The newest few strokes are the loudest ink; older ones fade back, so
      // the eye lands on what is being said now.
      final age = (shown.length - 1 - i) / _bars;
      final paint = Paint()
        ..color = NestColor.o(ink, (1 - age * 0.75).clamp(0.2, 1.0))
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, midY - amplitude),
        Offset(x, midY + amplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.live != live ||
      old.history.length != history.length ||
      (old.history.isNotEmpty &&
          history.isNotEmpty &&
          old.history.last != history.last);
}

/// A single pulsing ring behind a microphone button, for the dictation screen
/// where there is no trace to draw — the platform recogniser reports one
/// loudness value, not a waveform.
class NestMicPulse extends StatelessWidget {
  const NestMicPulse({
    super.key,
    required this.level,
    required this.active,
    required this.child,
    this.size = 92,
  });

  final double level;
  final bool active;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reach = active ? (0.55 + level.clamp(0.0, 1.0) * 0.45) : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: reach),
            builder: (context, t, _) => CustomPaint(
              size: Size(size, size),
              painter: _PulsePainter(t),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final inner = size.width * 0.30;
    final outer = size.width * 0.5;

    for (var ring = 0; ring < 2; ring++) {
      final spread = t - ring * 0.22;
      if (spread <= 0) continue;
      canvas.drawCircle(
        center,
        inner + (outer - inner) * spread.clamp(0.0, 1.0),
        Paint()
          ..color = NestColor.o(NestColor.pen, 0.16 - ring * 0.07)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}
