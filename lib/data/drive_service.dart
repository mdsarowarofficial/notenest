import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_repository.dart';
import 'google_identity.dart';
import '../l10n/strings.dart';

/// A file the app put in somebody's Google Drive.
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    this.mimeType = '',
    this.size = 0,
    this.webViewLink = '',
    this.modifiedTime,
    this.appProperties = const {},
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;

  /// Opens the file in Drive's own viewer, in a browser or the Drive app.
  final String webViewLink;
  final DateTime? modifiedTime;
  final Map<String, String> appProperties;

  factory DriveFile.fromJson(Map<String, dynamic> j) {
    final props = j['appProperties'];
    return DriveFile(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      mimeType: j['mimeType'] as String? ?? '',
      size: int.tryParse('${j['size'] ?? ''}') ?? 0,
      webViewLink: j['webViewLink'] as String? ?? '',
      modifiedTime: DateTime.tryParse(j['modifiedTime'] as String? ?? ''),
      appProperties:
          props is Map ? props.map((k, v) => MapEntry('$k', '$v')) : const {},
    );
  }
}

/// Why a Drive call did not work, worded for the person holding the phone.
class DriveException implements Exception {
  const DriveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Google Drive, through its REST API and the `drive.file` scope.
///
/// `drive.file` means the app can see only files it created itself — never
/// the rest of somebody's Drive. That is a real limit and it is chosen on
/// purpose: it is a non-sensitive scope that needs no security assessment, and
/// the student can open, keep or delete every file from Drive like any other.
///
/// It also decides how files reach other people. A teacher's slides live in the
/// teacher's Drive; a student's app cannot read them through the API, because
/// it did not create them. So a file meant for a class is shared as "anyone
/// with the link can view", and the link is stored only in the class, which
/// only its members can read. Opening it then needs no Google account at all.
class DriveService {
  DriveService._() {
    // The next account on this phone must not inherit this one's token.
    AuthRepository.instance.addSignOutHook(reset);
  }

  static final DriveService instance = DriveService._();

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields =
      'id,name,mimeType,size,webViewLink,modifiedTime,appProperties';

  /// The top folder every NoteNest file goes in, so the student can find them.
  static const rootFolderName = 'NoteNest';

  final Map<String, String> _folderIds = {};
  String? _token;

  bool get isSupported => GoogleAccounts.instance.isSupported;

  /// Asks Google for Drive access, showing the consent sheet only when it has
  /// not been granted yet. With [prompt] false, never shows anything — used by
  /// the daily backup, which must not pop a sheet over whatever the student is
  /// doing.
  Future<String> _accessToken({bool prompt = true}) async {
    if (!isSupported) {
      throw DriveException(
        tr('Google Drive needs the NoteNest app on a phone.'),
      );
    }
    String? token;
    try {
      token =
          await GoogleAccounts.instance.authorizeDrive(promptIfNeeded: prompt);
    } catch (e) {
      throw DriveException('Google Drive could not be reached. $e');
    }
    if (token == null || token.isEmpty) {
      throw DriveException(
        tr('Google Drive access was not given. Allow it when Google asks, so '
        'NoteNest can save files in your Drive.'),
      );
    }
    _token = token;
    return token;
  }

  /// True when Drive access was granted before, checked without asking.
  Future<bool> isConnected() async {
    try {
      await _accessToken(prompt: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks for access now, so later calls do not interrupt anything.
  Future<void> connect() => _accessToken();

  Future<Map<String, String>> _headers({bool prompt = true}) async => {
        'Authorization':
            'Bearer ${_token ?? await _accessToken(prompt: prompt)}',
      };

  /// Runs a request, refreshing the token once if Google says it expired.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) call, {
    bool prompt = true,
  }) async {
    http.Response res;
    try {
      res = await call(await _headers(prompt: prompt));
      if (res.statusCode == 401) {
        _token = null;
        res = await call(await _headers(prompt: prompt));
      }
    } on DriveException {
      rethrow;
    } catch (e) {
      throw DriveException(
        'Could not reach Google Drive. Check your connection. ($e)',
      );
    }
    if (res.statusCode >= 400) throw DriveException(_describe(res));
    return res;
  }

  static String _describe(http.Response res) {
    var reason = '';
    try {
      final body = jsonDecode(res.body);
      reason = (body['error']?['message'] ?? '').toString();
    } catch (_) {}
    if (res.statusCode == 403 && reason.contains('has not been used')) {
      return tr('The Google Drive API is switched off for this app\'s Google '
          'Cloud project. Turn it on in the Cloud console (APIs & Services → '
          'Library → Google Drive API) and try again.');
    }
    if (res.statusCode == 403 && reason.toLowerCase().contains('quota')) {
      return fullMessage;
    }
    if (res.statusCode == 404) {
      return tr('That file is no longer in Google Drive.');
    }
    return trp('Google Drive refused that ({0}). {1}', [res.statusCode, reason]).trim();
  }

  static String get fullMessage =>
      tr('Your Google Drive has no space left. Free some space in Drive '
      '(delete files or empty the bin), then try again.');

  /// Throws [fullMessage] when [bytes] more would not fit in the student's
  /// Drive. Drive reports no limit for unlimited (Workspace) accounts, which
  /// always pass. A failed lookup passes too: the upload itself still reports
  /// a full Drive, so this check only saves a wasted upload.
  Future<void> ensureSpace(int bytes, {bool prompt = true}) async {
    int? limit, used;
    try {
      final res = await _send(
        (h) => http.get(
          Uri.parse('$_api/about').replace(
            queryParameters: {'fields': 'storageQuota'},
          ),
          headers: h,
        ),
        prompt: prompt,
      );
      final q = jsonDecode(res.body)['storageQuota'];
      limit = int.tryParse('${q?['limit'] ?? ''}');
      used = int.tryParse('${q?['usage'] ?? ''}');
    } on DriveException {
      // No access or no network is not "full"; the upload says what's wrong.
      return;
    }
    if (limit == null || used == null) return;
    if (used + bytes > limit) throw DriveException(fullMessage);
  }

  // --------------------------------------------------------------- folders

  /// Finds or makes a folder by path under the NoteNest folder, such as
  /// `['Classes', 'CSE 112']`. Results are remembered for the session.
  Future<String> folder(List<String> path, {bool prompt = true}) async {
    var parent = 'root';
    final names = [rootFolderName, ...path];
    for (var i = 0; i < names.length; i++) {
      final key = names.sublist(0, i + 1).join('/');
      final known = _folderIds[key];
      if (known != null) {
        parent = known;
        continue;
      }
      final name = names[i];
      final q = "mimeType='application/vnd.google-apps.folder' and "
          "name='${_quote(name)}' and '$parent' in parents and trashed=false";
      final found = await _send((h) => http.get(
            Uri.parse('$_api/files').replace(queryParameters: {
              'q': q,
              'fields': 'files(id)',
              'pageSize': '1',
            }),
            headers: h,
          ), prompt: prompt);
      final files = (jsonDecode(found.body)['files'] as List?) ?? const [];
      String id;
      if (files.isNotEmpty) {
        id = files.first['id'] as String;
      } else {
        final made = await _send((h) => http.post(
              Uri.parse('$_api/files?fields=id'),
              headers: {...h, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'name': name,
                'mimeType': 'application/vnd.google-apps.folder',
                'parents': [parent],
              }),
            ), prompt: prompt);
        id = jsonDecode(made.body)['id'] as String;
      }
      _folderIds[key] = id;
      parent = id;
    }
    return parent;
  }

  static String _quote(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  // ---------------------------------------------------------------- files

  /// Uploads bytes as a new file. Resumable, so a large PDF on a weak
  /// connection is one request for the metadata and one for the content,
  /// instead of a multipart body that has to be built in memory twice.
  Future<DriveFile> upload({
    required Uint8List bytes,
    required String name,
    required String mimeType,
    List<String> folderPath = const [],
    Map<String, String> appProperties = const {},
    bool prompt = true,
  }) async {
    final parent = await folder(folderPath, prompt: prompt);
    final start = await _send(
      (h) => http.post(
        Uri.parse('$_upload/files?uploadType=resumable&fields=$_fields'),
        headers: {
          ...h,
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': mimeType,
          'X-Upload-Content-Length': '${bytes.length}',
        },
        body: jsonEncode({
          'name': name,
          'parents': [parent],
          if (appProperties.isNotEmpty) 'appProperties': appProperties,
        }),
      ),
      prompt: prompt,
    );
    final session = start.headers['location'];
    if (session == null) {
      throw DriveException(tr('Google Drive did not start the upload.'));
    }
    final done = await _send(
      (h) => http.put(
        Uri.parse(session),
        headers: {...h, 'Content-Type': mimeType},
        body: bytes,
      ),
      prompt: prompt,
    );
    return DriveFile.fromJson(jsonDecode(done.body) as Map<String, dynamic>);
  }

  /// Replaces the content of a file the app made earlier.
  Future<DriveFile> overwrite({
    required String fileId,
    required Uint8List bytes,
    required String mimeType,
    bool prompt = true,
  }) async {
    final res = await _send(
      (h) => http.patch(
        Uri.parse('$_upload/files/$fileId?uploadType=media&fields=$_fields'),
        headers: {...h, 'Content-Type': mimeType},
        body: bytes,
      ),
      prompt: prompt,
    );
    return DriveFile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Lets anyone holding the link view the file — see the class comment for
  /// why this is how a class gets its files.
  Future<void> shareByLink(String fileId) async {
    await _send((h) => http.post(
          Uri.parse('$_api/files/$fileId/permissions'),
          headers: {...h, 'Content-Type': 'application/json'},
          body: jsonEncode({'type': 'anyone', 'role': 'reader'}),
        ));
  }

  /// Files this app made that carry [key] = [value] in their app properties.
  Future<List<DriveFile>> findByProperty(
    String key,
    String value, {
    bool prompt = true,
  }) async {
    final q = "appProperties has { key='${_quote(key)}' and "
        "value='${_quote(value)}' } and trashed=false";
    final res = await _send(
      (h) => http.get(
        Uri.parse('$_api/files').replace(queryParameters: {
          'q': q,
          'fields': 'files($_fields)',
          'orderBy': 'modifiedTime desc',
          'pageSize': '20',
        }),
        headers: h,
      ),
      prompt: prompt,
    );
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    return files
        .map((f) => DriveFile.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// Downloads a file this app made, with the student's own access.
  Future<Uint8List> downloadOwn(String fileId) async {
    final res = await _send((h) => http.get(
          Uri.parse('$_api/files/$fileId?alt=media'),
          headers: h,
        ));
    return res.bodyBytes;
  }

  Future<void> delete(String fileId) async {
    await _send((h) => http.delete(
          Uri.parse('$_api/files/$fileId'),
          headers: h,
        ));
  }

  /// Downloads a file shared by link, with no Google account needed.
  ///
  /// `confirm=t` skips the "too large to scan for viruses" page Google puts in
  /// front of files over about 100 MB, which would otherwise come back as HTML
  /// in place of the PDF.
  static Future<Uint8List> downloadShared(String fileId) async {
    final http.Response res;
    try {
      res = await http.get(Uri.parse(
        'https://drive.usercontent.google.com/download'
        '?id=$fileId&export=download&confirm=t',
      ));
    } catch (e) {
      throw DriveException('Could not download the file. Check your '
          'connection. ($e)');
    }
    final type = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || type.startsWith('text/html')) {
      throw DriveException(
        tr('The file could not be downloaded. Its owner may have removed it or '
        'stopped sharing it.'),
      );
    }
    return res.bodyBytes;
  }

  /// The browser link for a shared file, for kinds the app cannot show itself.
  static String viewLink(String fileId) =>
      'https://drive.google.com/file/d/$fileId/view';

  /// Forgets the session's token and folders, on sign out.
  void reset() {
    _token = null;
    _folderIds.clear();
  }
}

/// The MIME type for a file name, for the handful of kinds a class shares.
String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  const types = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'zip': 'application/zip',
    'm4a': 'audio/mp4',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
  };
  return types[ext] ?? 'application/octet-stream';
}
