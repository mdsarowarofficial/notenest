import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/brand_store.dart';
import '../../data/note_repository.dart';
import '../../models/cover_spec.dart';
import '../../theme/nest_theme.dart';
import 'university_picker.dart';

/// The controls under the cover page preview.
///
/// Fields are declared as data rather than written out one by one, because
/// there are sixteen of them and the labels change with what is being handed
/// in — a lab report asks for an "Experiment name" where an assignment asks
/// for a "Title". Declaring them means that logic lives in one place instead
/// of being spread across sixteen copies of the same widget.
class CoverForm extends StatefulWidget {
  const CoverForm({
    super.key,
    required this.spec,
    required this.onChanged,
  });

  final CoverSpec spec;
  final ValueChanged<CoverSpec> onChanged;

  @override
  State<CoverForm> createState() => _CoverFormState();
}

class _Field {
  const _Field({
    required this.id,
    required this.label,
    required this.read,
    required this.write,
    this.hint,
    this.capitalize = TextCapitalization.words,
    this.wide = true,
  });

  final String id;
  final String label;
  final String? hint;
  final String Function(CoverSpec) read;
  final CoverSpec Function(CoverSpec, String) write;
  final TextCapitalization capitalize;

  /// False puts the field in a row beside its neighbour.
  final bool wide;
}

class _CoverFormState extends State<CoverForm> {
  final _controllers = <String, TextEditingController>{};
  final _repo = NoteRepository.instance;

  bool _pickingLogo = false;
  String? _logoError;

  /// Where the mix-your-own slider sits. Kept in the widget rather than the
  /// spec because the spec stores the resulting colour, and two hues can
  /// produce colours close enough that reversing the sum would make the
  /// slider jump under the student's thumb.
  double _hue = 220;
  bool _mixing = false;

  /// Every field in the order the form asks for them. The ids are stable so a
  /// controller keeps its text when the labels change with the kind.
  static final _fields = <_Field>[
    _Field(
      id: 'institution',
      label: 'Institution',
      hint: 'Daffodil International University',
      read: (s) => s.institution,
      write: (s, v) => s.copyWith(institution: v),
    ),
    _Field(
      id: 'department',
      label: 'Department or faculty',
      hint: 'Department of Computer Science and Engineering',
      read: (s) => s.department,
      write: (s, v) => s.copyWith(department: v),
    ),
    _Field(
      id: 'courseCode',
      label: 'Course code',
      hint: 'CSE 112',
      read: (s) => s.courseCode,
      write: (s, v) => s.copyWith(courseCode: v),
      capitalize: TextCapitalization.characters,
      wide: false,
    ),
    _Field(
      id: 'courseTitle',
      label: 'Course title',
      hint: 'Data Structures',
      read: (s) => s.courseTitle,
      write: (s, v) => s.copyWith(courseTitle: v),
      wide: false,
    ),
    _Field(
      id: 'studentName',
      label: 'Your name',
      read: (s) => s.studentName,
      write: (s, v) => s.copyWith(studentName: v),
    ),
    _Field(
      id: 'studentId',
      label: 'Your ID',
      hint: '221-15-1234',
      read: (s) => s.studentId,
      write: (s, v) => s.copyWith(studentId: v),
      capitalize: TextCapitalization.characters,
      wide: false,
    ),
    _Field(
      id: 'program',
      label: 'Program',
      hint: 'BSc in CSE',
      read: (s) => s.program,
      write: (s, v) => s.copyWith(program: v),
    ),
    _Field(
      id: 'batch',
      label: 'Batch',
      hint: '63rd',
      read: (s) => s.batch,
      write: (s, v) => s.copyWith(batch: v),
      wide: false,
    ),
    _Field(
      id: 'section',
      label: 'Section',
      hint: 'B',
      read: (s) => s.section,
      write: (s, v) => s.copyWith(section: v),
      capitalize: TextCapitalization.characters,
      wide: false,
    ),
    _Field(
      id: 'session',
      label: 'Session or semester',
      hint: 'Spring 2026',
      read: (s) => s.session,
      write: (s, v) => s.copyWith(session: v),
    ),
    _Field(
      id: 'teacherName',
      label: 'Teacher\'s name',
      read: (s) => s.teacherName,
      write: (s, v) => s.copyWith(teacherName: v),
    ),
    _Field(
      id: 'teacherDesignation',
      label: 'Designation',
      hint: 'Assistant Professor',
      read: (s) => s.teacherDesignation,
      write: (s, v) => s.copyWith(teacherDesignation: v),
    ),
    _Field(
      id: 'teacherDepartment',
      label: 'Their department',
      read: (s) => s.teacherDepartment,
      write: (s, v) => s.copyWith(teacherDepartment: v),
    ),
    _Field(
      id: 'teacherInstitution',
      label: 'Their institution',
      read: (s) => s.teacherInstitution,
      write: (s, v) => s.copyWith(teacherInstitution: v),
    ),
  ];

  TextEditingController _controllerFor(_Field field) {
    return _controllers.putIfAbsent(field.id, () {
      final c = TextEditingController(text: field.read(widget.spec));
      c.addListener(() => widget.onChanged(field.write(widget.spec, c.text)));
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the institution from the bundled list.
  ///
  /// The controller's text is set rather than the spec alone, so the field the
  /// student is looking at agrees with the page — and because setting the text
  /// runs the same listener a keystroke would, there is one path into the spec
  /// instead of two.
  Future<void> _findUniversity() async {
    final picked = await showUniversityPicker(context);
    if (picked == null || !mounted) return;
    final controller = _controllers['institution'];
    if (controller != null) {
      controller.text = picked.name;
    } else {
      widget.onChanged(widget.spec.copyWith(institution: picked.name));
    }
  }

  Widget _findUniversityButton() {
    return OutlinedButton.icon(
      onPressed: _findUniversity,
      icon: const Icon(Icons.travel_explore_rounded, size: 18),
      label: const Text('Find my university'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
    );
  }

  Future<void> _pickLogo() async {
    if (_pickingLogo) return;
    setState(() {
      _pickingLogo = true;
      _logoError = null;
    });
    try {
      final png = await BrandStore.pickLogo();
      if (!mounted) return;
      if (png == null) {
        setState(() => _pickingLogo = false);
        return;
      }
      await _repo.saveBrandLogo(png);
      if (mounted) setState(() => _pickingLogo = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _pickingLogo = false;
          _logoError = 'That file could not be read as an image. '
              'A PNG with a transparent background looks best.';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.spec.submittedOn ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null) {
      widget.onChanged(widget.spec.copyWith(submittedOn: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final serialLabel = spec.kind.serialLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------ what and how
        const Text('WHAT ARE YOU HANDING IN', style: nestEyebrow),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in CoverKind.values)
              _Chip(
                label: kind.label,
                selected: spec.kind == kind,
                onTap: () => widget.onChanged(spec.copyWith(kind: kind)),
              ),
          ],
        ),
        const SizedBox(height: 18),

        _TextField(
          label: spec.kind.titleLabel,
          hint: spec.kind == CoverKind.labReport
              ? 'Verification of Ohm\'s Law'
              : 'Sorting algorithms compared',
          controller: _titleController,
        ),

        if (serialLabel != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 150,
            child: _TextField(
              label: serialLabel,
              hint: '3',
              controller: _serialController,
              capitalize: TextCapitalization.none,
            ),
          ),
        ],

        const SizedBox(height: 18),
        const Text('LOOK', style: nestEyebrow),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in CoverTemplate.values)
              _Chip(
                label: t.label,
                selected: spec.template == t,
                onTap: () => widget.onChanged(spec.copyWith(template: t)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          spec.template.note,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < coverAccents.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _Swatch(
                  color: Color(coverAccents[i]),
                  // A mixed colour outranks the swatches, so while one is in
                  // use no swatch should look chosen.
                  selected: spec.customAccent == null &&
                      spec.accentIndex % coverAccents.length == i,
                  onTap: () => widget.onChanged(
                    spec.copyWith(accentIndex: i, clearCustomAccent: true),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _OptionRow(
          label: 'Mix your own',
          selected: _mixing,
          onTap: () => setState(() => _mixing = !_mixing),
        ),
        if (_mixing) ...[
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _hue,
                  min: 0,
                  max: 359,
                  onChanged: (v) {
                    setState(() => _hue = v);
                    widget.onChanged(
                      spec.copyWith(customAccent: argbFromHue(v)),
                    );
                  },
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(argbFromHue(_hue)),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          if (spec.customAccent != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.onChanged(
                  spec.copyWith(clearCustomAccent: true),
                ),
                child: const Text('Back to the swatches'),
              ),
            ),
        ],

        if (spec.template == CoverTemplate.framed) ...[
          const SizedBox(height: 14),
          const Text('SPACING', style: nestEyebrow),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in CoverDensity.values)
                _Chip(
                  label: d.label,
                  selected: spec.density == d,
                  onTap: () => widget.onChanged(spec.copyWith(density: d)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('SIGNATURE BLOCKS', style: nestEyebrow),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in SignatureStyle.values)
                _Chip(
                  label: v.label,
                  selected: spec.signatureStyle == v,
                  onTap: () =>
                      widget.onChanged(spec.copyWith(signatureStyle: v)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('BORDER', style: nestEyebrow),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in FrameStyle.values)
                _Chip(
                  label: f.label,
                  selected: spec.frameStyle == f,
                  onTap: () => widget.onChanged(spec.copyWith(frameStyle: f)),
                ),
            ],
          ),
        ],

        if (spec.template == CoverTemplate.classic ||
            spec.template == CoverTemplate.framed) ...[
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            value: spec.showBorder,
            onChanged: (v) => widget.onChanged(spec.copyWith(showBorder: v)),
            contentPadding: EdgeInsets.zero,
            title: const Text('Border around the page',
                style: TextStyle(fontSize: 14)),
          ),
        ],

        const SizedBox(height: 12),
        const Text('YOUR LOGO', style: nestEyebrow),
        const SizedBox(height: 8),
        _LogoTile(
          logo: _repo.brandLogo,
          busy: _pickingLogo,
          onPick: _pickLogo,
          onRemove: () => _repo.saveBrandLogo(null),
        ),
        if (_logoError != null) ...[
          const SizedBox(height: 6),
          Text(
            _logoError!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NestColor.redPen),
          ),
        ],
        if (_repo.brandLogo != null) ...[
          SwitchListTile.adaptive(
            value: spec.showWatermark,
            onChanged: (v) => widget.onChanged(spec.copyWith(showWatermark: v)),
            contentPadding: EdgeInsets.zero,
            title: const Text('Faded watermark behind the text',
                style: TextStyle(fontSize: 14)),
          ),
        ],

        const SizedBox(height: 12),
        const Text('DATE OF SUBMISSION', style: nestEyebrow),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(NestRadius.chip),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: NestColor.paper,
              borderRadius: BorderRadius.circular(NestRadius.chip),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_rounded, size: 18, color: NestColor.pen),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    spec.submittedOn == null
                        ? 'Not shown on the page'
                        : coverDateLabel(spec.submittedOn!),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (spec.submittedOn != null)
                  TextButton(
                    onPressed: () =>
                        widget.onChanged(spec.copyWith(clearDate: true)),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ),

        // ------------------------------------------------- the typed fields
        ..._group(
          'WHERE YOU STUDY',
          ['institution', 'department'],
          trailing: _findUniversityButton(),
        ),
        ..._group('THE COURSE', ['courseCode', 'courseTitle']),
        ..._group('SUBMITTED BY', [
          'studentName',
          'studentId',
          'program',
          'batch',
          'section',
          'session',
        ]),
        ..._group('SUBMITTED TO', [
          'teacherName',
          'teacherDesignation',
          'teacherDepartment',
          'teacherInstitution',
        ]),
      ],
    );
  }

  TextEditingController get _titleController => _controllers.putIfAbsent(
        'title',
        () {
          final c = TextEditingController(text: widget.spec.title);
          c.addListener(
            () => widget.onChanged(widget.spec.copyWith(title: c.text)),
          );
          return c;
        },
      );

  TextEditingController get _serialController => _controllers.putIfAbsent(
        'serial',
        () {
          final c = TextEditingController(text: widget.spec.serial);
          c.addListener(
            () => widget.onChanged(widget.spec.copyWith(serial: c.text)),
          );
          return c;
        },
      );

  /// Builds one headed group. Narrow fields are paired onto one row, which
  /// keeps a course code from taking a whole line to itself.
  List<Widget> _group(String heading, List<String> ids, {Widget? trailing}) {
    final fields = [
      for (final id in ids) _fields.firstWhere((f) => f.id == id),
    ];

    final rows = <Widget>[];
    var i = 0;
    while (i < fields.length) {
      final field = fields[i];
      final next = i + 1 < fields.length ? fields[i + 1] : null;

      if (!field.wide && next != null && !next.wide) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _fieldWidget(field)),
            const SizedBox(width: 12),
            Expanded(child: _fieldWidget(next)),
          ],
        ));
        i += 2;
      } else {
        rows.add(_fieldWidget(field));
        i += 1;
      }
      rows.add(const SizedBox(height: 12));
    }

    return [
      const SizedBox(height: 10),
      Text(heading, style: nestEyebrow),
      const SizedBox(height: 10),
      if (trailing != null) ...[trailing, const SizedBox(height: 12)],
      ...rows,
    ];
  }

  Widget _fieldWidget(_Field field) => _TextField(
        label: field.label,
        hint: field.hint,
        controller: _controllerFor(field),
        capitalize: field.capitalize,
      );
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.hint,
    this.capitalize = TextCapitalization.words,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final TextCapitalization capitalize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: NestColor.inkSoft,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          textCapitalization: capitalize,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: NestColor.paper,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NestRadius.chip),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? NestColor.tintPen : NestColor.paper,
          borderRadius: BorderRadius.circular(NestRadius.tile),
          boxShadow:
              selected ? NestShadow.glow(NestColor.pen) : const <BoxShadow>[],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: NestColor.ink,
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? NestColor.ink : Colors.transparent,
            width: 2.2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

/// The logo slot: pick one once, and it appears on every cover page after.
class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.logo,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? logo;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mark = logo;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: NestColor.card,
              borderRadius: BorderRadius.circular(NestRadius.chip),
              boxShadow: NestShadow.resting,
            ),
            child: mark == null
                ? const Icon(Icons.school_outlined,
                    size: 22, color: NestColor.inkFaint)
                : Image.memory(mark, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mark == null ? 'No logo yet' : 'Logo set',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  mark == null
                      // Said plainly, because "why doesn't it know my
                      // university's logo?" is the obvious question.
                      ? 'Logos belong to the universities, so the app cannot '
                          'ship them. Add yours once and it goes on every '
                          'cover page from now on.'
                      : 'Used in the corner and, faded, as the watermark.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onPick,
                  icon: Icon(
                    mark == null ? Icons.add_rounded : Icons.edit_outlined,
                    size: 19,
                  ),
                  tooltip: mark == null ? 'Add a logo' : 'Change it',
                ),
                if (mark != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    color: NestColor.redPen,
                    tooltip: 'Remove',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A one-line toggle used where a chip would look lonely.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NestRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 20,
              color: NestColor.pen,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NestColor.pen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
