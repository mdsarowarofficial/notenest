/// The cover page: what goes on it, and the rules for the gaps.
///
/// This file holds no widgets and no PDF code on purpose. A cover page is
/// mostly a set of small decisions — what to call the numbered field, what to
/// do when the course title is missing, what the file should be named — and
/// those are easier to argue with and to test when they are plain Dart.
library;

import 'dart:convert';
import '../l10n/strings.dart';

/// What is being handed in. The wording on the page changes with it, and so
/// does what the numbered field is called.
enum CoverKind { assignment, labReport, project, thesis, presentation }

extension CoverKindData on CoverKind {
  String get key => name;

  String get label {
    switch (this) {
      case CoverKind.assignment:
        return tr('Assignment');
      case CoverKind.labReport:
        return tr('Lab Report');
      case CoverKind.project:
        return tr('Project Report');
      case CoverKind.thesis:
        return tr('Thesis');
      case CoverKind.presentation:
        return tr('Presentation');
    }
  }

  /// The big word across the middle of the page.
  String get heading => label.toUpperCase();

  /// What the numbered field is called. A thesis has no number, so the field
  /// is hidden rather than labelled with something invented.
  String? get serialLabel {
    switch (this) {
      case CoverKind.assignment:
        return tr('Assignment No.');
      case CoverKind.labReport:
        return tr('Experiment No.');
      case CoverKind.project:
        return tr('Project No.');
      case CoverKind.presentation:
        return tr('Presentation No.');
      case CoverKind.thesis:
        return null;
    }
  }

  /// What the main free-text line is called.
  String get titleLabel {
    switch (this) {
      case CoverKind.labReport:
        return tr('Experiment name');
      case CoverKind.thesis:
        return tr('Thesis title');
      default:
        return tr('Title');
    }
  }

  static CoverKind fromKey(String? key) {
    for (final k in CoverKind.values) {
      if (k.name == key) return k;
    }
    return CoverKind.assignment;
  }
}

/// How the page is laid out. Four genuinely different arrangements rather
/// than one layout in four colours.
enum CoverTemplate { framed, classic, ruled, crest, minimal }

extension CoverTemplateData on CoverTemplate {
  String get key => name;

  String get label {
    switch (this) {
      case CoverTemplate.framed:
        return tr('Framed');
      case CoverTemplate.classic:
        return tr('Classic');
      case CoverTemplate.ruled:
        return tr('Ruled');
      case CoverTemplate.crest:
        return tr('Crest');
      case CoverTemplate.minimal:
        return tr('Minimal');
    }
  }

  String get note {
    switch (this) {
      case CoverTemplate.framed:
        return tr('Ruled border, logo in the corner, details in panels. The '
            'arrangement most departments here hand out.');
      case CoverTemplate.classic:
        return tr('Centred, double rule, two columns at the bottom. What most '
            'departments expect.');
      case CoverTemplate.ruled:
        return tr('Notebook rules behind the text, in the app\'s own hand.');
      case CoverTemplate.crest:
        return tr('A drawn seal at the top, everything stacked under it.');
      case CoverTemplate.minimal:
        return tr('Left-aligned, one thin rule, a lot of air.');
    }
  }

  static CoverTemplate fromKey(String? key) {
    for (final t in CoverTemplate.values) {
      if (t.name == key) return t;
    }
    return CoverTemplate.framed;
  }
}

/// The accent colours offered for a cover page.
///
/// Deliberately sober — these are the colours of a document that goes to a
/// teacher, not of the app's own interface. Stored as ARGB ints so this file
/// stays free of `dart:ui` and can be tested as plain Dart.
const coverAccents = <int>[
  0xFF243E8C, // ballpoint blue, the app's own
  0xFF16295F, // navy
  0xFF1F8A6B, // deep green
  0xFF8C1C13, // maroon
  0xFF4A3B6B, // plum
  0xFF1A1A1A, // near black, for a photocopier
];

/// How tightly the page is set. The reason this exists: a cover page with
/// four filled fields and a cover page with twelve want different spacing, and
/// a single fixed rhythm leaves the first looking empty and crowds the second.
enum CoverDensity { compact, normal, airy }

extension CoverDensityData on CoverDensity {
  String get key => name;

  String get label {
    switch (this) {
      case CoverDensity.compact:
        return tr('Tight');
      case CoverDensity.normal:
        return tr('Normal');
      case CoverDensity.airy:
        return tr('Airy');
    }
  }

  /// Every gap on the page is multiplied by this.
  double get scale {
    switch (this) {
      case CoverDensity.compact:
        return 0.68;
      case CoverDensity.normal:
        return 1.0;
      case CoverDensity.airy:
        return 1.34;
    }
  }

  static CoverDensity fromKey(String? key) {
    for (final d in CoverDensity.values) {
      if (d.name == key) return d;
    }
    return CoverDensity.normal;
  }
}

/// How the two signature blocks sit against each other.
enum SignatureStyle { staggered, level, stacked }

extension SignatureStyleData on SignatureStyle {
  String get key => name;

  String get label {
    switch (this) {
      case SignatureStyle.staggered:
        return tr('Stepped');
      case SignatureStyle.level:
        return tr('Level');
      case SignatureStyle.stacked:
        return tr('Stacked');
    }
  }

  static SignatureStyle fromKey(String? key) {
    for (final v in SignatureStyle.values) {
      if (v.name == key) return v;
    }
    return SignatureStyle.staggered;
  }
}

/// The border drawn round the page.
enum FrameStyle { dotted, double, hairline, corners, none }

extension FrameStyleData on FrameStyle {
  String get key => name;

  String get label {
    switch (this) {
      case FrameStyle.dotted:
        return tr('Dotted');
      case FrameStyle.double:
        return tr('Double');
      case FrameStyle.hairline:
        return tr('Hairline');
      case FrameStyle.corners:
        return tr('Corners');
      case FrameStyle.none:
        return tr('None');
    }
  }

  static FrameStyle fromKey(String? key) {
    for (final v in FrameStyle.values) {
      if (v.name == key) return v;
    }
    return FrameStyle.dotted;
  }
}

/// One label-and-value row in the "submitted by" and "submitted to" blocks.
class CoverRow {
  const CoverRow(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CoverRow && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

/// Everything that goes on one cover page.
class CoverSpec {
  const CoverSpec({
    this.institution = '',
    this.department = '',
    this.courseCode = '',
    this.courseTitle = '',
    this.kind = CoverKind.assignment,
    this.serial = '',
    this.title = '',
    this.studentName = '',
    this.studentId = '',
    this.program = '',
    this.batch = '',
    this.section = '',
    this.session = '',
    this.teacherName = '',
    this.teacherDesignation = '',
    this.teacherDepartment = '',
    this.teacherInstitution = '',
    this.submittedOn,
    this.template = CoverTemplate.framed,
    this.accentIndex = 0,
    this.customAccent,
    this.showBorder = true,
    this.showWatermark = true,
    this.density = CoverDensity.normal,
    this.signatureStyle = SignatureStyle.staggered,
    this.frameStyle = FrameStyle.dotted,
  });

  final String institution;
  final String department;
  final String courseCode;
  final String courseTitle;
  final CoverKind kind;
  final String serial;
  final String title;

  final String studentName;
  final String studentId;
  final String program;
  final String batch;
  final String section;
  final String session;

  final String teacherName;
  final String teacherDesignation;
  final String teacherDepartment;

  /// The teacher's own institution. Usually the same as the student's, but not
  /// always — a visiting examiner belongs somewhere else, and the cover page
  /// should be able to say so.
  final String teacherInstitution;

  final DateTime? submittedOn;

  final CoverTemplate template;
  final int accentIndex;

  /// A colour the student mixed themselves, as ARGB. Null means one of the
  /// six curated accents is in use instead.
  final int? customAccent;

  final bool showBorder;

  /// Whether the logo is also drawn large and faint behind the text.
  final bool showWatermark;

  final CoverDensity density;
  final SignatureStyle signatureStyle;
  final FrameStyle frameStyle;

  /// A mixed colour wins over the swatch, because choosing one is the later
  /// and more deliberate act.
  int get accent =>
      customAccent ?? coverAccents[accentIndex % coverAccents.length];

  CoverSpec copyWith({
    String? institution,
    String? department,
    String? courseCode,
    String? courseTitle,
    CoverKind? kind,
    String? serial,
    String? title,
    String? studentName,
    String? studentId,
    String? program,
    String? batch,
    String? section,
    String? session,
    String? teacherName,
    String? teacherDesignation,
    String? teacherDepartment,
    String? teacherInstitution,
    DateTime? submittedOn,
    /// Passing `submittedOn: null` cannot clear the date — null is also what
    /// "leave it alone" looks like to copyWith. This flag is the only way to
    /// take a date off a cover page.
    bool clearDate = false,
    CoverTemplate? template,
    int? accentIndex,
    int? customAccent,
    bool clearCustomAccent = false,
    bool? showBorder,
    bool? showWatermark,
    CoverDensity? density,
    SignatureStyle? signatureStyle,
    FrameStyle? frameStyle,
  }) =>
      CoverSpec(
        institution: institution ?? this.institution,
        department: department ?? this.department,
        courseCode: courseCode ?? this.courseCode,
        courseTitle: courseTitle ?? this.courseTitle,
        kind: kind ?? this.kind,
        serial: serial ?? this.serial,
        title: title ?? this.title,
        studentName: studentName ?? this.studentName,
        studentId: studentId ?? this.studentId,
        program: program ?? this.program,
        batch: batch ?? this.batch,
        section: section ?? this.section,
        session: session ?? this.session,
        teacherName: teacherName ?? this.teacherName,
        teacherDesignation: teacherDesignation ?? this.teacherDesignation,
        teacherDepartment: teacherDepartment ?? this.teacherDepartment,
        teacherInstitution: teacherInstitution ?? this.teacherInstitution,
        submittedOn: clearDate ? null : (submittedOn ?? this.submittedOn),
        template: template ?? this.template,
        accentIndex: accentIndex ?? this.accentIndex,
        customAccent:
            clearCustomAccent ? null : (customAccent ?? this.customAccent),
        showBorder: showBorder ?? this.showBorder,
        showWatermark: showWatermark ?? this.showWatermark,
        density: density ?? this.density,
        signatureStyle: signatureStyle ?? this.signatureStyle,
        frameStyle: frameStyle ?? this.frameStyle,
      );

  /// "CSE 112 — Data Structures", or whichever half of it exists.
  ///
  /// An em dash with nothing on one side of it looks like a mistake, so the
  /// separator only appears when there is something to separate.
  String get courseLine {
    final code = courseCode.trim();
    final name = courseTitle.trim();
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code — $name';
  }

  /// The numbered line, when this kind has one and it is filled in.
  String? get serialLine {
    final label = kind.serialLabel;
    final value = serial.trim();
    if (label == null || value.isEmpty) return null;
    return '$label $value';
  }

  List<CoverRow> get submittedBy => [
        if (studentName.trim().isNotEmpty) CoverRow('Name', studentName.trim()),
        if (studentId.trim().isNotEmpty) CoverRow('ID', studentId.trim()),
        if (program.trim().isNotEmpty) CoverRow('Program', program.trim()),
        if (batch.trim().isNotEmpty) CoverRow('Batch', batch.trim()),
        if (section.trim().isNotEmpty) CoverRow('Section', section.trim()),
        if (session.trim().isNotEmpty) CoverRow('Session', session.trim()),
      ];

  List<CoverRow> get submittedTo => [
        if (teacherName.trim().isNotEmpty) CoverRow('Name', teacherName.trim()),
        if (teacherDesignation.trim().isNotEmpty)
          CoverRow('Designation', teacherDesignation.trim()),
        if (teacherDepartment.trim().isNotEmpty)
          CoverRow('Department', teacherDepartment.trim()),
        if (teacherInstitution.trim().isNotEmpty)
          CoverRow('Institution', teacherInstitution.trim()),
      ];

  /// The fields a teacher would notice were missing, in the order the form
  /// asks for them.
  ///
  /// This is a prompt, not a gate — a cover page with gaps still exports. A
  /// student who wants to write the date by hand should be allowed to.
  List<String> get missing => [
        if (institution.trim().isEmpty) 'Institution',
        if (courseCode.trim().isEmpty && courseTitle.trim().isEmpty) 'Course',
        if (title.trim().isEmpty) kind.titleLabel,
        if (studentName.trim().isEmpty) 'Your name',
        if (studentId.trim().isEmpty) 'Your ID',
        if (teacherName.trim().isEmpty) 'Submitted to',
      ];

  bool get isComplete => missing.isEmpty;

  /// "CSE112-assignment-3.pdf", falling back as pieces go missing.
  String get suggestedFileName {
    final parts = <String>[
      if (courseCode.trim().isNotEmpty) courseCode,
      kind.label.toLowerCase().replaceAll(' ', '-'),
      if (serial.trim().isNotEmpty) serial,
    ];
    final stem = _safeFileStem(parts.join('-'));
    return '${stem.isEmpty ? 'cover-page' : stem}.pdf';
  }

  /// The settings store holds one string, so the draft travels as JSON.
  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => {
        'institution': institution,
        'department': department,
        'courseCode': courseCode,
        'courseTitle': courseTitle,
        'kind': kind.key,
        'serial': serial,
        'title': title,
        'studentName': studentName,
        'studentId': studentId,
        'program': program,
        'batch': batch,
        'section': section,
        'session': session,
        'teacherName': teacherName,
        'teacherDesignation': teacherDesignation,
        'teacherDepartment': teacherDepartment,
        'teacherInstitution': teacherInstitution,
        'submittedOn': submittedOn?.millisecondsSinceEpoch,
        'template': template.key,
        'accentIndex': accentIndex,
        'customAccent': customAccent,
        'showBorder': showBorder,
        'showWatermark': showWatermark,
        'density': density.key,
        'signatureStyle': signatureStyle.key,
        'frameStyle': frameStyle.key,
      };

  /// Never throws. A draft is a convenience; a corrupt one should hand back an
  /// empty form rather than take the screen down with it.
  static CoverSpec decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const CoverSpec();
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const CoverSpec();
      return CoverSpec.fromJson(data.cast<String, Object?>());
    } catch (_) {
      return const CoverSpec();
    }
  }

  factory CoverSpec.fromJson(Map<String, Object?> m) {
    String text(String key) {
      final v = m[key];
      return v is String ? v : '';
    }

    final on = m['submittedOn'];
    final accent = m['accentIndex'];

    return CoverSpec(
      institution: text('institution'),
      department: text('department'),
      courseCode: text('courseCode'),
      courseTitle: text('courseTitle'),
      kind: CoverKindData.fromKey(m['kind'] as String?),
      serial: text('serial'),
      title: text('title'),
      studentName: text('studentName'),
      studentId: text('studentId'),
      program: text('program'),
      batch: text('batch'),
      section: text('section'),
      session: text('session'),
      teacherName: text('teacherName'),
      teacherDesignation: text('teacherDesignation'),
      teacherDepartment: text('teacherDepartment'),
      teacherInstitution: text('teacherInstitution'),
      submittedOn:
          on is int ? DateTime.fromMillisecondsSinceEpoch(on) : null,
      template: CoverTemplateData.fromKey(m['template'] as String?),
      accentIndex: accent is int ? accent : 0,
      customAccent: m['customAccent'] is int ? m['customAccent'] as int : null,
      showBorder: m['showBorder'] != false,
      showWatermark: m['showWatermark'] != false,
      density: CoverDensityData.fromKey(m['density'] as String?),
      signatureStyle:
          SignatureStyleData.fromKey(m['signatureStyle'] as String?),
      frameStyle: FrameStyleData.fromKey(m['frameStyle'] as String?),
    );
  }

  /// What carries over to the next cover page the student makes.
  ///
  /// The institution, the department, their own name and ID do not change
  /// between assignments; the title and the number do. Carrying everything
  /// over would mean handing in last week's title by accident.
  CoverSpec get asNextDraft => copyWith(
        serial: '',
        title: '',
        clearDate: true,
      );
}

/// A printable accent colour from a hue on the wheel, as ARGB.
///
/// The saturation and brightness are fixed rather than offered as two more
/// sliders. A cover page is printed, and fully saturated colour at full
/// brightness prints as a muddy stripe on a laser printer while very pale
/// colour disappears into the paper. Holding both at values that survive
/// toner means every hue the student can pick is one that will actually come
/// out — the choice is wide, and none of it is a trap.
///
/// Written out by hand rather than through `HSVColor`, so this file stays
/// plain Dart and the conversion can be tested on its own.
int argbFromHue(double hue) {
  final h = ((hue % 360) + 360) % 360;
  const saturation = 0.72;
  const value = 0.58;

  // Both operands are compile-time constants, so these are too. `x` is not:
  // it depends on the hue that was passed in.
  const c = value * saturation;
  const m = value - c;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());

  double r = 0;
  double g = 0;
  double b = 0;
  if (h < 60) {
    r = c;
    g = x;
  } else if (h < 120) {
    r = x;
    g = c;
  } else if (h < 180) {
    g = c;
    b = x;
  } else if (h < 240) {
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }

  int channel(double raw) => (((raw + m) * 255).round()).clamp(0, 255);
  return 0xFF000000 | (channel(r) << 16) | (channel(g) << 8) | channel(b);
}

/// Strips a string down to something safe to use as a file name.
String _safeFileStem(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
}

/// "12 October 2026". No weekday — a submission date is a date, and the
/// weekday is noise on a cover page.
String coverDateLabel(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
