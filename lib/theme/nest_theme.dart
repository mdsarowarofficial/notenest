import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/strings.dart';

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
/// One complete set of colours. The app has two, and [NestColor] reads from
/// whichever is in use, so a screen asks for `NestColor.card` and gets white by
/// day and a deep blue-grey by night without knowing which.
class NestPalette {
  const NestPalette({
    required this.brightness,
    required this.ground,
    required this.paper,
    required this.paperDeep,
    required this.card,
    required this.rule,
    required this.ink,
    required this.inkSoft,
    required this.inkBody,
    required this.inkMeta,
    required this.inkFaint,
    required this.pen,
    required this.penDeep,
    required this.penPale,
    required this.highlight,
    required this.redPen,
    required this.mint,
    required this.tintWarm,
    required this.warmDeep,
    required this.tintMint,
    required this.mintDeep,
    required this.tintRed,
    required this.redDeep,
    required this.tintPen,
  });

  final Brightness brightness;
  final Color ground, paper, paperDeep, card, rule;
  final Color ink, inkSoft, inkBody, inkMeta, inkFaint;
  final Color pen, penDeep, penPale, highlight, redPen, mint;
  final Color tintWarm, warmDeep, tintMint, mintDeep, tintRed, redDeep, tintPen;

  static const light = NestPalette(
    brightness: Brightness.light,
    ground: Color(0xFFF6F7FB),
    paper: Color(0xFFEEF0F6),
    paperDeep: Color(0xFFE3E6F0),
    card: Color(0xFFFFFFFF),
    rule: Color(0xFFE4E7F0),
    ink: Color(0xFF1B1E2B),
    inkSoft: Color(0xFF5A6076),
    inkBody: Color(0xFF6E7489),
    inkMeta: Color(0xFF8A90A6),
    inkFaint: Color(0xFF9AA0B4),
    pen: Color(0xFF4A5BD4),
    penDeep: Color(0xFF35469E),
    penPale: Color(0xFFCBD2F7),
    highlight: Color(0xFFFFD84D),
    redPen: Color(0xFFC42A42),
    mint: Color(0xFF17A47A),
    tintWarm: Color(0xFFFFF3CF),
    warmDeep: Color(0xFF9A7400),
    tintMint: Color(0xFFDFF6EC),
    mintDeep: Color(0xFF0E7A5A),
    tintRed: Color(0xFFFFE3E6),
    redDeep: Color(0xFFB01A2A),
    tintPen: Color(0xFFE8EBFC),
  );

  /// The night set. Surfaces step up in lightness the nearer they are to the
  /// reader (ground, then card), because a shadow cannot show depth on a dark
  /// page; the tints become deep washes and their "deep" inks become light, so
  /// every pair keeps the contrast it has by day.
  static const dark = NestPalette(
    brightness: Brightness.dark,
    ground: Color(0xFF0E1016),
    paper: Color(0xFF12141C),
    paperDeep: Color(0xFF202433),
    card: Color(0xFF181B26),
    rule: Color(0xFF2A2E3D),
    ink: Color(0xFFECEEF5),
    inkSoft: Color(0xFFB4B9CC),
    inkBody: Color(0xFFA0A6BC),
    inkMeta: Color(0xFF8A90A6),
    inkFaint: Color(0xFF7C8299),
    pen: Color(0xFF6676E8),
    penDeep: Color(0xFFAEB8FA),
    penPale: Color(0xFFD6DBFA),
    highlight: Color(0xFFFFD84D),
    redPen: Color(0xFFD63A52),
    mint: Color(0xFF22B88C),
    tintWarm: Color(0xFF3B3215),
    warmDeep: Color(0xFFF6CD54),
    tintMint: Color(0xFF12352B),
    mintDeep: Color(0xFF5FD3A3),
    tintRed: Color(0xFF3D1C23),
    redDeep: Color(0xFFFF8A9B),
    tintPen: Color(0xFF262C55),
  );
}

class NestColor {
  NestColor._();

  static NestPalette _p = NestPalette.light;

  /// Switches every colour the app reads. The caller rebuilds the tree
  /// afterwards (see ThemeController): a getter cannot tell a widget to redraw.
  static void use(NestPalette p) => _p = p;

  static NestPalette get palette => _p;

  static bool get isDark => _p.brightness == Brightness.dark;

  // Surfaces
  //
  // Two greys, not one. `ground` is the page; `paper` is a well sunk into it —
  // an input, a tag chip, an unselected segment. A filled text field on a page
  // of its own colour is invisible, so every field would need a border to
  // exist, and the borders put the whole screen back on one flat plane.
  static Color get ground => _p.ground; // the page
  static Color get paper => _p.paper; // a well sunk into the page
  static Color get paperDeep => _p.paperDeep; // pressed
  static Color get card => _p.card; // a surface above the page
  static Color get rule => _p.rule; // hairline

  // Ink
  static Color get ink => _p.ink;
  static Color get inkSoft => _p.inkSoft;
  static Color get inkBody => _p.inkBody; // body copy inside a card
  static Color get inkMeta => _p.inkMeta; // "CSE 112 · 4 min"
  static Color get inkFaint => _p.inkFaint; // a timestamp, an inactive icon

  // Writing instruments
  static Color get pen => _p.pen; // indigo — every primary action
  static Color get penDeep => _p.penDeep;
  static Color get penPale => _p.penPale; // type on top of a pen-filled card
  static Color get highlight => _p.highlight; // what to do next
  static Color get redPen => _p.redPen; // important / destructive
  static Color get mint => _p.mint; // done / synced

  /// Ink for anything printed on [highlight] yellow. Fixed, because the yellow
  /// is the same by day and by night and so must be the type on it.
  static const onHighlight = Color(0xFF1B1E2B);

  /// Soft tints, and the one ink that is readable on each.
  ///
  /// These pairs are the app's colour. A status word, a subject initial, a
  /// tool icon — each sits in its own tint, and those small blocks of colour
  /// are what stop a page of white cards looking like a spreadsheet. Each ink
  /// was picked to clear 4.5:1 against its own tint, so the pairs must be used
  /// together: warm ink on a red tint fails.
  static Color get tintWarm => _p.tintWarm;
  static Color get warmDeep => _p.warmDeep;
  static Color get tintMint => _p.tintMint;
  static Color get mintDeep => _p.mintDeep;
  static Color get tintRed => _p.tintRed;
  static Color get redDeep => _p.redDeep;
  static Color get tintPen => _p.tintPen;

  /// Index-tab colours for subjects. Pastels read on both grounds.
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

  // A shadow is the ink colour at low strength by day; at night the ground is
  // already dark, so it is plain black and a little stronger.
  static Color _c(int day, int night) =>
      NestColor.isDark ? Color(night) : Color(day);

  /// A card resting on the page.
  static List<BoxShadow> get resting => [
        BoxShadow(
          color: _c(0x141B1E2B, 0x59000000),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  /// Something lifted: a selected card, a tool tile, the primary button.
  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: _c(0x1F1B1E2B, 0x73000000),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: _c(0x0F1B1E2B, 0x40000000),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// Floating over everything: the nav bar, a sheet, a dialog.
  static List<BoxShadow> get floating => [
        BoxShadow(
          color: _c(0x241B1E2B, 0x80000000),
          blurRadius: 34,
          offset: const Offset(0, 12),
        ),
      ];

  /// A coloured glow under a filled action, so the primary button looks lit
  /// rather than merely dark.
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: NestColor.o(c, NestColor.isDark ? 0.28 : 0.34),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Small uppercase utility labels ("SUBJECTS", note counts, section heads).
TextStyle get nestEyebrow => TextStyle(
      fontFamily: NestFont.body,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: ls(1.2),
      color: NestColor.inkFaint,
    );

/// The app's theme, built from whichever palette [NestColor] is using.
ThemeData nestTheme() {
  final dark = NestColor.isDark;
  final scheme = ColorScheme.fromSeed(
    seedColor: NestColor.pen,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: NestColor.pen,
    onPrimary: Colors.white,
    secondary: NestColor.highlight,
    onSecondary: NestColor.onHighlight,
    surface: NestColor.card,
    onSurface: NestColor.ink,
    error: NestColor.redPen,
  );

  final text = TextTheme(
    displaySmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 31,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: ls(-0.8),
      color: NestColor.ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 24,
      height: 1.18,
      fontWeight: FontWeight.w600,
      letterSpacing: ls(-0.5),
      color: NestColor.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: ls(-0.2),
      color: NestColor.ink,
    ),
    titleSmall: TextStyle(
      fontFamily: NestFont.display,
      fontSize: 16.5,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: ls(-0.1),
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

    dividerTheme: DividerThemeData(
      color: NestColor.rule,
      thickness: 1,
      space: 1,
    ),

    appBarTheme: AppBarTheme(
      // Status-bar icons are dark on the light page and light on the dark one.
      systemOverlayStyle:
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
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
        letterSpacing: ls(-0.4),
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
        textStyle: TextStyle(
          fontFamily: NestFont.display,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: ls(0),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NestColor.pen,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: NestColor.rule, width: 1.4),
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
        borderSide: BorderSide(color: NestColor.rule, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: BorderSide(color: NestColor.rule, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: BorderSide(color: NestColor.pen, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: BorderSide(color: NestColor.redPen, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NestRadius.chip + 4),
        borderSide: BorderSide(color: NestColor.redPen, width: 1.8),
      ),
      labelStyle: TextStyle(
        fontFamily: NestFont.body,
        color: NestColor.inkSoft,
        fontSize: 14,
      ),
      hintStyle: TextStyle(
        fontFamily: NestFont.body,
        color: NestColor.inkFaint,
        fontSize: 14,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: NestColor.card,
      selectedColor: NestColor.pen,
      side: BorderSide(color: NestColor.rule, width: 1.2),
      labelStyle: TextStyle(
        fontFamily: NestFont.body,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: NestColor.inkSoft,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: NestFont.body,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: NestColor.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
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
      titleTextStyle: TextStyle(
        fontFamily: NestFont.display,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: ls(-0.3),
        color: NestColor.ink,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      // A dark bar with white type by day. At night the ink is the light
      // colour, so the bar becomes a raised dark surface with light type.
      backgroundColor: dark ? NestColor.paperDeep : NestColor.ink,
      contentTextStyle: TextStyle(
        fontFamily: NestFont.body,
        fontSize: 13.5,
        height: 1.4,
        color: dark ? NestColor.ink : Colors.white,
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
        // The selected segment is the app's own indigo wash, not the generated
        // scheme's grey, which at night looked like a disabled button.
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NestColor.tintPen
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NestColor.penDeep
                : NestColor.inkSoft),
        side: WidgetStatePropertyAll(BorderSide(color: NestColor.rule)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: NestColor.inkSoft,
      textColor: NestColor.ink,
    ),
  );
}
