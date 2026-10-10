import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/note_repository.dart';
import '../../models/note.dart';
import '../../models/note_query.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_empty_state.dart';
import '../../widgets/nest_query_bar.dart';
import '../../widgets/nest_tags.dart';
import '../../widgets/note_tile.dart';
import '../notes/note_detail.dart';

/// Search the whole notebook. Requirement 6.1.
///
/// Typing runs the query against the database rather than against the list
/// already on screen, so a note is found by a word buried in its body, not
/// only by its title. The query is held in one [NoteQuery], so the filter bar
/// and the typed words narrow the same search instead of fighting each other.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initial});

  /// Lets another screen open search already narrowed — tapping a tag on a
  /// note arrives here with that tag switched on.
  final NoteQuery? initial;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _repo = NoteRepository.instance;
  final _input = TextEditingController();
  final _focus = FocusNode();

  late NoteQuery _query;

  Timer? _debounce;
  List<Note> _results = const [];
  bool _running = false;

  /// Each run is numbered so a slow earlier query cannot overwrite the
  /// results of a later one.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initial ?? const NoteQuery();
    _input.text = _query.text;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run();
      // A search opened from the toolbar should be ready to type into; one
      // opened from a tag already has its answer, so the keyboard stays down.
      if (_query.isPlain) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _asking => !_query.isPlain;

  void _update(NoteQuery next, {bool immediate = false}) {
    setState(() => _query = next);
    _debounce?.cancel();
    if (immediate) {
      _run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 220), _run);
    }
  }

  Future<void> _run() async {
    final mine = ++_seq;
    if (!_asking) {
      setState(() {
        _results = const [];
        _running = false;
      });
      return;
    }

    setState(() => _running = true);
    final found = await _repo.searchNotes(_query);
    if (!mounted || mine != _seq) return;
    setState(() {
      _results = found;
      _running = false;
    });
  }

  Future<void> _open(Note note) async {
    _focus.unfocus();
    await _repo.rememberSearch(_query.text);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailPage(noteId: note.id!)),
    );
    // The note may have been edited, re-filed or trashed while it was open.
    if (mounted) _run();
  }

  void _useRecent(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _update(_query.copyWith(text: text), immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: _input,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            style: const TextStyle(fontSize: 16, color: NestColor.ink),
            onChanged: (v) => _update(_query.copyWith(text: v)),
            onSubmitted: (v) {
              _repo.rememberSearch(v);
              _update(_query.copyWith(text: v), immediate: true);
            },
            decoration: InputDecoration(
              hintText: 'Search titles, notes and tags',
              border: InputBorder.none,
              isDense: true,
              suffixIcon: _input.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _input.clear();
                        _update(_query.copyWith(text: ''), immediate: true);
                        _focus.requestFocus();
                      },
                    ),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
              child: NestQueryBar(
                query: _query,
                tags: _repo.topTags(limit: 6),
                onChanged: (q) => _update(q, immediate: true),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (!_asking) return _Browse(onPickRecent: _useRecent, onPickQuery: _update);

    if (_results.isEmpty) {
      if (_running) {
        return const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        );
      }
      return NestEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing found',
        message: _query.hasText
            ? 'No note matches “${_query.text.trim()}”. Try a single word, or '
                'clear the filters.'
            : 'No note matches these filters yet.',
        actionLabel: _query.activeFilters > 0 ? 'Clear filters' : null,
        onAction: _query.activeFilters > 0
            ? () => _update(_query.withoutFilters(), immediate: true)
            : null,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        Row(
          children: [
            Text(
              '${_results.length} '
              '${_results.length == 1 ? 'RESULT' : 'RESULTS'}',
              style: nestEyebrow.copyWith(color: NestColor.pen),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: NestColor.rule)),
          ],
        ),
        const SizedBox(height: 4),
        for (final note in _results)
          _ResultTile(note: note, terms: _query.terms, onTap: () => _open(note)),
      ],
    );
  }
}

/// A result with the matching line pulled out of the body.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.note,
    required this.terms,
    required this.onTap,
  });

  final Note note;
  final List<String> terms;
  final VoidCallback onTap;

  /// The piece of the body the match was found in, so the student can see why
  /// the note came back without opening it.
  String? get _snippet {
    if (terms.isEmpty || note.body.trim().isEmpty) return null;
    final body = note.body.replaceAll('\n', ' ');
    final lower = body.toLowerCase();

    for (final term in terms) {
      final at = lower.indexOf(term);
      if (at < 0) continue;
      final from = (at - 34).clamp(0, body.length);
      final to = (at + term.length + 56).clamp(0, body.length);
      final cut = body.substring(from, to).trim();
      return '${from > 0 ? '… ' : ''}$cut${to < body.length ? ' …' : ''}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final snippet = _snippet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoteTile(note: note, onTap: onTap, showRule: snippet == null),
        if (snippet != null)
          Padding(
            padding: const EdgeInsets.only(left: 19, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: NestColor.o(NestColor.highlight, 0.22),
                    borderRadius: BorderRadius.circular(NestRadius.chip),
                    border: const Border(
                      left: BorderSide(color: NestColor.highlight, width: 3),
                    ),
                  ),
                  child: Text(
                    snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: NestColor.inkSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: NestColor.rule),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the screen shows before anything has been asked for: the last few
/// searches, the tags in use, and the subjects, so search is also a way to
/// browse rather than only a box to type into.
class _Browse extends StatelessWidget {
  const _Browse({required this.onPickRecent, required this.onPickQuery});

  final void Function(String text) onPickRecent;
  final void Function(NoteQuery query, {bool immediate}) onPickQuery;

  @override
  Widget build(BuildContext context) {
    final repo = NoteRepository.instance;
    final recent = repo.recentSearches();
    final tags = repo.allTags();
    final subjects = repo.subjects();

    if (!repo.hasNotes) {
      return const NestEmptyState(
        icon: Icons.search_rounded,
        title: 'Nothing to search',
        message: 'Write a note first and it will be findable by its title, '
            'its text or any tag you give it.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              const Text('RECENT SEARCHES', style: nestEyebrow),
              const Spacer(),
              TextButton(
                onPressed: repo.clearRecentSearches,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final text in recent)
            InkWell(
              onTap: () => onPickRecent(text),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        size: 17, color: NestColor.inkFaint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: NestColor.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.north_west_rounded,
                        size: 15, color: NestColor.inkFaint),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
        ],
        if (tags.isNotEmpty) ...[
          const Text('TAGS', style: nestEyebrow),
          const SizedBox(height: 10),
          NestTagChips(
            tags: tags,
            onTap: (tag) => onPickQuery(
              NoteQuery(tag: tag),
              immediate: true,
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (subjects.isNotEmpty) ...[
          const Text('SUBJECTS', style: nestEyebrow),
          const SizedBox(height: 8),
          for (final s in subjects)
            InkWell(
              onTap: () => onPickQuery(
                NoteQuery(subjectId: s.id),
                immediate: true,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 20,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text('${s.noteCount}', style: nestEyebrow),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: NestColor.inkFaint),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
