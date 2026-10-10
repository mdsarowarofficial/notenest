import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/subject.dart';
import '../../theme/nest_theme.dart';

/// Add or edit a subject.
///
/// Returns true when something was saved, so the caller can react.
Future<bool> showSubjectForm(BuildContext context, {Subject? existing}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NestColor.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _SubjectForm(existing: existing),
    ),
  );
  return saved ?? false;
}

class _SubjectForm extends StatefulWidget {
  const _SubjectForm({this.existing});

  final Subject? existing;

  @override
  State<_SubjectForm> createState() => _SubjectFormState();
}

class _SubjectFormState extends State<_SubjectForm> {
  final _repo = NoteRepository.instance;
  late final TextEditingController _name;
  late final TextEditingController _code;
  late int _colorIndex;

  String? _nameError;
  String? _codeError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _code = TextEditingController(text: widget.existing?.code ?? '');
    _colorIndex = widget.existing?.colorIndex ?? _repo.nextColorIndex;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Give the subject a name' : null;
      _codeError = code.isEmpty
          ? 'A short code keeps lists readable'
          : _repo.codeExists(code, ignoreId: widget.existing?.id)
              ? 'You already have a subject with this code'
              : null;
    });
    if (_nameError != null || _codeError != null) return;

    setState(() => _saving = true);

    if (widget.existing == null) {
      await _repo.addSubject(name: name, code: code, colorIndex: _colorIndex);
    } else {
      await _repo.updateSubject(
        widget.existing!.copyWith(
          name: name,
          code: code,
          colorIndex: _colorIndex,
        ),
      );
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
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
              editing ? 'Edit subject' : 'New subject',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const Text('SUBJECT NAME', style: nestEyebrow),
            const SizedBox(height: 8),
            _field(
              controller: _name,
              hint: 'Software Engineering',
              error: _nameError,
              capitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            const Text('SUBJECT CODE', style: nestEyebrow),
            const SizedBox(height: 8),
            _field(
              controller: _code,
              hint: 'CSE-3103',
              error: _codeError,
              capitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 18),
            const Text('INDEX TAB COLOUR', style: nestEyebrow),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < NestColor.tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _colorIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: NestColor.tabs[i],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: i == _colorIndex
                                ? NestColor.ink
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: i == _colorIndex
                            ? const Icon(Icons.check_rounded,
                                size: 20, color: NestColor.ink)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Saving...'
                      : editing
                          ? 'Save changes'
                          : 'Add subject',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required String? error,
    required TextCapitalization capitalization,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: capitalization,
      style: const TextStyle(fontSize: 15, color: NestColor.ink),
      decoration: InputDecoration(
        hintText: hint,
        errorText: error,
        filled: true,
        fillColor: NestColor.paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NestRadius.tile),
          borderSide: const BorderSide(color: NestColor.pen, width: 2),
        ),
      ),
    );
  }
}
