import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nest_theme.dart';

class NestNavItem {
  const NestNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Kept because every caller passes it and the drawer reads the same
  /// palette, but the bar no longer draws it: the selected pill is plain
  /// indigo, as in the design.
  final Color accent;
}

/// The bottom bar, floating clear of the page.
///
/// A rounded bar resting *above* the content on its own shadow rather than a
/// strip welded to the bottom edge. That one change does most of the work of
/// making the app feel current: the page runs underneath it, and the bar is
/// obviously a control rather than part of the page.
///
/// The selected destination grows a filled pill with its label; the others are
/// icons alone. The capture button is unchanged from the original design — the
/// offset highlighter block behind a blue key — because it was the one piece
/// of the old bar that was already doing something nobody else does.
class NestNavBar extends StatelessWidget {
  const NestNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.onCapture,
    this.captureLabel = 'New note',
  });

  /// Exactly four destinations; the capture button sits between items 1 and 2.
  final List<NestNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCapture;
  final String captureLabel;

  static const double _pillHeight = 66;
  static const double _sideMargin = 16;
  static const double _bottomMargin = 14;

  /// How far the capture button stands proud of the bar.
  static const double _rise = 12;

  /// The gap in the row that the capture button sits in.
  static const double _wellWidth = 78;

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'NestNavBar expects four destinations');
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: _pillHeight + _rise + _bottomMargin + bottomInset,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: _sideMargin,
            right: _sideMargin,
            bottom: _bottomMargin + bottomInset,
            height: _pillHeight,
            child: Container(
              decoration: BoxDecoration(
                color: NestColor.card,
                borderRadius: BorderRadius.circular(NestRadius.card),
                boxShadow: NestShadow.floating,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(child: _tab(0)),
                  Expanded(child: _tab(1)),
                  const SizedBox(width: _wellWidth),
                  Expanded(child: _tab(2)),
                  Expanded(child: _tab(3)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: _bottomMargin + bottomInset + _pillHeight - 58,
            child: _captureButton(context),
          ),
        ],
      ),
    );
  }

  Widget _tab(int index) {
    final item = items[index];
    final selected = index == currentIndex;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap(index);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 8),
            decoration: BoxDecoration(
              // A plain filled pill, no outline. The outline was mine, not the
              // design's: a 2px ring in a third colour around a filled shape
              // makes the one control you look at most read as a sticker.
              color: selected ? NestColor.pen : Colors.transparent,
              borderRadius: BorderRadius.circular(NestRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 21,
                  color: selected ? Colors.white : NestColor.inkFaint,
                ),
                if (selected) ...[
                  const SizedBox(width: 7),
                  // Flexible and scaled down rather than clipped. Four labels
                  // plus a capture well on a narrow phone is exactly where a
                  // fixed row overflows, and an overflow stripe across the
                  // navigation bar is the worst place to find one.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: NestFont.display,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _captureButton(BuildContext context) {
    return Semantics(
      button: true,
      label: captureLabel,
      child: SizedBox(
        width: 74,
        height: 70,
        child: Stack(
          children: [
            // Highlighter block, offset like a misregistered print.
            Positioned(
              left: 12,
              top: 10,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: NestColor.highlight,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: NestShadow.glow(NestColor.pen),
                ),
                child: Material(
                  color: NestColor.pen,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onCapture();
                    },
                    child: const SizedBox(
                      width: 58,
                      height: 58,
                      child: Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
