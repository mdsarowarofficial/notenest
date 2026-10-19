import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_plan.dart';
import 'auth_repository.dart';
import 'note_repository.dart';

/// Schedules task, exam and "come back" reminders on the phone itself.
///
/// There is no server in this project, so these are local notifications: the
/// phone's own alarm clock holds them, and they ring with the app closed. They
/// are rebuilt from the plan in [planReminders] whenever tasks or exams change,
/// and the whole set is cleared when the person turns reminders off or signs
/// out. Off by default; turning them on is what asks for permission.
class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _debounce;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_ready || !supported) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  /// Rebuilds the schedule whenever the repository changes.
  void attach(NoteRepository repo) {
    repo.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), sync);
    });
  }

  /// Asks the system for permission. Returns whether reminders may ring.
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<void> sync() async {
    await init();
    if (!_ready) return;
    final repo = NoteRepository.instance;
    try {
      await _plugin.cancelAll();
      if (!AuthRepository.instance.isSignedIn || !repo.remindersOn) return;

      final plan = planReminders(
        tasks: repo.tasks(),
        exams: repo.exams(),
        now: DateTime.now(),
        disabledGroups: repo.noticeOff,
        idleNudge: repo.idleReminder,
      );
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Reminders',
              channelDescription: 'Task, exam and study reminders',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          // Inexact on purpose: exact alarms need a special permission that
          // Google Play reviews, and a reminder a few minutes late is fine.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }
}
