import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'attachment_store.dart';

/// Why a recording could not start. Kept as a value so the screen decides the
/// wording and this file stays free of UI text.
enum RecorderError { noPermission, notSupported, failed }

extension RecorderErrorMessage on RecorderError {
  String get message {
    switch (this) {
      case RecorderError.noPermission:
        return 'NoteNest needs permission to use the microphone. Allow it in '
            'your phone settings and try again.';
      case RecorderError.notSupported:
        return 'Recording saves a file, so it needs the phone app. The browser '
            'build cannot keep attachments.';
      case RecorderError.failed:
        return 'The microphone could not be started. Close anything else that '
            'might be using it and try again.';
    }
  }
}

/// Records a lecture to an audio file.
///
/// A thin wrapper around the `record` plugin, kept out of the screens for the
/// same reason the database is: the screen asks for "start" and "stop" and
/// watches a few values, and if the plugin is ever swapped only this file
/// changes.
///
/// The elapsed time is counted here rather than taken from the plugin, because
/// what the student needs to see is how long they have been recording, and that
/// has to keep ticking while paused without advancing.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder();

  final _recorder = AudioRecorder();

  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudes;

  /// An amplitude reading or a ticker callback can land after this object has
  /// been disposed, and notifying listeners then throws, so every
  /// notification goes through the override at the bottom of this class.
  bool _disposed = false;

  bool _recording = false;
  bool _paused = false;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  String? _path;

  bool get isRecording => _recording;
  bool get isPaused => _paused;
  bool get isActive => _recording || _paused;
  Duration get elapsed => _elapsed;

  /// Microphone loudness from 0 (silence) to 1 (as loud as it gets), ready to
  /// drive a meter. The plugin reports dBFS, which is negative and logarithmic.
  double get level => _level;

  /// The last few levels, newest last, so a meter can draw a short history
  /// instead of a single jumping bar.
  final List<double> history = <double>[];

  static const _historyLength = 56;

  /// Lectures are speech, so one channel at a modest bit rate. An hour comes
  /// to roughly 28 MB instead of the 115 MB stereo 128 kbps would cost.
  static const _config = RecordConfig(
    numChannels: 1,
    bitRate: 64000,
  );

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording. Returns null on success, or why it could not start.
  Future<RecorderError?> start() async {
    if (isActive) return null;
    if (!AttachmentStore.isSupported) return RecorderError.notSupported;

    try {
      if (!await _recorder.hasPermission()) return RecorderError.noPermission;

      // The file is written into the attachment folder directly, so a finished
      // recording never has to be copied anywhere.
      _path = await AttachmentStore.newFilePath('m4a');
      await _recorder.start(_config, path: _path!);
    } catch (_) {
      _path = null;
      return RecorderError.failed;
    }

    _recording = true;
    _paused = false;
    _elapsed = Duration.zero;
    history.clear();
    _startTicker();
    _listenToLevels();
    notifyListeners();
    return null;
  }

  Future<void> pause() async {
    if (!_recording) return;
    await _recorder.pause();
    _recording = false;
    _paused = true;
    _ticker?.cancel();
    _level = 0;
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_paused) return;
    await _recorder.resume();
    _recording = true;
    _paused = false;
    _startTicker();
    notifyListeners();
  }

  /// Stops and returns the stored file name and its length, or null if nothing
  /// was captured.
  Future<Recording?> stop() async {
    if (!isActive) return null;

    final length = _elapsed;
    await _recorder.stop();
    await _stopWatchers();

    _recording = false;
    _paused = false;
    _level = 0;
    final path = _path;
    _path = null;
    notifyListeners();

    if (path == null) return null;

    final storedName = AttachmentStore.nameOf(path);
    final size = await AttachmentStore.sizeOf(storedName);

    // Under a second usually means a mis-tap, and an empty file is worse than
    // no file, so it is thrown away rather than filed.
    if (size <= 0 || length.inMilliseconds < 1000) {
      await AttachmentStore.delete(storedName);
      return null;
    }

    return Recording(
      storedName: storedName,
      duration: length,
      sizeBytes: size,
    );
  }

  /// Throws the recording away without filing it.
  Future<void> discard() async {
    if (!isActive) return;
    await _abandon();
    notifyListeners();
  }

  /// Stops and deletes without telling anyone.
  ///
  /// [dispose] needs this: a half-finished recording still has to be cleaned
  /// off disk, but notifying listeners from inside dispose would push a
  /// rebuild at a widget that is already gone.
  Future<void> _abandon() async {
    final path = _path;
    try {
      await _recorder.cancel();
    } catch (_) {
      // cancel() is best-effort; the file is removed below either way.
    }
    await _stopWatchers();
    _recording = false;
    _paused = false;
    _level = 0;
    _elapsed = Duration.zero;
    _path = null;
    if (path != null) {
      await AttachmentStore.delete(AttachmentStore.nameOf(path));
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _elapsed += const Duration(milliseconds: 200);
      notifyListeners();
    });
  }

  void _listenToLevels() {
    _amplitudes?.cancel();
    _amplitudes = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((a) {
      _level = _normalize(a.current);
      history.add(_level);
      if (history.length > _historyLength) history.removeAt(0);
      notifyListeners();
    }, onError: (_) {
      // A device that will not report levels should not stop the recording;
      // the meter simply sits still.
    });
  }

  /// dBFS runs from about -60 (silence) up to 0 (clipping). Anything quieter
  /// than -45 is room noise, so the floor is set there to keep the meter from
  /// twitching in a silent room.
  static double _normalize(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    const floor = -45.0;
    final clamped = dbfs.clamp(floor, 0.0);
    return ((clamped - floor) / -floor).clamp(0.0, 1.0);
  }

  Future<void> _stopWatchers() async {
    _ticker?.cancel();
    _ticker = null;
    await _amplitudes?.cancel();
    _amplitudes = null;
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _amplitudes?.cancel();
    // A recording still running when the screen goes has to be cleaned up, or
    // its file is left behind in the attachment folder with nothing pointing
    // at it. The plugin is closed once that has finished.
    if (isActive) {
      _abandon().whenComplete(_recorder.dispose);
    } else {
      _recorder.dispose();
    }
    super.dispose();
  }
}

/// A finished recording, ready to be filed as an attachment.
class Recording {
  const Recording({
    required this.storedName,
    required this.duration,
    required this.sizeBytes,
  });

  final String storedName;
  final Duration duration;
  final int sizeBytes;
}
