import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../models/chat.dart';
import '../../models/cloud_profile.dart';
import '../../theme/nest_theme.dart';
import 'chat_page.dart';
import '../../l10n/strings.dart';

String _nameOf(CloudProfile p) => p.name.trim().isEmpty ? p.email : p.name;

/// Opens the conversation with [person], or does the right thing when it
/// cannot be opened yet: offers to send a message request, or says where the
/// request stands. Every "message this person" button goes through here.
Future<void> startConversation(
    BuildContext context, CloudProfile person) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final cloud = CloudService.instance;
  try {
    final chatId = await cloud.openDirectChat(person.uid);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(chatId: chatId, title: _nameOf(person)),
      ),
    );
  } on RequestRequired catch (e) {
    if (!navigator.mounted) return;
    switch (e.kind) {
      case RequestKind.none:
        final sent = await showModalBottomSheet<bool>(
          context: navigator.context,
          isScrollControlled: true,
          backgroundColor: NestColor.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (_) => _RequestSheet(person: person),
        );
        if (sent == true) {
          messenger.showSnackBar(
            SnackBar(content: Text(trp('Request sent to {0}.', [_nameOf(person)]))),
          );
        }
      case RequestKind.toAnswer || RequestKind.declinedByMe:
        await navigator.push(
          MaterialPageRoute(builder: (_) => const MessageRequestsPage()),
        );
      default:
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on CloudException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.person});

  final CloudProfile person;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudService.instance
          .sendMessageRequest(widget.person.uid, _text.text);
      if (mounted) Navigator.pop(context, true);
    } on CloudException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 20, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Message request'), style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              trp('{0} has to accept before you can talk. Say who you are and why you are writing.', [_nameOf(widget.person)]),
              style: t.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: true,
              maxLength: 500,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Your message')),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: NestColor.redPen)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? tr('Sending…') : tr('Send request')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Requests waiting for this account, ones it declined, and ones it sent.
class MessageRequestsPage extends StatelessWidget {
  const MessageRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    return Scaffold(
      backgroundColor: NestColor.paper,
      appBar: AppBar(title: Text(tr('Message requests'))),
      body: StreamBuilder<List<MessageRequest>>(
        stream: cloud.watchIncomingRequests(),
        builder: (context, incomingSnap) =>
            StreamBuilder<List<MessageRequest>>(
          stream: cloud.watchSentRequests(),
          builder: (context, sentSnap) {
            final incoming = (incomingSnap.data ?? const <MessageRequest>[])
                .where((r) => !cloud.isBlocked(r.fromUid))
                .toList();
            final pending = incoming
                .where((r) => r.state == RequestState.pending)
                .toList();
            final declined = incoming
                .where((r) => r.state == RequestState.declined)
                .toList();
            final sent = sentSnap.data ?? const <MessageRequest>[];
            if (!incomingSnap.hasData && !sentSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (pending.isEmpty && declined.isEmpty && sent.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(tr('No message requests.')),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (pending.isNotEmpty) ...[
                  Text(tr('WAITING FOR YOU'), style: nestEyebrow),
                  const SizedBox(height: 8),
                  for (final r in pending)
                    _RequestCard(request: r, incoming: true),
                  const SizedBox(height: 18),
                ],
                if (sent.isNotEmpty) ...[
                  Text(tr('YOU ASKED'), style: nestEyebrow),
                  const SizedBox(height: 8),
                  for (final r in sent)
                    _RequestCard(request: r, incoming: false),
                  const SizedBox(height: 18),
                ],
                if (declined.isNotEmpty) ...[
                  Text(tr('DECLINED'), style: nestEyebrow),
                  const SizedBox(height: 8),
                  for (final r in declined)
                    _RequestCard(request: r, incoming: true),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request, required this.incoming});

  final MessageRequest request;
  final bool incoming;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on CloudException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final r = widget.request;
    final other = r.otherUid(cloud.uid ?? '');
    final t = Theme.of(context).textTheme;

    return FutureBuilder<CloudProfile?>(
      future: cloud.profileFor(other),
      builder: (context, snap) {
        final person = snap.data;
        final name = person == null ? tr('Someone') : _nameOf(person);
        final canAnswer = widget.incoming && r.state != RequestState.accepted;

        String status() {
          if (widget.incoming) {
            return r.state == RequestState.declined ? tr('Declined') : '';
          }
          return switch (r.state) {
            RequestState.pending => tr('Waiting for them to accept'),
            RequestState.accepted => tr('Accepted. Tap to open.'),
            RequestState.declined => tr('Not accepted'),
          };
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: NestColor.card,
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: !widget.incoming &&
                    r.state == RequestState.accepted &&
                    person != null
                ? () => startConversation(context, person)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: t.titleSmall),
                  if (person != null && person.email.isNotEmpty)
                    Text(person.email, style: t.bodySmall),
                  const SizedBox(height: 6),
                  Text(r.text, style: t.bodyMedium),
                  if (status().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(status(), style: t.bodySmall),
                  ],
                  if (canAnswer) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() =>
                                  cloud.respondToRequest(r, accept: true)),
                          child: Text(tr('Accept')),
                        ),
                        const SizedBox(width: 8),
                        if (r.state == RequestState.pending)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() =>
                                    cloud.respondToRequest(r, accept: false)),
                            child: Text(tr('Decline')),
                          ),
                      ],
                    ),
                  ],
                  if (!widget.incoming && r.state == RequestState.pending)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => cloud.withdrawRequest(r)),
                        child: Text(tr('Withdraw')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
