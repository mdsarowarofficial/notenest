import 'note.dart';
import '../l10n/strings.dart';

/// How a list of notes is ordered. Requirement 6.2.
enum NoteSort { newest, oldest, titleAZ, recentlyOpened }

extension NoteSortData on NoteSort {
  String get label {
    switch (this) {
      case NoteSort.newest:
        return tr('Newest first');
      case NoteSort.oldest:
        return tr('Oldest first');
      case NoteSort.titleAZ:
        return tr('Title A–Z');
      case NoteSort.recentlyOpened:
        return tr('Recently opened');
    }
  }

  /// A shorter form for the sort button, which has little room.
  String get shortLabel {
    switch (this) {
      case NoteSort.newest:
        return tr('Newest');
      case NoteSort.oldest:
        return tr('Oldest');
      case NoteSort.titleAZ:
        return 'A–Z';
      case NoteSort.recentlyOpened:
        return tr('Opened');
    }
  }

  /// The ORDER BY clause used when the same query runs in SQL.
  ///
  /// `opened_at IS NULL` sorts to 0 for notes that have been opened and 1 for
  /// those that have not, which keeps never-opened notes at the bottom instead
  /// of letting NULL decide.
  String get orderBy {
    switch (this) {
      case NoteSort.newest:
        return 'updated_at DESC';
      case NoteSort.oldest:
        return 'updated_at ASC';
      case NoteSort.titleAZ:
        return 'title COLLATE NOCASE ASC';
      case NoteSort.recentlyOpened:
        return 'opened_at IS NULL, opened_at DESC';
    }
  }
}

/// Everything the student has asked for in one object: the words typed, the
/// filters switched on, and the order wanted.
///
/// Keeping it in one immutable value means the Notes tab and the search screen
/// ask the same question in the same way, and a query can be handed from one
/// screen to another — tapping a tag on a note opens search already narrowed
/// to that tag.
class NoteQuery {
  const NoteQuery({
    this.text = '',
    this.subjectId,
    this.type,
    this.status,
    this.tag,
    this.importantOnly = false,
    this.sort = NoteSort.newest,
  });

  /// Free text. Every word must appear somewhere in the note.
  final String text;

  /// Set by the drawer on the Notes tab, or by the subject filter in search.
  final int? subjectId;

  final NoteType? type;
  final StudyStatus? status;
  final String? tag;
  final bool importantOnly;
  final NoteSort sort;

  bool get hasText => text.trim().isNotEmpty;

  /// The words to look for, lower-cased, with empty gaps dropped.
  List<String> get terms => text
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// How many filters are switched on. Shown as a badge so the student can
  /// see that a list is narrowed even when the chips are scrolled out of view.
  int get activeFilters => [
        type != null,
        status != null,
        tag != null,
        importantOnly,
      ].where((on) => on).length;

  /// True when nothing has been asked for: no words, no filters, default order.
  bool get isPlain => !hasText && activeFilters == 0 && sort == NoteSort.newest;

  NoteQuery copyWith({
    String? text,
    int? subjectId,
    bool clearSubject = false,
    NoteType? type,
    bool clearType = false,
    StudyStatus? status,
    bool clearStatus = false,
    String? tag,
    bool clearTag = false,
    bool? importantOnly,
    NoteSort? sort,
  }) =>
      NoteQuery(
        text: text ?? this.text,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        type: clearType ? null : (type ?? this.type),
        status: clearStatus ? null : (status ?? this.status),
        tag: clearTag ? null : (tag ?? this.tag),
        importantOnly: importantOnly ?? this.importantOnly,
        sort: sort ?? this.sort,
      );

  /// Drops the filters but keeps the words, the subject and the order, which
  /// is what "Clear filters" should do.
  NoteQuery withoutFilters() =>
      NoteQuery(text: text, subjectId: subjectId, sort: sort);

  /// Toggling a chip means switching it off again when it is already on.
  NoteQuery toggleType(NoteType value) => value == type
      ? copyWith(clearType: true)
      : copyWith(type: value);

  NoteQuery toggleStatus(StudyStatus value) => value == status
      ? copyWith(clearStatus: true)
      : copyWith(status: value);

  NoteQuery toggleTag(String value) {
    final t = normalizeTag(value);
    return t == tag ? copyWith(clearTag: true) : copyWith(tag: t);
  }

  /// True when this note satisfies every part of the query.
  bool matches(Note note) {
    if (note.isDeleted) return false;
    if (subjectId != null && note.subjectId != subjectId) return false;
    if (type != null && note.type != type) return false;
    if (status != null && note.status != status) return false;
    if (importantOnly && !note.important) return false;

    if (tag != null) {
      final wanted = normalizeTag(tag!);
      if (!note.tags.any((t) => normalizeTag(t) == wanted)) return false;
    }

    if (!hasText) return true;

    // Every word must be found, so "dbms normal" finds the note about
    // normalization in DBMS rather than everything mentioning either word.
    final haystack = noteSearchText(note);
    for (final term in terms) {
      if (!haystack.contains(term)) return false;
    }
    return true;
  }

  /// Narrows and orders a list of notes.
  List<Note> apply(List<Note> notes) {
    final out = notes.where(matches).toList();
    out.sort(noteComparator(sort));
    return out;
  }
}

/// Everything in a note that free text is matched against, lower-cased once
/// so a multi-word search does not re-build it for every word.
String noteSearchText(Note note) => [
      note.title,
      note.topic ?? '',
      note.body,
      note.tags.join(' '),
    ].join(' ').toLowerCase();

/// The comparator behind each [NoteSort], so the in-memory path and the SQL
/// path put notes in the same order.
Comparator<Note> noteComparator(NoteSort sort) {
  switch (sort) {
    case NoteSort.newest:
      return (a, b) => b.updatedAt.compareTo(a.updatedAt);
    case NoteSort.oldest:
      return (a, b) => a.updatedAt.compareTo(b.updatedAt);
    case NoteSort.titleAZ:
      return (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase());
    case NoteSort.recentlyOpened:
      return (a, b) {
        final ao = a.openedAt;
        final bo = b.openedAt;
        // Never-opened notes go last, then fall back to when they changed.
        if (ao == null && bo == null) return b.updatedAt.compareTo(a.updatedAt);
        if (ao == null) return 1;
        if (bo == null) return -1;
        return bo.compareTo(ao);
      };
  }
}

/// Puts a tag into the one form it is stored and compared in.
///
/// Tags for one note live in a single comma-joined column, so a tag may never
/// contain a comma. Everything is lower-cased, so "DBMS" and "dbms" are the
/// same tag rather than two entries in the tag list.
String normalizeTag(String raw) {
  var t = raw.trim().toLowerCase();
  t = t.replaceAll(',', ' '); // reserved as the stored separator
  t = t.replaceAll(RegExp(r'^#+'), ''); // students type the hash out of habit
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length > 24) t = t.substring(0, 24).trim();
  return t;
}

/// Cleans a whole list: normalized, empties dropped, duplicates removed, and
/// capped so one note cannot carry an unbounded tag string.
List<String> normalizeTags(Iterable<String> raw, {int limit = 12}) {
  final out = <String>[];
  for (final value in raw) {
    final t = normalizeTag(value);
    if (t.isEmpty || out.contains(t)) continue;
    out.add(t);
    if (out.length >= limit) break;
  }
  return out;
}
