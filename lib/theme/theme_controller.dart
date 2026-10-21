import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../l10n/strings.dart';
import 'nest_theme.dart';

/// What the person asked for. "System" follows the phone's own light/dark
/// setting, including when it flips at sunset.
enum ThemeChoice { system, light, dark }

extension ThemeChoiceData on ThemeChoice {
  String get label => switch (this) {
        ThemeChoice.system => tr('System'),
        ThemeChoice.light => tr('Light'),
        ThemeChoice.dark => tr('Dark'),
      };

  static ThemeChoice fromKey(String? key) => ThemeChoice.values.firstWhere(
        (c) => c.name == key,
        orElse: () => ThemeChoice.system,
      );
}

/// Owns light/dark for the whole app.
///
/// The colours are read from [NestColor] at build time rather than looked up
/// through the widget tree, so switching is two steps: point [NestColor] at the
/// other palette, then rebuild every widget that is on screen. Rebuilding only
/// the MaterialApp would repaint the parts that read the Theme and leave the
/// rest in the old colours.
///
/// Device-wide, not per account: it has to be right on the login screen too.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';

  ThemeChoice _choice = ThemeChoice.system;
  ThemeChoice get choice => _choice;

  /// Reads the saved choice and sets the palette. Called before the first
  /// frame, so the app never opens in the wrong colours and then flips.
  Future<void> load() async {
    try {
      final rows = await AppDatabase.instance.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_key],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        _choice = ThemeChoiceData.fromKey(rows.first['value'] as String?);
      }
    } catch (_) {
      // A settings table that cannot be read leaves the app on "system".
    }
    NestColor.use(_resolve());
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> set(ThemeChoice choice) async {
    if (choice == _choice) return;
    _choice = choice;
    await AppDatabase.instance.db.insert(
      'app_settings',
      {'key': _key, 'value': choice.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _apply();
  }

  @override
  void didChangePlatformBrightness() {
    if (_choice == ThemeChoice.system) _apply();
  }

  NestPalette _resolve() {
    final dark = switch (_choice) {
      ThemeChoice.dark => true,
      ThemeChoice.light => false,
      ThemeChoice.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    return dark ? NestPalette.dark : NestPalette.light;
  }

  void _apply() {
    NestColor.use(_resolve());
    notifyListeners();
    // Always, even when the palette did not change: a screen showing the
    // choice itself (Settings) has to redraw to show the new selection.
    rebuildEverything();
  }

}

/// Marks every live element dirty, the same way a hot reload does, so each
/// widget rebuilds and reads the new palette or language.
void rebuildEverything() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
