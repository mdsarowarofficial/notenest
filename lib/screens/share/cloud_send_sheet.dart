import 'package:flutter/material.dart';

import '../../data/cloud_service.dart';
import '../../data/note_repository.dart';
import '../../models/cloud_profile.dart';
import '../../models/note.dart';
import '../../models/note_share.dart';
import '../../theme/nest_theme.dart';
import '../chat/chat_page.dart';

/// Sending a note to somebody inside NoteNest, rather than out through a file.
///
/// The difference from the file route is not the destination but the shape of
/// the thing that arrives: a file lands in Downloads and has to be found again,
/// while this lands in their Shared inbox with their name already on it and a
/// choice to accept it. Both carry exactly the same bundle.
Future<void> showCloudSendSheet(BuildContext context, Note note) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CloudSendSheet(note: note),
  );
}

class _CloudSendSheet extends StatefulWidget {
  const _CloudSendSheet({required this.note});

  final Note note;

  @override
  State<_CloudSendSheet> createState() => _CloudSendSheetState();
}

class _CloudSendSheetState extends State<_CloudSendSheet> {
  final _repo = NoteRepository.instance;
  final _cloud = CloudService.instance;

  final _email = TextEditingController();
  final _message = TextEditingController();

  /// What will actually be sent, and what it costs.
  ///
  /// Measured once when the sheet opens rather than at send time, because the
  /// answer decides what the sheet *says* — and a warning that appears after
  /// the button is pressed is not a warning, it is an excuse.
  String? _payloadWithFiles;
  String? _payloadTextOnly;
  int _fileCount = 0;
  int _fileBytes = 0;
  bool _measuring = true;

  CloudProfile? _found;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final withFiles = await _repo.packForSharing(widget.note);
    final textOnly = await _repo.packForSharing(
      widget.note,
      includeFiles: false,
    );
    if (!mounted) return;
    setState(() {
      _payloadWithFiles = withFiles.encode();
      _payloadTextOnly = textOnly.encode();
      _fileCount = withFiles.files.length;
      _fileBytes = withFiles.fileBytes;
      _measuring = false;
    });
  }

  /// The payload that will be sent: with its files when they fit, without them
  /// when they do not.
  String? get _payload {
    final full = _payloadWithFiles;
    if (full != null && sharePayloadFits(full.length)) return full;
    return _payloadTextOnly;
  }

  bool get _filesTravel {
    final full = _payloadWithFiles;
    return _fileCount > 0 && full != null && sharePayloadFits(full.length);
  }

  Future<void> _lookUp() async {
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final person = await _cloud.findByEmail(_email.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _found = person;
        _error = person == null
            ? 'Nobody with that address has a NoteNest cloud account yet. '
                'Check the spelling, or send it as a file instead.'
            : null;
      });
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _send() async {
    final payload = _payload;
    if (payload == null) return;

    final person = _found;
    if (person == null) {
      setState(() => _error = 'Find the person first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // Held before the sheet closes: after the pop this context is gone, and
    // reading a Navigator or a Messenger off it throws.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final sent = await _cloud.sendNote(
        toUids: [person.uid],
        title: widget.note.title,
        payload: payload,
        message: _message.text,
        subjectCode: widget.note.subjectId == null
            ? ''
            : (_repo.subjectById(widget.note.subjectId!)?.code ?? ''),
        fileCount: _filesTravel ? _fileCount : 0,
      );

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sent == 0
                // Sending a group note to a group of one — yourself — is not a
                // failure, but saying "sent" would be a lie.
                ? 'Nobody to send to: you are the only one in that group.'
                : sent == 1
                    ? 'Sent. It is waiting for them to accept.'
                    : 'Sent to $sent people. Each one accepts separately.',
          ),
        ),
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final warning = attachmentWarning(
      fileCount: _fileCount,
      textBytes: _payloadTextOnly?.length ?? 0,
      attachmentBytes: _fileBytes,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: NestColor.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Send inside NoteNest',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '"${widget.note.title}" lands in their Shared inbox. Nothing '
                'is copied into their notebook until they accept it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),

              // Sending to a whole group used to live here too, and it was
              // the wrong place. Posting in the group's conversation shows the
              // note to everyone at once, with no accepting to do — being in
              // the group is already the permission. This sheet is for
              // somebody you share no group with, where the note arrives
              // unasked and a choice is the right thing to offer.
              const _Note(
                colour: NestColor.pen,
                text: 'For a group, post the note in its chat instead — '
                    'everybody sees it straight away and keeps it only if '
                    'they want to.',
              ),
              const SizedBox(height: 18),

              ..._personFields(context),

              const SizedBox(height: 16),
              TextField(
                controller: _message,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'A line with it (optional)',
                  hintText: 'the one from Tuesday',
                  counterText: '',
                ),
              ),

              if (warning != null) ...[
                const SizedBox(height: 14),
                _Note(colour: NestColor.redPen, text: warning),
              ] else if (_filesTravel) ...[
                const SizedBox(height: 14),
                _Note(
                  colour: NestColor.mint,
                  text: 'The $_fileCount '
                      '${_fileCount == 1 ? 'file' : 'files'} '
                      '(${formatBytes(_fileBytes)}) travel with it.',
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                _Note(colour: NestColor.redPen, text: _error!),
              ],

              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy || _measuring || _payload == null
                      ? null
                      : _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _measuring
                        ? 'Measuring…'
                        : _busy
                            ? 'Sending…'
                            : 'Send  ·  ${formatBytes(_payload?.length ?? 0)}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _personFields(BuildContext context) {
    final found = _found;
    return [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Their email',
                hintText: 'classmate@example.com',
              ),
              onSubmitted: (_) => _lookUp(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _busy ? null : _lookUp,
              child: const Text('Find'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        // Explained, because it is a limit people hit and wonder about.
        'The address has to match exactly — NoteNest does not list everybody '
        'who has an account, so there is nobody to browse.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (found != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NestColor.card,
            borderRadius: BorderRadius.circular(NestRadius.tile),
            border: Border.all(color: NestColor.o(NestColor.mint, 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NestColor.o(NestColor.mint, 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  found.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: NestColor.mint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      found.name.trim().isEmpty ? found.email : found.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      found.role.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_rounded, color: NestColor.mint),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Found them, so there is no reason to make them hunt for the same
        // person again under Chats.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _messageInstead(found),
            icon: const Icon(Icons.forum_outlined, size: 17),
            label: const Text('Message them instead'),
          ),
        ),
      ],
    ];
  }

  Future<void> _messageInstead(CloudProfile person) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final chatId = await _cloud.openDirectChat(person.uid);
      if (!mounted) return;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            title: person.name.trim().isEmpty ? person.email : person.name,
          ),
        ),
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: NestColor.o(colour, 0.08),
        borderRadius: BorderRadius.circular(NestRadius.chip),
        border: Border(left: BorderSide(color: colour, width: 3)),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
