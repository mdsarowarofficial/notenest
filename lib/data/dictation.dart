import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../l10n/strings.dart';

/// Turns speech into text using whatever recogniser the device already has.
///
/// The hard part is not starting it, it is keeping it going. The platform
/// recogniser is built for short commands: Android ends the session after
/// roughly five seconds of silence and there is no setting to change that, and
/// Apple cuts a task off after about a minute. A lecture has pauses in it, so
/// a single `listen` call would stop within seconds of the lecturer drawing
/// breath and the student would lose the rest of the class.
///
/// So this class treats each session as one piece of a longer dictation. When
/// a session ends on its own, and the student has not asked to stop, it starts
/// another and keeps the text from the previous one. [restarts] counts how
/// often that has happened, which is also the honest answer to "why does the
/// transcript have gaps" — a word spoken during the handover is lost.
///
/// It is live input only. The platform recogniser on Android cannot read back
/// an audio file, so a recording made with [VoiceRecorder] cannot be
/// transcribed afterwards — the two are separate ways of capturing a lecture,
/// not two steps of one.
class Dictation extends ChangeNotifier {
  Dictation();

  final _speech = SpeechToText();

  /// Everything the recogniser has finalised, joined together.
  String committed = '';

  /// The words it is still working on. Shown in lighter ink, because they can
  /// still change.
  String partial = '';

  bool available = false;
  bool get isListening => _speech.isListening;

  /// True from the moment the student starts until they stop, including the
  /// gaps between sessions. [isListening] goes false in those gaps.
  bool wanted = false;

  int restarts = 0;
  String? error;

  double level = 0;

  String? localeId;
  List<DictationLocale> locales = const [];

  Timer? _restartTimer;

  /// The plugin can deliver a status or error callback after this object has
  /// been disposed — `cancel()` does not promise the platform has gone quiet.
  /// Notifying listeners then throws, so every notification goes through the
  /// override below.
  bool _disposed = false;

  /// Consecutive failed restarts. A device that refuses to listen would
  /// otherwise be asked again forever.
  int _failedRestarts = 0;
  static const _maxFailedRestarts = 3;

  /// The whole dictation so far, finalised text plus what is in flight.
  String get text {
    final p = partial.trim();
    if (p.isEmpty) return committed.trim();
    return '${committed.trim()} $p'.trim();
  }

  bool get isEmpty => text.isEmpty;

  /// Asks the platform for a recogniser. False means this device cannot do it,
  /// and [error] says so.
  Future<bool> prepare() async {
    if (available) return true;
    try {
      available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
    } catch (_) {
      available = false;
    }

    if (!available) {
      error = tr('This device has no speech recogniser available to the app. On '
          'Android the Google app provides it, and it needs to be installed '
          'and allowed to use the microphone.');
      notifyListeners();
      return false;
    }

    error = null;
    try {
      final found = await _speech.locales();
      locales = found
          .map((l) => DictationLocale(id: l.localeId, name: l.name))
          .toList();
      final system = await _speech.systemLocale();
      localeId ??= system?.localeId;
    } catch (_) {
      // Not being able to list languages is not fatal; the recogniser just
      // uses the device default.
      locales = const [];
    }

    notifyListeners();
    return true;
  }

  Future<void> start() async {
    if (!await prepare()) return;
    wanted = true;
    error = null;
    _failedRestarts = 0;
    notifyListeners();
    await _listen();
  }

  /// Ends the dictation. Anything still in flight is kept rather than dropped.
  Future<void> stop() async {
    wanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _commitPartial();
    try {
      await _speech.stop();
    } catch (_) {
      // Already stopped.
    }
    level = 0;
    notifyListeners();
  }

  /// Clears the text without touching the recogniser.
  void reset() {
    committed = '';
    partial = '';
    restarts = 0;
    notifyListeners();
  }

  Future<void> _listen() async {
    if (!wanted) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        // Everything goes inside SpeechListenOptions. The same settings can be
        // passed straight to listen(), but those parameters are deprecated in
        // version 7 and will be removed.
        listenOptions: SpeechListenOptions(
          partialResults: true,
          // One error must not end the whole dictation — a passing "no match"
          // is normal in a quiet stretch and is handled by restarting.
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          // Where the platform supports it, the recogniser puts in the full
          // stops and commas itself. That matters more here than it looks:
          // without punctuation the structuring in models/transcript.dart has
          // to fall back on guessing sentence ends from spoken cue words.
          autoPunctuation: true,
          // Ask for as long a session as the platform will give, so there are
          // fewer handovers and fewer lost words.
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 8),
          localeId: localeId,
        ),
      );
      _failedRestarts = 0;
    } catch (_) {
      _failedRestarts++;
      if (_failedRestarts >= _maxFailedRestarts) {
        wanted = false;
        error = tr('The recogniser stopped responding. The text so far has been '
            'kept — tap the microphone to carry on.');
      }
    }
    notifyListeners();
  }

  void _onResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      _append(result.recognizedWords);
      partial = '';
    } else {
      partial = result.recognizedWords;
    }
    notifyListeners();
  }

  void _append(String words) {
    final w = words.trim();
    if (w.isEmpty) return;
    committed = committed.isEmpty ? w : '${committed.trim()} $w';
  }

  void _commitPartial() {
    if (partial.trim().isEmpty) {
      partial = '';
      return;
    }
    _append(partial);
    partial = '';
  }

  void _onLevel(double value) {
    // Android reports roughly -2 to 10, iOS reports decibels. Both are mapped
    // onto 0..1 so the meter behaves the same on either.
    final normalized = ((value + 2) / 12).clamp(0.0, 1.0);
    level = normalized;
    notifyListeners();
  }

  void _onStatus(String status) {
    // 'done' and 'notListening' both mean this session has ended. If the
    // student has not stopped, that is a pause in the lecture, not the end of
    // the dictation, so another session is started.
    if (status == 'done' || status == 'notListening') {
      _commitPartial();
      level = 0;
      if (wanted) _scheduleRestart();
    }
    notifyListeners();
  }

  void _onError(SpeechRecognitionError e) {
    _commitPartial();
    level = 0;

    // "No match" and "speech timeout" are what a quiet stretch of a lecture
    // looks like, not a fault, so they are never shown — the session is just
    // started again. The exact strings differ between platforms and plugin
    // versions, so the check is on the words rather than on an exact code.
    final code = e.errorMsg.toLowerCase();
    final quiet = code.contains('no_match') ||
        code.contains('nomatch') ||
        code.contains('speech_timeout') ||
        code.contains('speechtimeout');

    // `permanent` is the plugin's own answer to "can recognition continue?",
    // which is more reliable than matching strings: a missing permission or an
    // unavailable recogniser is permanent, a silent moment is not.
    if (!quiet && e.permanent) {
      wanted = false;
      _restartTimer?.cancel();
      _restartTimer = null;
      error = _readable(e.errorMsg);
      notifyListeners();
      return;
    }

    if (!quiet) error = _readable(e.errorMsg);

    if (wanted) {
      _scheduleRestart();
    } else {
      notifyListeners();
    }
  }

  void _scheduleRestart() {
    if (!wanted || _restartTimer != null) return;
    restarts++;
    // A short gap, so a recogniser that is still winding down is not asked to
    // start again on top of itself.
    _restartTimer = Timer(const Duration(milliseconds: 350), () {
      _restartTimer = null;
      if (wanted) _listen();
    });
  }

  /// Turns a platform error code into something a student can act on. Matched
  /// on words rather than exact codes, which differ between platforms.
  static String _readable(String raw) {
    final code = raw.toLowerCase();
    if (code.contains('permission')) {
      return tr('NoteNest needs permission to use the microphone. Allow it in '
          'your phone settings and try again.');
    }
    if (code.contains('network')) {
      return tr('The recogniser on this device needs an internet connection and '
          'could not reach it.');
    }
    if (code.contains('busy')) {
      return tr('The microphone is busy. Close anything else that might be '
          'using it.');
    }
    if (code.contains('language') || code.contains('locale')) {
      return tr('That language is not installed on this device. Pick another, or '
          'add it in the device speech settings.');
    }
    if (code.contains('client')) {
      return tr('The device recogniser could not start. On Android this usually '
          'means the Google app is disabled or has no microphone permission.');
    }
    return trp('The recogniser reported: {0}', [raw]);
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _restartTimer?.cancel();
    wanted = false;
    _speech.cancel();
    super.dispose();
  }
}

/// A language the device can recognise.
class DictationLocale {
  const DictationLocale({required this.id, required this.name});

  final String id;
  final String name;
}
