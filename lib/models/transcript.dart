/// Turning dictated speech into a note worth revising from.
///
/// A speech recogniser hands back one long run of words with almost no
/// punctuation: "okay so today normalization first normal form means every
/// column holds one value this is important for the exam". Pasted into a note
/// as-is that is unreadable, so this file breaks it into sentences, pulls out
/// the lines the lecturer flagged, and groups the rest.
///
/// Every rule here is a plain text rule — cue words and sentence boundaries.
/// Nothing is sent anywhere and nothing is guessed by a model. That is a
/// deliberate limit: it means the structuring works offline and the student
/// can see exactly why a line was treated as a key point, but it also means it
/// only recognises the cues listed below.
library;

/// Words that mark a lecturer calling something out. A sentence containing one
/// of these is lifted into Key points.
const emphasisCues = <String>[
  'important',
  'remember',
  'note that',
  'keep in mind',
  'make sure',
  'do not forget',
  "don't forget",
  'will come in the exam',
  'for the exam',
  'exam question',
  'definition',
  'define',
  'formula',
  'theorem',
  'rule is',
  'key point',
  'the main point',
  'in short',
  'to summarize',
  'to summarise',
];

/// Words that start an item in a spoken list, so the sentence reads better as
/// a bullet than as part of a paragraph.
const listCues = <String>[
  'first',
  'firstly',
  'second',
  'secondly',
  'third',
  'thirdly',
  'fourth',
  'next',
  'then',
  'after that',
  'finally',
  'lastly',
  'also',
  'another',
  'one more',
  'for example',
  'for instance',
  'such as',
];

/// Noises a speaker makes before actually starting. Stripped from a suggested
/// title so a note is not called "Okay So Today".
const _openerFillers = <String>[
  'okay so',
  'ok so',
  'right so',
  'alright so',
  'so basically',
  'basically',
  'okay',
  'alright',
  'right',
  'so',
  'um',
  'uh',
  'erm',
  'well',
  'now',
  'today we will',
  'today we are going to',
  'today i will',
  'in this lecture',
  'in this class',
];

/// One block of the structured note: either a paragraph or a run of bullets.
class TranscriptBlock {
  const TranscriptBlock({required this.lines, required this.bulleted});

  final List<String> lines;
  final bool bulleted;
}

/// What [structureTranscript] works out from a raw dictation.
class StructuredNote {
  const StructuredNote({
    required this.suggestedTitle,
    required this.keyPoints,
    required this.blocks,
    required this.sentenceCount,
    required this.wordCount,
  });

  /// A title taken from the opening sentence. Only a suggestion — the editor
  /// lets the student replace it.
  final String suggestedTitle;

  /// Sentences that carried an emphasis cue, in the order they were spoken.
  final List<String> keyPoints;

  final List<TranscriptBlock> blocks;
  final int sentenceCount;
  final int wordCount;

  bool get isEmpty => blocks.isEmpty && keyPoints.isEmpty;
}

/// Tidies the recogniser's output without changing any words.
///
/// Collapses the runaway spacing, drops the space before punctuation that
/// recognisers often leave, and makes sure the text ends in a full stop so the
/// sentence splitter does not lose the last clause.
String cleanTranscript(String raw) {
  var t = raw.replaceAll('\r\n', '\n').trim();
  if (t.isEmpty) return '';

  t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
  // replaceAll takes the replacement literally, so a group reference needs
  // replaceAllMapped — otherwise every such space becomes the text "$1".
  t = t.replaceAllMapped(RegExp(r' +([,.;:?!])'), (m) => m.group(1)!);
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  t = t.replaceAll(RegExp(r' *\n *'), '\n');

  if (!RegExp(r'[.?!]$').hasMatch(t)) t = '$t.';
  return t;
}

/// Splits text into sentences.
///
/// Full stops are used where the recogniser supplied them. Where it supplied
/// none — which is the normal case for a long dictation — a line would stay one
/// enormous sentence, so a spoken list cue such as "next" or "finally" is also
/// treated as a boundary. Without that fallback the structuring below would
/// have nothing to work with.
List<String> splitSentences(String text) {
  final cleaned = cleanTranscript(text);
  if (cleaned.isEmpty) return const [];

  final rough = <String>[];
  for (final line in cleaned.split('\n')) {
    if (line.trim().isEmpty) continue;
    // Break after . ? or ! when the next character starts something new.
    for (final part in line.split(RegExp(r'(?<=[.?!])\s+'))) {
      if (part.trim().isNotEmpty) rough.add(part.trim());
    }
  }

  final out = <String>[];
  for (final sentence in rough) {
    out.addAll(_splitOnCues(sentence));
  }
  return out;
}

/// Breaks one very long unpunctuated sentence at spoken list cues.
List<String> _splitOnCues(String sentence) {
  // Short enough to read as one sentence already.
  if (_words(sentence).length <= 18) return [sentence];

  final words = sentence.split(' ');
  final parts = <String>[];
  var current = <String>[];

  for (var i = 0; i < words.length; i++) {
    final lower = words[i].toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    // A cue only starts a new part if there is already enough behind it, so
    // "first" in the middle of a short clause does not shatter the sentence.
    if (current.length >= 6 && listCues.contains(lower)) {
      parts.add(current.join(' '));
      current = <String>[];
    }
    current.add(words[i]);
  }
  if (current.isNotEmpty) parts.add(current.join(' '));

  return parts
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map(_ensureStop)
      .toList();
}

String _ensureStop(String s) =>
    RegExp(r'[.?!]$').hasMatch(s) ? s : '$s.';

List<String> _words(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').isNotEmpty)
    .toList();

String _normalized(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

/// True when the lecturer flagged this sentence as worth remembering.
bool hasEmphasisCue(String sentence) {
  final n = _normalized(sentence);
  return emphasisCues.any((cue) => n.contains(_normalized(cue)));
}

/// True when the sentence opens like an item in a spoken list.
bool startsListItem(String sentence) {
  final n = _normalized(sentence).trim();
  for (final cue in listCues) {
    final c = _normalized(cue);
    if (n == c || n.startsWith('$c ')) return true;
  }
  return false;
}

/// Reads a note title out of the opening sentence.
String suggestTitle(List<String> sentences, {int maxWords = 8}) {
  if (sentences.isEmpty) return '';

  var opening = _normalized(sentences.first).trim();

  // Strip the throat-clearing, longest filler first so "today we will" is
  // removed before the bare "today".
  final fillers = [..._openerFillers]
    ..sort((a, b) => b.length.compareTo(a.length));
  var changed = true;
  while (changed) {
    changed = false;
    for (final filler in fillers) {
      final f = _normalized(filler);
      if (opening == f) {
        opening = '';
        changed = true;
        break;
      }
      if (opening.startsWith('$f ')) {
        opening = opening.substring(f.length + 1).trim();
        changed = true;
        break;
      }
    }
  }

  if (opening.isEmpty) return '';

  final words = opening.split(' ').where((w) => w.isNotEmpty).toList();
  final kept = words.take(maxWords).join(' ');
  return kept.isEmpty
      ? ''
      : kept[0].toUpperCase() + kept.substring(1);
}

/// Breaks a dictation into key points and grouped blocks.
StructuredNote structureTranscript(String raw) {
  final sentences = splitSentences(raw);
  if (sentences.isEmpty) {
    return const StructuredNote(
      suggestedTitle: '',
      keyPoints: [],
      blocks: [],
      sentenceCount: 0,
      wordCount: 0,
    );
  }

  final keyPoints = <String>[];
  final blocks = <TranscriptBlock>[];
  var run = <String>[];
  bool? runBulleted;

  void flush() {
    if (run.isEmpty) return;
    blocks.add(TranscriptBlock(lines: List.of(run), bulleted: runBulleted!));
    run = <String>[];
    runBulleted = null;
  }

  for (final sentence in sentences) {
    if (hasEmphasisCue(sentence)) keyPoints.add(sentence);

    final bulleted = startsListItem(sentence);
    if (runBulleted != null && runBulleted != bulleted) flush();
    runBulleted = bulleted;
    run.add(sentence);
  }
  flush();

  return StructuredNote(
    suggestedTitle: suggestTitle(sentences),
    keyPoints: keyPoints,
    blocks: blocks,
    sentenceCount: sentences.length,
    wordCount: _words(sentences.join(' ')).length,
  );
}

/// Lays a [StructuredNote] out as the note body.
///
/// Plain text with bullet characters and the app's uppercase section labels,
/// because a note body is stored and shown as plain text — there is no
/// Markdown renderer in NoteNest, so inventing `##` headings here would only
/// show up as stray hashes on the note screen.
String structuredBody(StructuredNote note) {
  final out = <String>[];

  // Key points are a summary of the transcript, so they only earn their place
  // when they leave something out. A recogniser that returns no punctuation
  // hands back one long sentence; if that sentence also carries a cue it is
  // both the only key point and the whole transcript, and printing both
  // sections would show the student the same line twice under two headings.
  final summarizes =
      note.keyPoints.isNotEmpty && note.keyPoints.length < note.sentenceCount;

  if (summarizes) {
    out.add('KEY POINTS');
    for (final point in note.keyPoints) {
      out.add('• $point');
    }
    out.add('');
  }

  if (note.blocks.isNotEmpty) {
    if (summarizes) out.add('TRANSCRIPT');
    for (var i = 0; i < note.blocks.length; i++) {
      final block = note.blocks[i];
      if (block.bulleted) {
        for (final line in block.lines) {
          out.add('• $line');
        }
      } else {
        out.add(block.lines.join(' '));
      }
      if (i != note.blocks.length - 1) out.add('');
    }
  }

  return out.join('\n').trim();
}

/// Tags worth offering for a dictation, drawn from the tags the student
/// already uses. A tag is offered when its words are actually spoken in the
/// transcript, so nothing is invented.
List<String> suggestedTagsFor(String transcript, List<String> knownTags) {
  final haystack = ' ${_normalized(transcript)} ';
  final out = <String>[];
  for (final tag in knownTags) {
    final t = _normalized(tag).trim();
    if (t.isEmpty || out.contains(tag)) continue;
    if (haystack.contains(' $t ')) out.add(tag);
    if (out.length >= 6) break;
  }
  return out;
}

/// How many actual words a piece of text holds, ignoring stray punctuation.
int wordCount(String text) => _words(text).length;

/// "7:04" or "1:02:11", for a recording length or a playback position.
String formatClock(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
