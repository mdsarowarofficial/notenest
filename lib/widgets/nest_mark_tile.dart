import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/subject.dart';
import '../theme/nest_theme.dart';

/// The first letter of a word, upper-cased.
///
/// Built on runes rather than `String.characters`, which needs the characters
/// package to be in scope, and rather than `substring(0, 1)`, which cuts a
/// multi-byte letter in half and prints a replacement box. A Bengali name
/// gives back its leading consonant, which is the right initial.
String firstLetterOf(String word) {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return '-';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// The small rounded tinted square at the head of a row.
///
/// This widget is where the app's colour comes from. Everything else is white
/// cards on a pale ground; the mark is a 40px block of warm yellow, pink or
/// mint carrying one letter or one icon, and it is repeated down every list in
/// the app. Remove it and the screens go grey — that was exactly the fault in
/// the first Soft Depth pass, where every card was white and the whole app
/// read as a spreadsheet with rounded corners.
///
/// The tint and the ink always travel as a pair, because each ink was chosen
/// to clear 4.5:1 against its own tint and no other.
class MarkTile extends StatelessWidget {
  const MarkTile({
    super.key,
    required this.tint,
    required this.ink,
    this.letter,
    this.icon,
    this.size = 40,
    this.radius = 14,
  }) : assert(letter != null || icon != null, 'a mark needs a letter or icon');

  final Color tint;
  final Color ink;
  final String? letter;
  final IconData? icon;
  final double size;
  final double radius;

  /// A note's revision status, as its initial. The one thing about a note that
  /// no other notes app shows, so it gets the colour.
  factory MarkTile.status(StudyStatus status, {double size = 40}) {
    return MarkTile(
      tint: tintForStatus(status),
      ink: inkForStatus(status),
      letter: firstLetterOf(status.label),
      size: size,
      radius: size * 0.35,
    );
  }

  /// A subject, as its first letter in the subject's own colour.
  ///
  /// Subject colours are pastels, so the tint is the colour itself lightened
  /// rather than a fixed pair, and the ink stays the page's near-black, which
  /// is readable on every one of the six.
  factory MarkTile.subject(Subject subject, {double size = 40}) {
    return MarkTile(
      tint: NestColor.o(subject.color, 0.34),
      ink: NestColor.ink,
      letter: subject.code.isEmpty ? '?' : firstLetterOf(subject.code),
      size: size,
      radius: size * 0.35,
    );
  }

  /// A tool, an action or anything without a status: an icon in indigo.
  factory MarkTile.tool(
    IconData icon, {
    Color? tint,
    Color? ink,
    double size = 38,
  }) {
    return MarkTile(
      tint: tint ?? NestColor.tintPen,
      ink: ink ?? NestColor.pen,
      icon: icon,
      size: size,
      radius: size * 0.34,
    );
  }

  static Color tintForStatus(StudyStatus status) {
    switch (status) {
      case StudyStatus.newNote:
        return NestColor.tintRed;
      case StudyStatus.read:
        return NestColor.tintPen;
      case StudyStatus.review:
        return NestColor.tintWarm;
      case StudyStatus.mastered:
        return NestColor.tintMint;
    }
  }

  static Color inkForStatus(StudyStatus status) {
    switch (status) {
      case StudyStatus.newNote:
        return NestColor.redDeep;
      case StudyStatus.read:
        return NestColor.penDeep;
      case StudyStatus.review:
        return NestColor.warmDeep;
      case StudyStatus.mastered:
        return NestColor.mintDeep;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.52, color: ink)
          : Text(
              letter!,
              style: TextStyle(
                fontFamily: NestFont.display,
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
                height: 1,
                color: ink,
              ),
            ),
    );
  }
}

/// A person's photo, or their initials when there is none, as a white tile
/// that floats rather than a tinted one that sinks. Used in the Today greeting,
/// the drawer, the profile and beside people in a class.
class InitialsTile extends StatelessWidget {
  const InitialsTile({
    super.key,
    required this.name,
    this.size = 44,
    this.photo,
  });

  final String name;
  final double size;

  /// JPEG bytes. When present the photo fills the tile and the initials are
  /// not drawn.
  final Uint8List? photo;

  /// At most two letters, taken from the first and last word of the name. An
  /// empty or whitespace name gives a dash rather than throwing or showing an
  /// empty box.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '–';
    if (words.length == 1) {
      return firstLetterOf(words.first);
    }
    return firstLetterOf(words.first) + firstLetterOf(words.last);
  }

  @override
  Widget build(BuildContext context) {
    final picture = photo;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(size * 0.36),
        boxShadow: NestShadow.resting,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: picture != null
          ? Image.memory(
              picture,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Rebuilds with the same bytes must not flash blank.
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _letters(),
            )
          : _letters(),
    );
  }

  Widget _letters() {
    return Text(
      initialsOf(name),
      style: TextStyle(
        fontFamily: NestFont.display,
        fontSize: size * 0.34,
        fontWeight: FontWeight.w700,
        height: 1,
        color: NestColor.pen,
      ),
    );
  }
}
