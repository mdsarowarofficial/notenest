import 'package:flutter/material.dart';

import '../models/semester.dart';
import '../theme/nest_theme.dart';

/// Choosing a semester: the system first, then the number.
///
/// The system has to come first because it decides how many numbers there are
/// — eight under a bi-semester, twelve under a tri-semester. Offering twelve to
/// everybody would let a student pick a semester their university does not
/// have, and offering eight would stop one who genuinely is in the tenth.
class SemesterPicker extends StatefulWidget {
  const SemesterPicker({
    super.key,
    required this.system,
    required this.label,
    required this.onChanged,
  });

  final SemesterSystem system;

  /// The stored label, such as `Semester 5`.
  final String label;

  final void Function(SemesterSystem system, String label) onChanged;

  @override
  State<SemesterPicker> createState() => _SemesterPickerState();
}

class _SemesterPickerState extends State<SemesterPicker> {
  late SemesterSystem _system = widget.system;
  late int? _number = semesterNumberIn(widget.label);
  late final TextEditingController _custom =
      TextEditingController(text: widget.label);

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _emit() {
    final label = _system == SemesterSystem.custom
        ? _custom.text.trim()
        : (_number == null ? '' : semesterLabelFor(_number!));
    widget.onChanged(_system, label);
  }

  void _pickSystem(SemesterSystem next) {
    setState(() {
      _system = next;
      // A tri-semester 11 is not a bi-semester anything. Dropping a number
      // that no longer exists is better than quietly keeping one the new
      // system cannot offer.
      if (_number != null && !semesterNumberFits(next, _number!)) {
        _number = null;
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('HOW YOUR UNIVERSITY COUNTS', style: nestEyebrow),
        const SizedBox(height: 8),
        for (final system in SemesterSystem.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _system == system
                  ? NestColor.o(NestColor.pen, 0.08)
                  : NestColor.card,
              borderRadius: BorderRadius.circular(NestRadius.tile),
              child: InkWell(
                borderRadius: BorderRadius.circular(NestRadius.tile),
                onTap: () => _pickSystem(system),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      Icon(
                        _system == system
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: _system == system
                            ? NestColor.pen
                            : NestColor.inkFaint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              system.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              system.blurb,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 14),

        if (_system == SemesterSystem.custom)
          TextField(
            controller: _custom,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Your semester',
              hintText: 'Year 2 Term 1',
              counterText: '',
            ),
            onChanged: (_) => _emit(),
          )
        else ...[
          const Text('WHICH ONE ARE YOU IN', style: nestEyebrow),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var n = 1; n <= _system.count; n++)
                ChoiceChip(
                  label: Text('$n'),
                  selected: _number == n,
                  onSelected: (_) {
                    setState(() => _number = n);
                    _emit();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _number == null
                ? 'Pick the one you are in now.'
                : 'Saved as "${semesterLabelFor(_number!)}" — this is what a '
                    'cover page prints.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
