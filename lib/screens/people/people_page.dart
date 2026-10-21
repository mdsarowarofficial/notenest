import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../theme/nest_theme.dart';
import '../chat/chats_page.dart';
import '../classroom/classes_page.dart';
import '../groups/groups_page.dart';
import '../share/request_note_sheet.dart';
import '../shared/shared_page.dart';
import '../../l10n/strings.dart';

/// Everything to do with other people, in one place.
///
/// These three lists used to live apart: Shared was a tab, while Chats and
/// Groups were links behind the drawer and Note requests was a sheet behind a
/// fourth link. They are the same idea seen from three sides — a classmate
/// sends you a note, you ask one for a note, you talk about it — so finding
/// them meant knowing in advance which of the three a thing had been filed
/// under. Here they are three segments of one destination, and the drawer goes
/// back to being a list of places rather than a menu of features.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, this.showClasses = false});

  /// Leads with the student's classes. A teacher has Classes as a tab of its
  /// own, so for them this stays the three social lists.
  final bool showClasses;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  int _segment = 0;

  List<String> get _labels => [
        if (widget.showClasses) 'Classes',
        'Chats',
        'Groups',
        'Shared',
      ];

  /// Which of the three social lists the selected segment is, or -1 for
  /// Classes, so the actions row does not have to know about the offset.
  int get _social => widget.showClasses ? _segment - 1 : _segment;

  @override
  Widget build(BuildContext context) {
    // The role can change under this page, and with it the segment count.
    if (_segment >= _labels.length) _segment = 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: _Segments(
            labels: _labels,
            selected: _segment,
            onPick: (i) => setState(() => _segment = i),
          ),
        ),
        // Classes carries its own button (Join a class) in its header.
        if (_social >= 0) _Actions(segment: _social),
        Expanded(
          // IndexedStack rather than swapping the child, so a thread you have
          // scrolled and a Firestore stream you have opened survive a tap on
          // another segment. Rebuilding them would re-read the collection
          // every time, which on a metered phone connection is rude.
          child: IndexedStack(
            index: _segment,
            children: [
              if (widget.showClasses) const ClassesPage(embedded: true),
              const ChatsPage(embedded: true),
              const GroupsPage(embedded: true),
              const SharedPage(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The three-way switch. Written here rather than with SegmentedButton because
/// the Material one draws a hairline outline and a check mark on the selected
/// segment, and neither belongs in a design where selection is shown by a
/// filled pill.
class _Segments extends StatelessWidget {
  const _Segments({
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.pill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? NestColor.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(NestRadius.pill),
                    boxShadow: i == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x141B1E2B),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 13,
                      fontWeight:
                          i == selected ? FontWeight.w700 : FontWeight.w500,
                      color:
                          i == selected ? NestColor.ink : NestColor.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What you can do on the segment you are looking at.
///
/// A row under the switch rather than a floating button: the nav bar already
/// floats over the bottom-right corner, and a FAB parked there covers a
/// destination — you reach for Exam and start a group instead.
class _Actions extends StatelessWidget {
  const _Actions({required this.segment});

  final int segment;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudService.instance,
      builder: (context, _) {
        // Every action here needs an account, so with none there is nothing
        // to offer; each segment says so in its own words instead.
        if (!CloudService.instance.isSignedIn) {
          return const SizedBox(height: 14);
        }

        final actions = switch (segment) {
          0 => [
              _Action(
                icon: Icons.person_add_alt_1_rounded,
                label: tr('Message someone'),
                onTap: () => showFindPersonSheet(context),
                primary: true,
              ),
            ],
          1 => [
              _Action(
                icon: Icons.login_rounded,
                label: tr('Join'),
                onTap: () => showJoinGroupSheet(context),
              ),
              _Action(
                icon: Icons.add_rounded,
                label: tr('Make one'),
                onTap: () => showCreateGroupSheet(context),
                primary: true,
              ),
            ],
          _ => [
              _Action(
                icon: Icons.pending_actions_rounded,
                label: tr('Ask for a note'),
                onTap: () => showRequestNoteSheet(context),
                primary: true,
              ),
            ],
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
