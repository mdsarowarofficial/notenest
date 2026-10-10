import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_query.dart';
import '../theme/nest_theme.dart';
import 'note_tile.dart';

/// The filter and sort strip above a list of notes. Requirement 6.2.
///
/// One row of chips that scrolls sideways, with the sort menu pinned on the
/// right so it never scrolls out of reach. The chips are the index tabs of a
/// subject divider: flat, coloured by what they stand for, and pressed in when
/// switched on.
class NestQueryBar extends StatelessWidget {
  const NestQueryBar({
    super.key,
    required this.query,
    required this.onChanged,
    this.tags = const [],
    this.showTypes = true,
    this.showStatuses = true,
  });

  final NoteQuery query;
  final ValueChanged<NoteQuery> onChanged;

  /// Offered as tag chips. Pass the tags actually in use.
  final List<String> tags;

  final bool showTypes;
  final bool showStatuses;

  /// Voice is left out until lecture recording is actually built, so the bar
  /// never offers a filter that can only ever return nothing.
  static const _types = <_TypeChoice>[
    _TypeChoice(NoteType.text, Icons.notes_rounded),
    _TypeChoice(NoteType.image, Icons.photo_rounded),
    _TypeChoice(NoteType.pdf, Icons.picture_as_pdf_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _QueryChip(
        label: 'Important',
        icon: Icons.star_rounded,
        accent: NestColor.redPen,
        active: query.importantOnly,
        onTap: () => onChanged(
          query.copyWith(importantOnly: !query.importantOnly),
        ),
      ),
      if (showTypes)
        for (final choice in _types)
          _QueryChip(
            label: choice.type.label,
            icon: choice.icon,
            accent: NestColor.pen,
            active: query.type == choice.type,
            onTap: () => onChanged(query.toggleType(choice.type)),
          ),
      if (showStatuses)
        for (final status in StudyStatus.values)
          _QueryChip(
            label: status.label,
            dot: StatusDot.colorFor(status),
            accent: StatusDot.colorFor(status),
            active: query.status == status,
            onTap: () => onChanged(query.toggleStatus(status)),
          ),
      for (final tag in tags)
        _QueryChip(
          label: '#$tag',
          accent: NestColor.pen,
          active: query.tag != null && normalizeTag(query.tag!) == tag,
          onTap: () => onChanged(query.toggleTag(tag)),
        ),
      if (query.activeFilters > 0)
        _QueryChip(
          label: 'Clear',
          icon: Icons.close_rounded,
          accent: NestColor.inkSoft,
          active: false,
          outlined: true,
          onTap: () => onChanged(query.withoutFilters()),
        ),
    ];

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) => Center(child: chips[i]),
            ),
          ),
          const SizedBox(width: 6),
          _SortButton(
            sort: query.sort,
            onPick: (s) => onChanged(query.copyWith(sort: s)),
          ),
        ],
      ),
    );
  }
}

class _TypeChoice {
  const _TypeChoice(this.type, this.icon);

  final NoteType type;
  final IconData icon;
}

class _QueryChip extends StatelessWidget {
  const _QueryChip({
    required this.label,
    required this.accent,
    required this.active,
    required this.onTap,
    this.icon,
    this.dot,
    this.outlined = false,
  });

  final String label;
  final Color accent;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? NestColor.o(accent, 0.18)
              : (outlined ? Colors.transparent : NestColor.card),
          borderRadius: BorderRadius.circular(NestRadius.chip),
          border: Border.all(
            color: active ? accent : NestColor.rule,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: active ? accent : NestColor.inkSoft,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? NestColor.ink : NestColor.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onPick});

  final NoteSort sort;
  final ValueChanged<NoteSort> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<NoteSort>(
      tooltip: 'Sort notes',
      initialValue: sort,
      onSelected: onPick,
      color: NestColor.card,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      itemBuilder: (_) => [
        for (final option in NoteSort.values)
          PopupMenuItem<NoteSort>(
            value: option,
            height: 44,
            child: Row(
              children: [
                Icon(
                  option == sort
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: option == sort ? NestColor.pen : NestColor.inkFaint,
                ),
                const SizedBox(width: 10),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        option == sort ? FontWeight.w700 : FontWeight.w500,
                    color: NestColor.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.chip),
          border: Border.all(color: NestColor.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded,
                size: 15, color: NestColor.inkSoft),
            const SizedBox(width: 5),
            Text(
              sort.shortLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: NestColor.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
