import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../theme/theme_controller.dart' show rebuildEverything;
import 'bn_strings.dart';

/// The two languages the app speaks. English is what the code is written in;
/// Bangla is a table of translations laid over it.
enum AppLang { en, bn }

extension AppLangData on AppLang {
  /// Each language is named in its own script, so a person who cannot read the
  /// current one can still find theirs.
  String get nativeName => this == AppLang.bn ? 'বাংলা' : 'English';
}

/// Owns the language of the whole app.
///
/// Text is translated where it is built, by [tr] and [trp], so switching works
/// the way the theme does: record the choice, then rebuild every widget on
/// screen. A string with no translation simply stays English, which is the
/// safe failure — a half-translated screen is better than a blank one.
///
/// Device-wide, so the login screen is in the right language too.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();

  static final AppLanguage instance = AppLanguage._();

  static const _key = 'language';

  AppLang _lang = AppLang.en;
  AppLang get lang => _lang;
  bool get isBangla => _lang == AppLang.bn;

  Future<void> load() async {
    try {
      final rows = await AppDatabase.instance.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_key],
        limit: 1,
      );
      if (rows.isNotEmpty && rows.first['value'] == 'bn') _lang = AppLang.bn;
    } catch (_) {
      // Unreadable settings leave the app in English.
    }
  }

  Future<void> set(AppLang lang) async {
    if (lang == _lang) return;
    _lang = lang;
    await AppDatabase.instance.db.insert(
      'app_settings',
      {'key': _key, 'value': lang.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
    rebuildEverything();
  }
}

/// [english], in the current language.
String tr(String english) {
  if (!AppLanguage.instance.isBangla) return english;
  return bnStrings[english] ?? english;
}

/// A sentence with blanks. `trp('Welcome, {0}', [name])` — the translator is
/// free to move the blank, which is why this is not string concatenation:
/// Bangla puts the verb last and the number before the noun.
///
/// Numbers go in as Bangla digits when the language is Bangla.
String trp(String english, List<Object?> args) {
  final bangla = AppLanguage.instance.isBangla;
  final pattern = bangla ? (bnStrings[english] ?? english) : english;
  return pattern.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
    final i = int.parse(m.group(1)!);
    if (i >= args.length) return '';
    final v = args[i];
    final text = '$v';
    return bangla && (v is int || v is double) ? banglaDigits(text) : text;
  });
}

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// 0-9 as ০-৯.
String banglaDigits(String s) =>
    s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _bnDigits[int.parse(m[0]!)]);

/// A count or any other number, written the way the current language writes it.
String num_(int n) => AppLanguage.instance.isBangla ? banglaDigits('$n') : '$n';

const _bnMonths = {
  'january': 'জানুয়ারি', 'february': 'ফেব্রুয়ারি', 'march': 'মার্চ',
  'april': 'এপ্রিল', 'may': 'মে', 'june': 'জুন', 'july': 'জুলাই',
  'august': 'আগস্ট', 'september': 'সেপ্টেম্বর', 'october': 'অক্টোবর',
  'november': 'নভেম্বর', 'december': 'ডিসেম্বর',
  'jan': 'জানু', 'feb': 'ফেব্রু', 'mar': 'মার্চ', 'apr': 'এপ্রিল',
  'jun': 'জুন', 'jul': 'জুলাই', 'aug': 'আগস্ট', 'sep': 'সেপ্টে',
  'oct': 'অক্টো', 'nov': 'নভে', 'dec': 'ডিসে',
  'monday': 'সোমবার', 'tuesday': 'মঙ্গলবার', 'wednesday': 'বুধবার',
  'thursday': 'বৃহস্পতিবার', 'friday': 'শুক্রবার', 'saturday': 'শনিবার',
  'sunday': 'রবিবার',
  'mon': 'সোম', 'tue': 'মঙ্গল', 'wed': 'বুধ', 'thu': 'বৃহঃ',
  'fri': 'শুক্র', 'sat': 'শনি', 'sun': 'রবি',
  'am': 'পূর্বাহ্ণ', 'pm': 'অপরাহ্ণ',
};

final _dateWord = RegExp(
  r'\b(' + _bnMonths.keys.join('|') + r')\b',
  caseSensitive: false,
);

/// A date or time written in English ("Wed, 21 October 2026", "5:30 PM"),
/// written the other way: month and day names in Bangla, digits in Bangla.
/// Unchanged in English. Applied to the finished text so the many places that
/// build a date from parts need only one call each.
String localDate(String s) {
  if (!AppLanguage.instance.isBangla) return s;
  return banglaDigits(
    s.replaceAllMapped(_dateWord, (m) => _bnMonths[m[0]!.toLowerCase()]!),
  );
}

/// Letter-spacing for a heading. The wide tracking that suits capitals breaks
/// Bangla apart: its conjuncts are drawn as one shape, and spreading them
/// leaves gaps in the middle of a letter. So Bangla gets none.
double ls(double english) => AppLanguage.instance.isBangla ? 0 : english;

/// A stored semester label, shown in the current language. The label itself
/// stays English on disk ("Semester 5") because the app reads the number back
/// out of it; only what is drawn on screen is translated.
String shownSemester(String label) {
  final m = RegExp(r'^Semester (\d+)$').firstMatch(label);
  if (m == null) return label;
  return trp('Semester {0}', [int.parse(m[1]!)]);
}
