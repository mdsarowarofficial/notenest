import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// One stop on the tour.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.target,
    this.icon = Icons.lightbulb_outline_rounded,
  });

  /// What to point at. Null for a stop with nothing to point at — the
  /// welcome and the goodbye — which shows the card in the middle.
  final GlobalKey? target;
  final String title;
  final String body;
  final IconData icon;
}

/// Walks a new person round the screen, one control at a time.
///
/// The page dims, a lit cut-out sits over the control being explained, and a
/// card beside it says what it is for. A tour rather than a slideshow of
/// screenshots before the app opens, because what somebody needs to learn is
/// *where things are on this screen*, and only the real screen can show that.
///
/// Returns true if it ran to the end, false if it was skipped. Either way the
/// caller should mark it as seen — a skip is an answer too.
Future<bool> showNestTour(BuildContext context, List<TourStep> steps) async {
  if (steps.isEmpty) return true;
  final finished = await Navigator.of(context).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => _TourOverlay(steps: steps),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  return finished ?? false;
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});

  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _index = 0;

  TourStep get _step => widget.steps[_index];
  bool get _last => _index == widget.steps.length - 1;

  /// Where the target is on screen now, or null when it has none or is not
  /// laid out (an off-screen tab, say) — then the card simply centres.
  Rect? _targetRect() {
    final context = _step.target?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    // Kept inside the screen, so a control at the edge (the menu, search)
    // gets a whole outline rather than one cut off by the glass.
    final screen = Offset.zero & MediaQuery.of(this.context).size;
    return (origin & box.size).inflate(6).intersect(screen.deflate(4));
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _index++);
    }
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hole = _targetRect();
    final padding = MediaQuery.of(context).padding;

    // Below the target when it is in the top half of the screen, above it
    // otherwise, so the card never covers what it is talking about.
    final below = hole == null || hole.center.dy < size.height / 2;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: CustomPaint(
                painter: _ScrimPainter(hole: hole),
              ),
            ),
          ),
          if (hole != null)
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NestColor.highlight, width: 3),
                  ),
                ),
              ),
            ),
          if (hole == null)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(child: _card(context)),
              ),
            )
          else
            Positioned(
              left: 18,
              right: 18,
              top: below
                  ? (hole.bottom + 14)
                      .clamp(padding.top + 8, size.height - 260)
                      .toDouble()
                  : null,
              bottom: below
                  ? null
                  : (size.height - hole.top + 14)
                      .clamp(padding.bottom + 8, size.height - 260)
                      .toDouble(),
              child: _card(context),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(_index),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.card),
          boxShadow: NestShadow.floating,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NestColor.tintPen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_step.icon, color: NestColor.pen, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_step.title, style: t.titleMedium)),
                Text(
                  '${_index + 1} / ${widget.steps.length}',
                  style: t.bodySmall,
                ),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 10),
            Text(_step.body, style: t.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!_last)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Skip tour'),
                  ),
                const Spacer(),
                if (_index > 0)
                  TextButton(onPressed: _back, child: const Text('Back')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _next,
                  child: Text(_last ? 'Start using NoteNest' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final cut = hole;
    final path = cut == null
        ? scrim
        : Path.combine(
            PathOperation.difference,
            scrim,
            Path()
              ..addRRect(
                  RRect.fromRectAndRadius(cut, const Radius.circular(18))),
          );
    canvas.drawPath(path, Paint()..color = const Color(0xC0101322));
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole;
}
