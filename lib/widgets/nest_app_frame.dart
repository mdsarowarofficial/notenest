import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// Holds the app to a phone's width on a wide screen.
///
/// NoteNest is laid out for a phone: a 44px tap target, one column, a nav bar
/// across the thumb. Run the same code in a desktop browser window and every
/// one of those decisions turns into a defect — a primary button eighteen
/// hundred pixels wide, cards with a paragraph of air inside them, a nav bar
/// whose five destinations are a mouse-sweep apart. Nothing is broken; the
/// layout is simply being asked a question it was never designed to answer.
///
/// So it answers it once, here: past [maxWidth] the app stops stretching and
/// centres on a quiet backdrop, the way a phone app looks when it is shown on
/// a laptop on purpose. The alternative — a real desktop layout, with a
/// sidebar and a two-column list/detail split — is a different design, not a
/// breakpoint, and this app does not have one.
///
/// Installed through `MaterialApp.builder`, so it wraps the Navigator: every
/// pushed route, dialog and bottom sheet is inside it, not only the first
/// screen.
class NestAppFrame extends StatelessWidget {
  const NestAppFrame({super.key, required this.child});

  final Widget child;

  /// A little wider than a large phone (430pt), so the layout gets its natural
  /// amount of air and no more.
  static const double maxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;

    return ColoredBox(
      color: NestColor.paper,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NestColor.ground,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A1B1E2B),
                  blurRadius: 40,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            // The size inside the frame is the size the app is drawn at, so
            // anything measuring the window — a chat bubble capped at 78% of
            // it, a sheet sized against it — measures the frame instead of the
            // monitor. Without this the app is narrow but still thinks it is
            // wide, which is worse than either.
            child: MediaQuery(
              data: media.copyWith(
                size: Size(maxWidth, media.size.height),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
