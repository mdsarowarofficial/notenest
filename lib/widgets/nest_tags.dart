import 'package:flutter/material.dart';

import '../models/note_query.dart';
import '../theme/nest_theme.dart';

/// Tags as they appear on a note: small torn-paper labels in pen ink.
///
/// Used read-only on the note screen and in search results. Tapping one is
/// how a student jumps from a note to everything else carrying that tag.
class NestTagChips extends StatelessWidget {
  const NestTagChips({
    super.key,
    required this.tags,
    this.onTap,
    this.selected,
    this.dense = false,
  });

  final List<String> tags;
  final void Function(String tag)? onTap;

  /// Drawn as the chosen tag. Used by the tag browser in search.
  final String? selected;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: dense ? 6 : 8,
      runSpacing: dense ? 6 : 8,
      children: [
        for (final tag in tags)
          NestTagChip(
            tag: tag,
            dense: dense,
            active: selected != null && normalizeTag(selected!) == tag,
            onTap: onTap == null ? null : () => onTap!(tag),
          ),
      ],
    );
  }
}

/// One tag label.
class NestTagChip extends StatelessWidget {
  const NestTagChip({
    super.key,
    required this.tag,
    this.onTap,
    this.onRemove,
    this.active = false,
    this.dense = false,
    this.trailingCount,
  });

  final String tag;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool active;
  final bool dense;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    final ink = active ? Colors.white : NestColor.pen;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.fromLTRB(
          dense ? 8 : 10,
          dense ? 4 : 6,
          onRemove != null ? 4 : (dense ? 8 : 10),
          dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: active ? NestColor.pen : NestColor.o(NestColor.pen, 0.08),
          borderRadius: BorderRadius.circular(NestRadius.chip),
          border: Border.all(
            color: active
                ? NestColor.pen
                : NestColor.o(NestColor.pen, 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#',
              style: TextStyle(
                fontFamily: NestFont.mono,
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: NestColor.o(ink, active ? 0.7 : 0.55),
              ),
            ),
            const SizedBox(width: 2),
            Text(
              tag,
              style: TextStyle(
                fontSize: dense ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (trailingCount != null) ...[
              const SizedBox(width: 6),
              Text(
                '$trailingCount',
                style: TextStyle(
                  fontFamily: NestFont.mono,
                  fontSize: dense ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: NestColor.o(ink, 0.6),
                ),
              ),
            ],
            if (onRemove != null) ...[
              const SizedBox(width: 2),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: dense ? 12 : 14,
                    color: NestColor.o(ink, 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Adding and removing a note's tags in the editor. Requirement 6.3.
///
/// Tags already used elsewhere are offered underneath, so a student files the
/// new note under "dbms" rather than inventing "DBMS " a second time.
class NestTagField extends StatefulWidget {
  const NestTagField({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions = const [],
    this.limit = 12,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final int limit;

  @override
  State<NestTagField> createState() => _NestTagFieldState();
}

class _NestTagFieldState extends State<NestTagField> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _full => widget.tags.length >= widget.limit;

  void _add(String raw) {
    final tag = normalizeTag(raw);
    _input.clear();
    setState(() {}); // the "+" button follows whether anything is typed
    if (tag.isEmpty || _full) return;
    if (widget.tags.any((t) => normalizeTag(t) == tag)) return;
    widget.onChanged(normalizeTags([...widget.tags, tag], limit: widget.limit));
  }

  void _remove(String tag) {
    widget.onChanged(
      widget.tags.where((t) => normalizeTag(t) != normalizeTag(tag)).toList(),
    );
  }

  /// A comma is the stored separator, so typing one commits the tag rather
  /// than ending up inside it.
  void _onTyped(String value) {
    if (value.contains(',')) {
      _add(value);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.tags.map(normalizeTag).toSet();
    final offer = widget.suggestions
        .map(normalizeTag)
        .where((t) => t.isNotEmpty && !used.contains(t))
        .take(6)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: NestColor.paper,
            borderRadius: BorderRadius.circular(NestRadius.chip),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in widget.tags)
                      NestTagChip(
                        tag: normalizeTag(tag),
                        dense: true,
                        onRemove: () => _remove(tag),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _input,
                focusNode: _focus,
                enabled: !_full,
                textInputAction: TextInputAction.done,
                onChanged: _onTyped,
                onSubmitted: (v) {
                  _add(v);
                  _focus.requestFocus();
                },
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: _full
                      ? 'Tag limit reached'
                      : widget.tags.isEmpty
                          ? 'Add a tag, e.g. formula'
                          : 'Add another tag',
                  suffixIcon: _input.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: () => _add(_input.text),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (offer.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('ALREADY IN USE', style: nestEyebrow),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in offer)
                NestTagChip(tag: tag, dense: true, onTap: () => _add(tag)),
            ],
          ),
        ],
      ],
    );
  }
}
