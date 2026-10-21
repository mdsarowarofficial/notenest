import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/subject.dart';
import '../theme/nest_theme.dart';
import 'nest_marks.dart';
import '../l10n/strings.dart';

/// A workspace destination in the lower half of the drawer.
class NestDrawerLink {
  const NestDrawerLink({
    required this.id,
    required this.label,
    required this.icon,
    this.badge = 0,
  });

  final String id;
  final String label;
  final IconData icon;
  final int badge;
}

/// The NoteNest drawer, built as a spiral-bound notebook.
///
/// Subjects are index tabs that run off the right edge of the sheet, so the
/// drawer reads as the divider page of a real notebook rather than a list of
/// menu rows.
class NestDrawer extends StatelessWidget {
  const NestDrawer({
    super.key,
    required this.userName,
    required this.semester,
    required this.subjects,
    required this.links,
    required this.selectedId,
    required this.onSelectSubject,
    required this.onSelectLink,
    this.onEditSemester,
    this.onAddSubject,
    this.onOpenProfile,
    this.synced = false,
    this.lastSynced,
    this.userPhoto,
  });

  final String userName;

  /// The account's photo; initials are drawn when null.
  final Uint8List? userPhoto;
  final String semester;
  final List<Subject> subjects;
  final List<NestDrawerLink> links;

  /// Either a subject code or a link id.
  final String selectedId;

  final ValueChanged<Subject> onSelectSubject;
  final ValueChanged<NestDrawerLink> onSelectLink;
  final VoidCallback? onEditSemester;

  /// Opens the new-subject form. Always offered, empty list or not.
  final VoidCallback? onAddSubject;

  /// Opens the account screen from the drawer header.
  final VoidCallback? onOpenProfile;

  /// Whether the last synchronisation succeeded. False until the cloud backend
  /// exists, in which case the footer says so rather than claiming a sync.
  final bool synced;

  /// Overrides the footer text. Leave null to describe [synced].
  final String? lastSynced;

  @override
  Widget build(BuildContext context) {
    final mastered = subjects.isEmpty
        ? 0.0
        : subjects.map((s) => s.mastery).reduce((a, b) => a + b) /
            subjects.length;

    return Drawer(
      width: 308,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: Container(
          color: NestColor.card,
          child: Row(
            children: [
              // Spiral binding.
              Container(
                width: 26,
                color: NestColor.paperDeep,
                child: const CustomPaint(
                  painter: SpiralEdgePainter(),
                  size: Size.infinite,
                ),
              ),
              Expanded(
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, mastered),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 12),
                          children: [
                            _sectionLabel(
                              tr('SUBJECTS'),
                              trailing: subjects.isEmpty
                                  ? null
                                  : '${subjects.length}',
                            ),
                            if (subjects.isEmpty) _emptyHint(context),
                            for (var i = 0; i < subjects.length; i++)
                              _staggered(
                                i,
                                _subjectTab(context, subjects[i]),
                              ),
                            _addSubjectRow(context),
                            const SizedBox(height: 8),
                            _sectionLabel(tr('WORKSPACE')),
                            for (var i = 0; i < links.length; i++)
                              _staggered(
                                subjects.length + i,
                                _linkRow(context, links[i]),
                              ),
                          ],
                        ),
                      ),
                      const PaperRule(),
                      _footer(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context, double mastered) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(NestRadius.chip),
            child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: NestColor.pen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: userPhoto != null
                    ? Image.memory(
                        userPhoto!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Text(
                  _initials(userName),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: ls(0.4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(tr('VIEW PROFILE'), style: nestEyebrow),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: NestColor.inkFaint),
            ],
          ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onEditSemester,
            borderRadius: BorderRadius.circular(NestRadius.chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: NestColor.paper,
                borderRadius: BorderRadius.circular(NestRadius.chip),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_rounded,
                      size: 17, color: NestColor.pen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      semester,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: NestColor.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded,
                      size: 17, color: NestColor.inkFaint),
                ],
              ),
            ),
          ),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(tr('MASTERED'), style: nestEyebrow),
                const Spacer(),
                Text(
                  trp('{0}%', [(mastered * 100).round()]),
                  style: nestEyebrow.copyWith(color: NestColor.pen),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: mastered),
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: NestColor.paperDeep,
                  valueColor: AlwaysStoppedAnimation(NestColor.pen),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- sections

  Widget _sectionLabel(String text, {String? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Row(
          children: [
            Text(text, style: nestEyebrow),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: NestColor.rule)),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing, style: nestEyebrow),
            ],
          ],
        ),
      );

  Widget _subjectTab(BuildContext context, Subject s) {
    final selected = s.code == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelectSubject(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(18, 11, 12, 11),
            decoration: BoxDecoration(
              // The tab runs off the right edge of the page.
              color: selected ? NestColor.o(s.color, 0.28) : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(NestRadius.tab),
                bottomLeft: Radius.circular(NestRadius.tab),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 30,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: NestColor.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(s.code, style: nestEyebrow.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NestColor.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trp('{0}', [s.noteCount]),
                    style: nestEyebrow.copyWith(
                      fontSize: 11,
                      color: NestColor.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkRow(BuildContext context, NestDrawerLink l) {
    final selected = l.id == selectedId;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelectLink(l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 11, 16, 11),
          child: Row(
            children: [
              Icon(
                l.icon,
                size: 20,
                color: selected ? NestColor.pen : NestColor.inkSoft,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Highlighted(
                  active: selected,
                  child: Text(
                    l.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: NestColor.ink,
                    ),
                  ),
                ),
              ),
              if (l.badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: NestColor.redPen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trp('{0}', [l.badge]),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              size: 17,
              color: synced ? NestColor.mint : NestColor.inkFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lastSynced ?? (synced ? tr('Synced') : tr('Not synced yet')),
                overflow: TextOverflow.ellipsis,
                style: nestEyebrow.copyWith(
                  letterSpacing: ls(0.2),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onSelectLink(
                NestDrawerLink(
                  id: 'settings',
                  label: tr('Settings'),
                  icon: Icons.settings_rounded,
                ),
              ),
              icon: Icon(Icons.settings_rounded,
                  size: 20, color: NestColor.inkSoft),
              tooltip: tr('Settings'),
            ),
          ],
        ),
      );

  Widget _addSubjectRow(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onAddSubject,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 26,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.add_rounded, size: 18, color: NestColor.pen),
                const SizedBox(width: 8),
                Text(
                  tr('Add subject'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: NestColor.pen,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _emptyHint(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
        child: Text(
          tr('No subjects yet. Add one to start filing notes.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  /// Rows slide in one after another, like tabs being flipped open.
  Widget _staggered(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 640),
      curve: Interval((index * 0.05).clamp(0.0, 0.6), 1,
          curve: Curves.easeOutCubic),
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(-24 * (1 - t), 0), child: child),
      ),
      child: child,
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'NN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
