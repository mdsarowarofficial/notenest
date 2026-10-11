import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../data/share_service.dart';
import '../../theme/nest_theme.dart';

/// Asking a classmate for a note. Requirement 9.3.
///
/// There is no server to deliver a request through, so this writes the message
/// and hands it to whatever app the student already talks to their class in.
/// That is not a workaround — a request that arrives in the group chat the
/// class actually reads gets answered, and one sitting in an app nobody opens
/// does not.
///
/// The message names the subject and topic so the classmate can find the note
/// without a second round of messages.
Future<void> showRequestNoteSheet(BuildContext context, {String? subjectCode}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _RequestSheet(subjectCode: subjectCode),
  );
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({this.subjectCode});

  final String? subjectCode;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _repo = NoteRepository.instance;
  final _topic = TextEditingController();

  int? _subjectId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final subjects = _repo.subjects();
    final named = widget.subjectCode == null
        ? null
        : _repo.subjectByCode(widget.subjectCode!);
    _subjectId = named?.id ?? (subjects.isNotEmpty ? subjects.first.id : null);
    _topic.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  String get _message {
    final subject =
        _subjectId == null ? null : _repo.subjectById(_subjectId!);
    final topic = _topic.text.trim();
    final name = _repo.userName.trim();
    final who = name.isEmpty ? 'A classmate' : name;

    final about = [
      if (subject != null) subject.code,
      if (topic.isNotEmpty) topic,
    ].join(' — ');

    final what = about.isEmpty ? 'your notes' : 'your notes on $about';

    return '$who is asking for $what.\n\n'
        'If you use NoteNest, open the note, tap Share, and send the file '
        'back here.';
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ShareService.shareText(_message);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _repo.subjects();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NestColor.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Ask for a note',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'NoteNest writes the message. You send it wherever your class '
                'already talks.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              if (subjects.isNotEmpty) ...[
                const Text('SUBJECT', style: nestEyebrow),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: NestColor.paper,
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _subjectId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Any subject',
                              style: TextStyle(fontSize: 14)),
                        ),
                        for (final s in subjects)
                          DropdownMenuItem<int?>(
                            value: s.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    s.code,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _subjectId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('TOPIC', style: nestEyebrow),
              const SizedBox(height: 6),
              TextField(
                controller: _topic,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Normalization, or the 12 March class',
                  filled: true,
                  fillColor: NestColor.paper,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('WHAT THEY WILL SEE', style: nestEyebrow),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NestColor.card,
                  borderRadius: BorderRadius.circular(NestRadius.card),
                  border: Border.all(color: NestColor.rule),
                ),
                child: Text(
                  _message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: NestColor.ink,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(_sending ? 'Opening…' : 'Send the request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
