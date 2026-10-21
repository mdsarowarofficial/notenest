import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../models/user_account.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';
import 'login_page.dart';
import '../../l10n/strings.dart';

/// Signing out and switching accounts, shared by Settings and the profile.
///
/// Switching is a sign out followed by a sign in, said honestly. Each account
/// on the phone keeps its own notes, and the next one still has to prove who
/// it is — a switcher that skipped the password would let anybody holding an
/// unlocked phone walk into every account that had ever used it.

/// Asks, then signs out and returns to the login screen.
Future<void> confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: NestColor.card,
      title: Text(tr('Sign out?')),
      content: Text(
        tr('Your notes stay on this device. You can sign back in any time.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(tr('Sign out')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _leaveFor(context, null);
}

/// Lists the other accounts on this phone and moves to the chosen one.
Future<void> showAccountSwitcher(BuildContext context) async {
  final auth = AuthRepository.instance;
  final me = auth.currentUser;
  final others = (await auth.deviceAccounts())
      .where((a) => a.id != me?.id)
      .toList();
  if (!context.mounted) return;

  // A record rather than a bare string, so "use another account" (no address)
  // and "dismissed" (null) are not the same answer.
  final picked = await showModalBottomSheet<({String? email})>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(tr('SWITCH ACCOUNT'), style: nestEyebrow),
            ),
            if (me != null)
              _AccountTile(
                account: me,
                trailing: Icon(Icons.check_circle_rounded,
                    color: NestColor.mint),
                subtitle: tr('Signed in now'),
              ),
            for (final a in others)
              _AccountTile(
                account: a,
                subtitle: a.email,
                onTap: () => Navigator.pop(sheetContext, (email: a.email)),
              ),
            const Divider(height: 18),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: NestColor.tintPen,
                child: Icon(Icons.person_add_alt_1_rounded,
                    color: NestColor.pen, size: 20),
              ),
              title: Text(tr('Use another account')),
              subtitle: Text(tr('Sign in, or make a new one')),
              onTap: () => Navigator.pop(sheetContext, (email: null)),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await _leaveFor(context, picked.email);
}

Future<void> _leaveFor(BuildContext context, String? email) async {
  final navigator = Navigator.of(context);
  await AuthRepository.instance.signOut();
  NoteRepository.instance.clear();
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LoginPage(initialEmail: email)),
    (route) => false,
  );
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final UserAccount account;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: InitialsTile(name: account.name, size: 40),
      title: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, color: NestColor.inkFaint),
      onTap: onTap,
    );
  }
}
