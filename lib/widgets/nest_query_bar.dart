import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_query.dart';
import '../theme/nest_theme.dart';
import 'note_tile.dart';

/// The filter and sort strip above a list of notes. Requirement 6.2.
///
/// One row of chips that scrolls sideways, with the sort menu pinned on the
/// right so it never scrolls out of reach.
///
/// A chip at rest is a white pill lying on the page on its own soft shadow;
/// switched on it fills with its own colour and the label reverses out. The
/// earlier version marked the on state with a 1.5px border and an 18%-opacity
/// wash, which is a difference you have to look for. A solid fill is one you
/// cannot miss at arm's length — and that matters most here, because the whole
/// point of the strip is to tell you at a glance why the list below is short.
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
            // The dot keeps the light status colour; the fill uses the deeper
            // one, because white type on a pale dot colour is unreadable.
            accent: StatusPill.inkFor(status),
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
      // Taller than the chips themselves: a horizontal ListView clips, and at
      // exactly chip height it would shave the soft shadow off top and bottom.
      height: 50,
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
    final Color fill = active
        ? accent
        : (outlined ? NestColor.paperDeep : NestColor.card);
    final Color labelInk = active ? Colors.white : NestColor.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(NestRadius.pill),
          // A chip on is lit from under by its own colour; a chip off just
          // rests on the page. Nothing carries a hairline border, which is
          // what made the old strip read as a table of buttons.
          boxShadow: active
              ? NestShadow.glow(accent)
              : (outlined ? const <BoxShadow>[] : _chipRest),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? Colors.white : dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: active ? Colors.white : NestColor.inkSoft,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: labelInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lighter than [NestShadow.resting]: a chip is a small object and the card
/// shadow under one looks like a smudge.
const _chipRest = <BoxShadow>[
  BoxShadow(
    color: Color(0x0F1B1E2B),
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: NestColor.card,
          borderRadius: BorderRadius.circular(NestRadius.pill),
          boxShadow: _chipRest,
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
                fontFamily: NestFont.body,
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
