import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// NoteNest design tokens — "Soft Depth"
///
/// Every name in this file is used across all 38 screens, so the names are
/// fixed and only the values move. That is the point: one file decides what
/// the whole app looks like, and a screen never hard-codes a colour, a radius
/// or a shadow.
///
/// The idea: a cool paper ground, white surfaces that genuinely sit *above* it
/// on soft shadow, one indigo that carries every action, and one warm yellow
/// that marks the thing you are meant to do next. Large radii throughout, so
/// nothing has a sharp corner except the text.
/// ---------------------------------------------------------------------------
class NestColor {
  NestColor._();

  // Surfaces
  //
  // Two greys, not one. `ground` is the page; `paper` is a well sunk into it —
  // an input, a tag chip, an unselected segment. Having only one grey was the
  // flaw in the first build: a filled text field on a page of its own colour
  // is invisible, so every field needed a border to exist, and the borders put
  // the whole screen back on one flat plane.
  static const ground = Color(0xFFF6F7FB); // the page
  static const paper = Color(0xFFEEF0F6); // a well sunk into the page
  static const paperDeep = Color(0xFFE3E6F0); // pressed
  static const card = Color(0xFFFFFFFF); // a surface above the page
  static const rule = Color(0xFFE4E7F0); // hairline, used sparingly now that
  // depth comes from shadow instead

  // Ink
  static const ink = Color(0xFF1B1E2B);
  static const inkSoft = Color(0xFF5A6076);
  static const inkBody = Color(0xFF6E7489); // body copy inside a card
  static const inkMeta = Color(0xFF8A90A6); // "CSE 112 · 4 min"
  static const inkFaint = Color(0xFF9AA0B4); // a timestamp, an inactive icon

  // Writing instruments
  static const pen = Color(0xFF4A5BD4); // indigo — every primary action
  static const penDeep = Color(0xFF35469E);
  static const penPale = Color(0xFFCBD2F7); // type on top of a pen-filled card
  static const highlight = Color(0xFFFFD84D); // what to do next
  static const redPen = Color(0xFFC42A42); // important / destructive
  static const mint = Color(0xFF17A47A); // done / synced

  /// Soft tints, and the one ink that is readable on each.
  ///
  /// These pairs are the app's colour. A status word, a subject initial, a
  /// tool icon — each sits in its own tint, and those small blocks of colour
  /// are what stop a page of white cards looking like a spreadsheet. Each ink
  /// was picked to clear 4.5:1 against its own tint, so the pairs must be used
  /// together: warm ink on a red tint fails.
  static const tintWarm = Color(0xFFFFF3CF);
  static const warmDeep = Color(0xFF9A7400);
  static const tintMint = Color(0xFFDFF6EC);
  static const mintDeep = Color(0xFF0E7A5A);
  static const tintRed = Color(0xFFFFE3E6);
  static const redDeep = Color(0xFFB01A2A);
  static const tintPen = Color(0xFFE8EBFC);

  /// Index-tab colours for subjects.
  static const tabs = <Color>[
    Color(0xFFFFD84D),
    Color(0xFFFF8FA8),
    Color(0xFF5FD3A3),
    Color(0xFF6FB6F5),
    Color(0xFFB19CF5),
    Color(0xFFFFAD6B),
  ];

  /// Opacity helper that stays valid across Flutter versions.
  static Color o(Color c, double opacity) =>
      c.withAlpha((opacity.clamp(0, 1) * 255).round());
}

/// Typeface roles.
///
/// Bundled as assets rather than fetched, which is not only about speed: the
/// app has already failed once in the field because it could not reach
/// fonts.gstatic.com, and a notebook that works offline cannot depend on a
/// font server to be readable.
///
/// Both families are SIL Open Font License — free to ship.
class NestFont {
  NestFont._();

  /// Outfit — geometric, confident, only used large. Shipped at 600 and 700.
  static const String display = 'Outfit';

  /// Plus Jakarta Sans — open and very legible at the 12–15px this app lives
  /// at. Shipped at 400, 500, 600, 700.
  static const String body = 'PlusJakartaSans';

  /// No separate mono is bundled. The two places that wanted one — the join
  /// code and the countdown — set their own letter spacing instead, which
  /// costs nothing and saves 100 KB.
  static const String mono = 'PlusJakartaSans';
}

class NestRadius {
  NestRadius._();
  static const card = 26.0;
  static const tile = 22.0;
  static const chip = 14.0;
  static const tab = 24.0;

  /// A pill: the floating nav bar, a filter chip, a status badge.
  static const pill = 999.0;
}

/// Three levels of depth, and no more.
///
/// A border says "here is a boundary". A shadow says "this is above that".
/// The app used to say only the first, which is why everything sat on one
/// plane and nothing felt picked up or put down.
///
/// Tinted with the ink colour rather than black: a neutral-black shadow on a
/// cool ground reads as dirt, a tinted one reads as light.
class NestShadow {
  NestShadow._();

  /// A card resting on the page.
  static const resting = <BoxShadow>[
    BoxShadow(
      color: Color(0x141B1E2B),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// Something lifted: a selected card, a tool tile, the primary button.
  static const lifted = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F1B1E2B),
      blurRadius: 30,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x0F1B1E2B),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  /// Floating over everything: the nav bar, a sheet, a dialog.
  static const floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x241B1E2B),
      blurRadius: 34,
      offset: Offset(0, 12),
    ),
  ];

  /// A coloured glow under a filled action, so the primary button looks lit
  /// rather than merely dark.
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: NestColor.o(c, 0.34),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Small uppercase utility labels ("SUBJECTS", note counts, section heads).
const TextStyle nestEyebrow = TextStyle(
  fontFamily: NestFont.body,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.2,
  color: NestColor.inkFaint,
);

ThemeData nestTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NestColor.pen,
    brightness: Brightness.light,
  ).copyWith(
    primary: NestColor.pen,
    onPrimary: Colors.white,
    secondary: NestColor.highlight,
    onSecondary: NestColor.ink,
    surface: NestColor.card,
    onSurface: NestColor.ink,
    error: NestColor.redPen,
  );

  const text = TextTheme(
    displaySmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 31,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      color: NestColor.ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 24,
      height: 1.18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      color: NestColor.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: NestColor.ink,
    ),
    titleSmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 16.5,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: NestColor.ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: NestFont.body,
      fontSize: 14.5,
      height: 1.5,
      color: NestColor.inkSoft,
    ),
    bodySmall: TextStyle(
      fontFamily: NestFont.body,
      fontSize: 12.5,
      height: 1.55,
      color: NestColor.inkBody,
    ),
    labelSmall: nestEyebrow,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    fontFamily: NestFont.body,
    scaffoldBackgroundColor: NestColor.ground,
    splashFactory: InkSparkle.splashFactory,

    dividerTheme: const DividerThemeData(
      color: NestColor.rule,
      thickness: 1,
      space: 1,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: NestColor.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: NestColor.ink),
      titleTextStyle: TextStyle(
        fontFamily: NestFont.display,
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: NestColor.ink,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NestColor.pen,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        ),
        textStyle: const TextStyle(
          fontFamily: NestFont.display,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NestColor.pen,
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: NestColor.rule, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        ),
        textStyle: const TextStyle(
          fontFamily: NestFont.display,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: NestColor.pen,
        textStyle: const TextStyle(
          fontFamily: NestFont.display,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Fields become soft wells rather than underlined lines. This is most of
    // the difference between a form that looks like a form and one that looks
    // designed.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NestColor.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: const BorderSide(color: NestColor.rule, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: const BorderSide(color: NestColor.rule, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: const BorderSide(color: NestColor.pen, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: const BorderSide(color: NestColor.redPen, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: const BorderSide(color: NestColor.redPen, width: 1.8),
      ),
      labelStyle: const TextStyle(
        fontFamily: NestFont.body,
        color: NestColor.inkSoft,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(
        fontFamily: NestFont.body,
        color: NestColor.inkFaint,
        fontSize: 14,
      ),
    ),

    chipTheme: const ChipThemeData(
      backgroundColor: NestColor.card,
      selectedColor: NestColor.pen,
      side: BorderSide(color: NestColor.rule, width: 1.2),
      labelStyle: TextStyle(
        fontFamily: NestFont.body,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: NestColor.inkSoft,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: NestFont.body,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: StadiumBorder(),
      showCheckmark: false,
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NestColor.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: NestColor.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NestRadius.card),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: NestFont.display,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: NestColor.ink,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: NestColor.ink,
      contentTextStyle: const TextStyle(
        fontFamily: NestFont.body,
        fontSize: 13.5,
        height: 1.4,
        color: Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 2),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: NestFont.body,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NestRadius.chip + 2),
          ),
        ),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: NestColor.inkSoft,
      textColor: NestColor.ink,
    ),
  );
}
