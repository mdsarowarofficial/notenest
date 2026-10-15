import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// The app's opening: the launcher icon drawn again, and finished.
///
/// The icon on the home screen is one frame of this — a page with its corner
/// already turned down. Tapping it plays the rest: the page arrives, the
/// corner folds, the line you meant to revise is marked, and the whole mark
/// opens out into the app. It is the same drawing in the same two colours, so
/// the tap and the app are one movement rather than two pictures.
///
/// It runs over the app, not before it. The child is built and laid out from
/// the first frame underneath this, so the animation costs nothing: by the
/// time it lifts, Today is already there.
class NestOpening extends StatefulWidget {
  const NestOpening({super.key, required this.child});

  final Widget child;

  @override
  State<NestOpening> createState() => _NestOpeningState();
}

class _NestOpeningState extends State<NestOpening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );

  /// Once finished the overlay is gone for good: no controller, no repaint,
  /// nothing between the app and the person's finger.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always the same Stack with the child first, finished or not. Returning
    // the bare child once the fold lifted changed the tree's shape, and
    // Flutter answered by throwing the first screen away and building a new
    // one — its state lost, and everything it started on opening (the
    // first-run tour, the account sync) started a second time.
    return Stack(
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _FoldPainter(_c.value),
                willChange: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the fold at a point in time.
///
/// One painter rather than a stack of animated widgets, because the crease and
/// the turned corner have to stay registered to each other to the pixel; two
/// widgets animating on their own curves drift apart by a pixel or two and the
/// fold stops looking like paper.
class _FoldPainter extends CustomPainter {
  _FoldPainter(this.t);

  /// 0 to 1 across the whole opening.
  final double t;

  /// Where each move starts and ends, as a fraction of the whole.
  static const _pageIn = [0.06, 0.40];
  static const _fold = [0.34, 0.68];
  static const _mark = [0.62, 0.84];
  static const _exit = [0.80, 1.00];

  static double _span(double t, List<double> at, Curve curve) {
    final raw = ((t - at[0]) / (at[1] - at[0])).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final leaving = _span(t, _exit, Curves.easeInCubic);
    if (leaving >= 1) return;

    // The ground fades rather than the mark flying away: the app is already
    // drawn underneath, so the yellow lifting off it is the whole transition.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPaint(Paint()..color = NestColor.highlight);

    final shown = _span(t, _pageIn, Curves.easeOutCubic);
    if (shown > 0) {
      // The mark grows slightly as the ground goes, so it reads as opening
      // out towards you rather than merely disappearing.
      final grow = 1 + leaving * 0.22;
      final box = size.shortestSide * 0.54 * grow;
      final w = box * 0.591;
      final h = box * 0.708;
      final left = (size.width - w) / 2;
      final top = (size.height - h) / 2;

      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(0.86 + shown * 0.14);
      canvas.translate(-size.width / 2, -size.height / 2);

      final page = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        Radius.circular(box * 0.083),
      );
      // Everything inside the page is clipped to the page, so the turned
      // corner is cut by the same rounded outline the paper has. Without this
      // the flap's square corner pokes out past the curve and the fold stops
      // reading as paper at all.
      canvas.save();
      canvas.clipRRect(page);
      canvas.drawRRect(page, Paint()..color = NestColor.pen);

      // The ruled lines. The top one is the mark, and it draws itself.
      final marked = _span(t, _mark, Curves.easeOutCubic);
      final lh = h * 0.0765;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + w * 0.155, top + h - h * 0.415 - lh,
              w * 0.60 * marked, lh),
          Radius.circular(lh / 2),
        ),
        Paint()..color = NestColor.highlight,
      );
      final lh2 = h * 0.053;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              left + w * 0.155, top + h - h * 0.265 - lh2, w * 0.40, lh2),
          Radius.circular(lh2 / 2),
        ),
        Paint()..color = const Color(0xFFAAB4EC),
      );

      // The corner turning down: the flap grows from the corner itself, so
      // the crease sweeps across rather than the triangle fading in.
      final folded = _span(t, _fold, Curves.easeOutCubic);
      if (folded > 0) {
        final leg = w * 0.43 * folded;
        final corner = Offset(left + w, top);
        final flap = Path()
          ..moveTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + leg)
          ..lineTo(corner.dx - leg, corner.dy)
          ..close();

        canvas.save();
        canvas.translate(-box * 0.006, box * 0.006);
        canvas.drawPath(
          flap,
          Paint()
            ..color = const Color(0xFF2E3A96)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, box * 0.022),
        );
        canvas.restore();
        canvas.drawPath(flap, Paint()..color = Colors.white);
      }

      canvas.restore(); // the page's own clip layer
      canvas.restore(); // the entry scale
    }

    // Lift the whole opening off the app underneath.
    canvas.drawPaint(
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = Colors.black.withAlpha((leaving * 255).round()),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoldPainter old) => old.t != t;
}
