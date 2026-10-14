import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../theme/nest_theme.dart';

/// Report and block — the two things Google Play requires an app to offer
/// wherever people can send each other things.
///
/// One sheet, used from a message, a conversation's header and a shared note,
/// so the wording and the behaviour are the same everywhere a student might
/// look for them.
Future<void> showSafetySheet(
  BuildContext context, {
  required String targetUid,
  required String targetName,
  String chatId = '',
  String messageId = '',
  String shareId = '',
  String messageText = '',
}) async {
  final cloud = CloudService.instance;
  if (targetUid.isEmpty || targetUid == cloud.uid) return;
  final name = targetName.trim().isEmpty ? 'this person' : targetName.trim();
  final blocked = cloud.isBlocked(targetUid);

  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: NestColor.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: NestColor.redPen),
              title: Text(messageId.isNotEmpty || shareId.isNotEmpty
                  ? 'Report this'
                  : 'Report $name'),
              subtitle: const Text('Sent to the NoteNest team to review.'),
              onTap: () => Navigator.pop(sheetContext, 'report'),
            ),
            ListTile(
              leading: Icon(
                blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: NestColor.redPen,
              ),
              title: Text(blocked ? 'Unblock $name' : 'Block $name'),
              subtitle: Text(blocked
                  ? 'Their messages and notes will show again.'
                  : 'Hide their messages and notes. They are not told.'),
              onTap: () =>
                  Navigator.pop(sheetContext, blocked ? 'unblock' : 'block'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (choice) {
      case 'report':
        final sent = await _reportDialog(
          context,
          name: name,
          offerBlock: !blocked,
          send: (reason, details, alsoBlock) async {
            await cloud.report(
              targetUid: targetUid,
              reason: reason,
              details: details,
              chatId: chatId,
              messageId: messageId,
              shareId: shareId,
              messageText: messageText,
            );
            if (alsoBlock) await cloud.block(targetUid);
          },
        );
        if (sent) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Thank you. The report has been sent.'),
          ));
        }
      case 'block':
        if (!context.mounted) return;
        if (await confirmBlock(context, name)) {
          await cloud.block(targetUid);
          messenger.showSnackBar(SnackBar(content: Text('$name is blocked.')));
        }
      case 'unblock':
        await cloud.unblock(targetUid);
        messenger.showSnackBar(SnackBar(content: Text('$name is unblocked.')));
    }
  } on CloudException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Says plainly what blocking does before doing it.
Future<bool> confirmBlock(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: NestColor.card,
      title: Text('Block $name?'),
      content: const Text(
        'You will not see their messages, in private or in groups, and notes '
        'they send you will be dropped. They cannot message you privately. '
        'They are not told. You can unblock them from the Cloud screen.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> _reportDialog(
  BuildContext context, {
  required String name,
  required bool offerBlock,
  required Future<void> Function(String reason, String details, bool alsoBlock)
      send,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(name: name, offerBlock: offerBlock, send: send),
  );
  return sent == true;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.name,
    required this.offerBlock,
    required this.send,
  });

  final String name;
  final bool offerBlock;
  final Future<void> Function(String reason, String details, bool alsoBlock)
      send;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  String? _reason;
  bool _alsoBlock = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(reason, _details.text, widget.offerBlock && _alsoBlock);
      if (mounted) Navigator.pop(context, true);
    } on CloudException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: NestColor.card,
      title: const Text('What is wrong?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) {
                if (!_sending) setState(() => _reason = v);
              },
              child: Column(
                children: [
                  for (final entry in CloudService.reportReasons.entries)
                    RadioListTile<String>(
                      value: entry.key,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(entry.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _details,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Anything else we should know (optional)',
              ),
            ),
            if (widget.offerBlock)
              CheckboxListTile(
                value: _alsoBlock,
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Also block ${widget.name}'),
                onChanged: _sending
                    ? null
                    : (v) => setState(() => _alsoBlock = v ?? false),
              ),
            Text(
              'The person is not told who reported them.',
              style: t.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: t.bodySmall?.copyWith(color: NestColor.redPen),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
          onPressed: _sending || _reason == null ? null : _submit,
          child: Text(_sending ? 'Sending…' : 'Send report'),
        ),
      ],
    );
  }
}
