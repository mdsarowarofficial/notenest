/// The university list, and how a search through ten thousand of them ranks.
///
/// Names of institutions are facts, so they can be carried in the app. Their
/// logos are not — see `brand_store.dart` for why the logo is something the
/// student supplies once rather than something the app ships.
library;

class University {
  const University({
    required this.name,
    required this.countryCode,
    this.domain = '',
  });

  final String name;

  /// ISO 3166-1 alpha-2, or empty where the source had none.
  final String countryCode;

  /// The institution's own domain, used only as a disambiguating hint when
  /// two universities in the list share a name.
  final String domain;

  factory University.fromJson(Map<String, Object?> m) => University(
        name: (m['n'] as String?)?.trim() ?? '',
        countryCode: (m['c'] as String?)?.trim().toUpperCase() ?? '',
        domain: (m['d'] as String?)?.trim() ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is University &&
      other.name == name &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(name, countryCode);

  @override
  String toString() => '$name ($countryCode)';
}

/// How well [name] answers [query]. Lower is better; -1 means no match.
///
/// Ranking by anything other than position is what makes a list this long
/// usable. Typing "city" should put "City University" first, not the
/// forty-ninth entry that happens to contain the word "City" in the middle of
/// its name.
///
/// [query] is expected already lowercased and trimmed by [searchUniversities].
int universityScore(String name, String query) {
  if (query.isEmpty) return -1;
  final lower = name.toLowerCase();

  if (lower == query) return 0;
  if (lower.startsWith(query)) return 1;

  final words = lower.split(RegExp(r'[\s\-,.()]+')).where((w) => w.isNotEmpty);

  // "nsu" should find nothing, but "north south" should find North South
  // University by its second word as readily as its first.
  for (final word in words) {
    if (word.startsWith(query)) return 2;
  }

  if (lower.contains(query)) return 3;

  // Every word typed matches the start of some word in the name, in any
  // order: "dhaka eng" finds "Dhaka University of Engineering and Technology".
  final terms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (terms.length > 1) {
    final nameWords = words.toList();
    final matchedAll = terms.every(
      (t) => nameWords.any((w) => w.startsWith(t)),
    );
    if (matchedAll) return 4;
  }

  return -1;
}

/// The best [limit] matches for [query], best first.
///
/// [preferCountry] breaks ties towards the student's own country. A student in
/// Dhaka typing "university of" wants the Bangladeshi ones at the top, and
/// without this the alphabet decides instead.
List<University> searchUniversities(
  List<University> all,
  String query, {
  String? preferCountry,
  int limit = 30,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    // No query yet: show the student's own country, which is almost always
    // what they were about to type.
    final home = preferCountry?.toUpperCase();
    final list = home == null
        ? all
        : all.where((u) => u.countryCode == home).toList();
    return list.take(limit).toList();
  }

  final scored = <({University uni, int score})>[];
  for (final uni in all) {
    final score = universityScore(uni.name, q);
    if (score >= 0) scored.add((uni: uni, score: score));
  }

  final home = preferCountry?.toUpperCase();
  scored.sort((a, b) {
    if (a.score != b.score) return a.score.compareTo(b.score);
    if (home != null) {
      final aHome = a.uni.countryCode == home;
      final bHome = b.uni.countryCode == home;
      if (aHome != bHome) return aHome ? -1 : 1;
    }
    return a.uni.name.toLowerCase().compareTo(b.uni.name.toLowerCase());
  });

  return [for (final s in scored.take(limit)) s.uni];
}

/// Initials for the drawn seal — "DIU" from "Daffodil International
/// University".
///
/// Short words are skipped so "University of Dhaka" gives "UD" rather than
/// "UOD". An empty name gives an empty string: the seal is then drawn blank
/// rather than with letters nobody chose.
String initialsOf(String name, {int max = 3}) {
  const skip = {'of', 'the', 'and', 'for', 'at', 'in'};
  final words = name
      .trim()
      .split(RegExp(r'[\s\-,.()]+'))
      .where((w) => w.length > 1 && !skip.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return '';
  return words.take(max).map((w) => w[0].toUpperCase()).join();
}
