import 'package:flutter/material.dart';

import '../../data/university_directory.dart';
import '../../models/university.dart';
import '../../theme/nest_theme.dart';
import '../../l10n/strings.dart';

/// Picks an institution from the list that ships with the app.
///
/// Searching happens in memory over about ten thousand names, which is fast
/// enough to run on every keystroke without a timer. Results are ranked rather
/// than filtered alphabetically — see [universityScore] — because a list this
/// long is only usable if the obvious answer is first.
Future<University?> showUniversityPicker(BuildContext context) {
  return showModalBottomSheet<University>(
    context: context,
    backgroundColor: NestColor.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _UniversityPicker(),
  );
}

class _UniversityPicker extends StatefulWidget {
  const _UniversityPicker();

  @override
  State<_UniversityPicker> createState() => _UniversityPickerState();
}

class _UniversityPickerState extends State<_UniversityPicker> {
  final _query = TextEditingController();

  List<University> _results = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _query.addListener(_search);
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _query.text;
    final found = await UniversityDirectory.search(text, limit: 40);
    // The field may have moved on while the first load was reading the asset.
    if (!mounted || text != _query.text) return;
    setState(() {
      _results = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: NestColor.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Find your university'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _query,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: tr('Type a name — "daffodil", "city"…'),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: NestColor.paper,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(NestRadius.chip),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? _NotListed(query: _query.text)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final uni = _results[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  uni.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: uni.domain.isEmpty
                                    ? null
                                    : Text(
                                        uni.domain,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                trailing: uni.countryCode.isEmpty
                                    ? null
                                    : Text(
                                        uni.countryCode,
                                        style: nestEyebrow,
                                      ),
                                onTap: () => Navigator.pop(context, uni),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No list of universities is complete, and a new one opens every year. Saying
/// so, and getting out of the way, beats an empty screen.
class _NotListed extends StatelessWidget {
  const _NotListed({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Not in the list'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            tr('The list holds about ten thousand institutions, but it is not '
            'every one, and new ones open each year. Close this and type the '
            'name into the field — it works exactly the same on the page.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (query.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                University(name: query.trim(), countryCode: ''),
              ),
              child: Text(trp('Use "{0}"', [query.trim()])),
            ),
          ],
        ],
      ),
    );
  }
}
