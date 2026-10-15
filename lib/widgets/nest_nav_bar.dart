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
/// Every destination shows its icon and its name; the selected one's icon sits
/// in a filled pill. The capture button is unchanged from the original design — the
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
    this.itemKeys,
    this.captureKey,
  });

  /// Optional handles on each tab and on the capture button, so the first-run
  /// tour can point at them.
  final List<GlobalKey>? itemKeys;
  final GlobalKey? captureKey;

  /// Exactly four destinations; the capture button sits between items 1 and 2.
  final List<NestNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCapture;
  final String captureLabel;

  static const double _pillHeight = 72;
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
      key: itemKeys != null && index < itemKeys!.length
          ? itemKeys![index]
          : null,
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap(index);
        },
        // Every tab carries its name, not only the selected one. Icons alone
        // were the bar's real failure: somebody who had not yet learned which
        // glyph was People and which was Exam had to tap to find out, and the
        // one label that did show was 12.5px white on a coloured pill.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              height: 30,
              width: selected ? 54 : 40,
              decoration: BoxDecoration(
                // A plain filled pill, no outline: a ring in a third colour
                // around a filled shape reads as a sticker.
                color: selected ? NestColor.pen : Colors.transparent,
                borderRadius: BorderRadius.circular(NestRadius.pill),
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                size: 22,
                color: selected ? Colors.white : NestColor.inkSoft,
              ),
            ),
            const SizedBox(height: 4),
            // Scaled down rather than clipped, so a large system font on a
            // narrow phone shrinks the word instead of striping the bar with
            // an overflow warning.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: NestFont.display,
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? NestColor.pen : NestColor.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureButton(BuildContext context) {
    return Semantics(
      key: captureKey,
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
