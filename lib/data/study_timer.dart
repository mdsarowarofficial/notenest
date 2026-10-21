import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import 'note_repository.dart';
import 'reminder_service.dart';

/// The study timer: one countdown for the whole app.
///
/// It lives here rather than on its screen so that leaving the screen does not
/// stop it: start a session, switch to the notes you are revising, and it
/// carries on. The end time is a moment on the clock, not a number counted
/// down, so a phone that sleeps, or an app that is backgrounded, still finishes
/// on time, and an alarm is scheduled with the system for the same moment.
///
/// What it does not do is survive the app being killed: the alarm still rings,
/// but that sitting is not recorded.
class StudyTimer extends ChangeNotifier {
  StudyTimer._();

  static final StudyTimer instance = StudyTimer._();

  DateTime? _startedAt;
  DateTime? _endsAt;
  int _plannedMinutes = 0;
  int? _subjectId;
  Timer? _ticker;

  /// Set when a session ran to the end and was saved, until it is dismissed.
  int? _finishedMinutes;

  bool get running => _endsAt != null;
  int get plannedMinutes => _plannedMinutes;
  int? get subjectId => _subjectId;
  int? get finishedMinutes => _finishedMinutes;

  Duration get remaining {
    final end = _endsAt;
    if (end == null) return Duration.zero;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 0 at the start, 1 at the end.
  double get progress {
    if (_plannedMinutes == 0 || _endsAt == null) return 0;
    final total = Duration(minutes: _plannedMinutes).inMilliseconds;
    return (1 - remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void dismissFinished() {
    _finishedMinutes = null;
    notifyListeners();
  }

  Future<void> start({required int minutes, int? subjectId}) async {
    if (running) return;
    final now = DateTime.now();
    _startedAt = now;
    _endsAt = now.add(Duration(minutes: minutes));
    _plannedMinutes = minutes;
    _subjectId = subjectId;
    _finishedMinutes = null;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    unawaited(ReminderService.instance.scheduleTimer(
      _endsAt!,
      tr('Study session over'),
      trp('{0} minutes done. Take a break.', [minutes]),
    ));
  }

  /// Ends the session now. The time already spent is saved if it is at least
  /// a minute; returns how many minutes were saved.
  Future<int> stop() async {
    final started = _startedAt;
    if (started == null) return 0;
    final minutes = DateTime.now().difference(started).inMinutes;
    final subject = _subjectId;
    _reset();
    unawaited(ReminderService.instance.cancelTimer());
    if (minutes >= 1) {
      await NoteRepository.instance.addStudySession(
        startedAt: started,
        minutes: minutes,
        subjectId: subject,
      );
    }
    notifyListeners();
    return minutes >= 1 ? minutes : 0;
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _endsAt = null;
    _plannedMinutes = 0;
    _subjectId = null;
  }

  void _tick() {
    final end = _endsAt;
    if (end == null) return;
    if (!DateTime.now().isBefore(end)) {
      _complete();
    } else {
      notifyListeners();
    }
  }

  Future<void> _complete() async {
    final started = _startedAt;
    final minutes = _plannedMinutes;
    final subject = _subjectId;
    _reset();
    if (started == null) return;
    HapticFeedback.heavyImpact();
    await NoteRepository.instance.addStudySession(
      startedAt: started,
      minutes: minutes,
      subjectId: subject,
    );
    _finishedMinutes = minutes;
    notifyListeners();
  }
}
