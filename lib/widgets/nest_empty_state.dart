import 'package:flutter/material.dart';

import '../theme/nest_theme.dart';

/// Shown when a screen has nothing to display.
///
/// Every list in NoteNest needs one of these, so it lives here rather than
/// being rewritten on each screen. An empty state should always say what the
/// screen is for and, where possible, offer the action that fills it.
///
/// The icon sits in a soft round well rather than floating on the page. A bare
/// grey glyph on a grey background is the single thing that makes an empty
/// screen look broken instead of ready.
class NestEmptyState extends StatelessWidget {
  const NestEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: NestColor.card,
                shape: BoxShape.circle,
                boxShadow: NestShadow.resting,
              ),
              child: Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: NestColor.tintPen,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: NestColor.pen),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
