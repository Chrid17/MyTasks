import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import '../state/task_store.dart';
import '../utils/format.dart';
import 'web_notifier.dart';

/// How reminders reach the user on this platform.
enum ReminderSupport {
  /// The OS delivers them, even when the app is closed (Android, iOS, macOS).
  always,

  /// Delivered while the app is open or minimised (Windows, Linux, web).
  whileOpen,

  /// Not available (permission blocked or unsupported browser).
  unavailable,
}

/// Local notifications for task reminders on every platform.
class NotificationService implements ReminderScheduler {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();
  bool _ready = false;

  /// Task id from the notification that launched the app, if any.
  String? launchTaskId;

  /// Task ids from notifications the user tapped while the app was running.
  Stream<String> get taps => _taps.stream;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _macos => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Android, iOS and macOS let us hand reminders to the OS. Windows can't
  /// cancel scheduled toasts without MSIX packaging and Linux has no
  /// scheduler, so there the app shows reminders itself while it runs.
  bool get _schedulesNatively => _ready && (_android || _ios || _macos);

  ReminderSupport get support {
    if (kIsWeb) {
      if (!WebNotifier.isSupported || WebNotifier.isDenied) {
        return ReminderSupport.unavailable;
      }
      return ReminderSupport.whileOpen;
    }
    if (!_ready) return ReminderSupport.unavailable;
    return _schedulesNatively ? ReminderSupport.always : ReminderSupport.whileOpen;
  }

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      final darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      final settings = InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
        linux: LinuxInitializationSettings(defaultActionName: 'Open task'),
        windows: WindowsInitializationSettings(
          appName: 'My Tasks',
          appUserModelId: 'ChrisBwendo.MyTasks',
          guid: '5b0a8f0e-6d2c-4b8a-9f3e-2c7d1a4e9b61',
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final id = response.payload;
          if (id != null && id.isNotEmpty) _taps.add(id);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      _ready = false;
      return;
    }
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        launchTaskId = launch.notificationResponse?.payload;
      }
    } catch (_) {
      // Not supported on every platform.
    }
  }

  /// Asks the OS or browser for permission to show notifications.
  Future<bool> requestPermission() async {
    if (kIsWeb) return WebNotifier.requestPermission();
    if (!_ready) return false;
    try {
      if (_android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (_ios) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (_macos) {
        final macos = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        return await macos?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      return true;
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  /// Android only: whether reminders can fire at the exact minute.
  Future<bool> canUseExactAlarms() async {
    if (!_android || !_ready) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android only: opens the system screen to allow exact alarms.
  Future<void> requestExactAlarms() async {
    if (!_android || !_ready) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  bool get isAndroid => _android;

  NotificationDetails get _details => NotificationDetails(
        android: const AndroidNotificationDetails(
          'task_reminders',
          'Task reminders',
          channelDescription: 'Reminders for tasks that are due',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );

  String _body(Task task) {
    final parts = <String>[];
    if (task.due != null) parts.add('Due ${formatDue(task)}');
    final note = task.notes.trim().split('\n').first;
    if (note.isNotEmpty) parts.add(note);
    return parts.isEmpty ? 'Reminder' : parts.join(' · ');
  }

  @override
  Future<void> schedule(Task task) async {
    if (!_schedulesNatively) return;
    await cancel(task);
    final at = task.reminderAt;
    if (task.done || at == null || !at.isAfter(DateTime.now())) return;
    try {
      var mode = AndroidScheduleMode.inexactAllowWhileIdle;
      if (_android && await canUseExactAlarms()) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
      await _plugin.zonedSchedule(
        id: task.notificationId,
        title: task.title,
        body: _body(task),
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: mode,
        payload: task.id,
      );
    } catch (e) {
      debugPrint('Could not schedule reminder: $e');
    }
  }

  @override
  Future<void> cancel(Task task) async {
    if (!_schedulesNatively) return;
    try {
      await _plugin.cancel(id: task.notificationId);
    } catch (_) {}
  }

  @override
  Future<void> rescheduleAll(Iterable<Task> tasks) async {
    if (!_schedulesNatively) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    for (final t in tasks.toList()) {
      await schedule(t);
    }
  }

  /// Shows a reminder right now. Used where reminders aren't scheduled with
  /// the OS (Windows, Linux, web).
  @override
  Future<void> showNow(Task task) async {
    if (kIsWeb) {
      WebNotifier.show(task.title, _body(task));
      return;
    }
    if (!_ready || _schedulesNatively) return;
    try {
      await _plugin.show(
        id: task.notificationId,
        title: task.title,
        body: _body(task),
        notificationDetails: _details,
        payload: task.id,
      );
    } catch (e) {
      debugPrint('Could not show reminder: $e');
    }
  }

  /// Sends a sample notification so the user can check it works.
  Future<bool> showTest() async {
    if (kIsWeb) {
      final ok = await WebNotifier.requestPermission();
      if (ok) WebNotifier.show('My Tasks', 'Notifications are working 🎉');
      return ok;
    }
    if (!_ready) return false;
    await requestPermission();
    try {
      await _plugin.show(
        id: 1,
        title: 'My Tasks',
        body: 'Notifications are working 🎉',
        notificationDetails: _details,
      );
      return true;
    } catch (e) {
      debugPrint('Test notification failed: $e');
      return false;
    }
  }
}
