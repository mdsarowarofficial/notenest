import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/university.dart';

/// Loads the bundled university list.
///
/// 10,248 institutions in 200 countries, about 670 KB of JSON. It is read from
/// the asset bundle once, on the first search, and kept in memory afterwards —
/// loading it at startup would make the app slower to open for every student
/// who never opens the cover page screen.
///
/// The list travels with the app rather than coming from a server, so picking
/// a university works on a phone with no connection, which is the point.
class UniversityDirectory {
  UniversityDirectory._();

  static const assetPath = 'assets/universities.json';

  /// Where most of this app's students are. Used only to break ties in search
  /// results, never to filter anything out.
  static const homeCountry = 'BD';

  static List<University>? _cache;
  static Future<List<University>>? _loading;

  static bool get isLoaded => _cache != null;

  /// Reads the asset, or hands back the copy already in memory.
  ///
  /// Concurrent callers share one load: two searches typed in quick succession
  /// should not parse 670 KB of JSON twice.
  static Future<List<University>> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _read();
  }

  static Future<List<University>> _read() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = jsonDecode(raw);
      if (data is! List) return _cache = const [];

      final list = <University>[];
      for (final row in data) {
        if (row is Map) {
          final uni = University.fromJson(row.cast<String, Object?>());
          if (uni.name.isNotEmpty) list.add(uni);
        }
      }
      return _cache = List.unmodifiable(list);
    } catch (_) {
      // A missing or damaged asset must not take the screen down with it. The
      // student can still type the name themselves, which is what the field
      // was before this list existed.
      return _cache = const [];
    } finally {
      _loading = null;
    }
  }

  static Future<List<University>> search(String query, {int limit = 30}) async {
    final all = await load();
    return searchUniversities(
      all,
      query,
      preferCountry: homeCountry,
      limit: limit,
    );
  }
}
