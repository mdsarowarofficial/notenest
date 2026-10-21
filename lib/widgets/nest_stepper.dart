import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';
import 'nest_marks.dart';
import '../l10n/strings.dart';

/// One stop in a NoteNest flow.
class NestStep {
  const NestStep({required this.title, required this.icon, this.hint = ''});

  final String title;
  final IconData icon;

  /// One short line describing what the student does here.
  final String hint;
}

/// A horizontal stepper drawn as a page of notes: a dotted pencil guide that
/// gets inked in as the student advances, tab-shaped nodes, a red-pen tick on
/// finished steps and a highlighter swipe under the step they are on.
///
/// Used for setup flows (semester setup, note capture, exam planning) where the
/// order genuinely carries information.
class NestStepper extends StatelessWidget {
  const NestStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.onStepTapped,
    this.showHeader = true,
  });

  final List<NestStep> steps;
  final int currentIndex;

  /// Called when a completed step is tapped. Upcoming steps are not tappable,
  /// so the student can go back but cannot skip ahead.
  final ValueChanged<int>? onStepTapped;
  final bool showHeader;

  static const double _nodeSize = 42;
  static const double _railY = _nodeSize / 2;

  @override
  Widget build(BuildContext context) {
    final current = steps[currentIndex.clamp(0, steps.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Text(
                trp('STEP {0} / {1}', [_two(currentIndex + 1), _two(steps.length)]),
                style: nestEyebrow.copyWith(color: NestColor.pen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(height: 1, color: NestColor.rule),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(current.title, style: Theme.of(context).textTheme.displaySmall),
          if (current.hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(current.hint, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 22),
        ],
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: currentIndex.toDouble()),
          builder: (context, progress, _) {
            return SizedBox(
              height: 86,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: PenRailPainter(
                        count: steps.length,
                        progress: progress,
                        centerY: _railY,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        Expanded(child: _node(context, i)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _node(BuildContext context, int i) {
    final done = i < currentIndex;
    final active = i == currentIndex;

    final node = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: _nodeSize,
      height: _nodeSize,
      decoration: BoxDecoration(
        color: done ? NestColor.pen : (active ? NestColor.card : NestColor.paperDeep),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? NestColor.pen : Colors.transparent,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: NestColor.o(NestColor.penDeep, 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Icon(
        done ? Icons.check_rounded : steps[i].icon,
        size: 20,
        color: done
            ? Colors.white
            : active
                ? NestColor.pen
                : NestColor.inkFaint,
      ),
    );

    final label = Text(
      steps[i].title,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: NestFont.body,
        fontSize: 11.5,
        height: 1.25,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active
            ? NestColor.ink
            : done
                ? NestColor.inkSoft
                : NestColor.inkFaint,
      ),
    );

    return Semantics(
      button: done,
      selected: active,
      label: trp('{0}, step {1} of {2}', [steps[i].title, i + 1, steps.length]),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: done ? () => onStepTapped?.call(i) : null,
        child: Column(
          children: [
            node,
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: active
                  ? Highlighted(child: label)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: label,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
