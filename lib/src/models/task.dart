import 'dart:math';

/// How important a task is. Ordered from lowest to highest.
enum TaskPriority { none, low, medium, high }

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
        TaskPriority.none => 'None',
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
      };
}

/// How often a task comes back after it is completed.
enum Repeat { none, daily, weekdays, weekly, monthly, yearly }

extension RepeatLabel on Repeat {
  String get label => switch (this) {
        Repeat.none => 'Never',
        Repeat.daily => 'Daily',
        Repeat.weekdays => 'Weekdays',
        Repeat.weekly => 'Weekly',
        Repeat.monthly => 'Monthly',
        Repeat.yearly => 'Yearly',
      };
}

/// When to remind, relative to the task's due date/time.
enum ReminderOffset { none, atDue, min5, min15, min30, hour1, day1 }

extension ReminderOffsetLabel on ReminderOffset {
  String get label => switch (this) {
        ReminderOffset.none => 'No reminder',
        ReminderOffset.atDue => 'At due time',
        ReminderOffset.min5 => '5 min before',
        ReminderOffset.min15 => '15 min before',
        ReminderOffset.min30 => '30 min before',
        ReminderOffset.hour1 => '1 hour before',
        ReminderOffset.day1 => '1 day before',
      };

  Duration get before => switch (this) {
        ReminderOffset.none => Duration.zero,
        ReminderOffset.atDue => Duration.zero,
        ReminderOffset.min5 => const Duration(minutes: 5),
        ReminderOffset.min15 => const Duration(minutes: 15),
        ReminderOffset.min30 => const Duration(minutes: 30),
        ReminderOffset.hour1 => const Duration(hours: 1),
        ReminderOffset.day1 => const Duration(days: 1),
      };
}

final Random _random = Random();

/// A unique, sortable id.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_random.nextInt(1 << 30).toRadixString(36)}';

/// A positive 31-bit id for OS notifications.
int newNotificationId() => 1 + _random.nextInt((1 << 30) - 1);

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [from] to [to], ignoring the time of day.
int daysBetween(DateTime from, DateTime to) =>
    (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();

class Subtask {
  const Subtask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  Subtask copyWith({String? title, bool? done}) =>
      Subtask(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        id: (json['id'] as String?) ?? newId(),
        title: (json['title'] as String?) ?? '',
        done: json['done'] == true,
      );
}

const Object _keep = Object();

class Task {
  const Task({
    required this.id,
    required this.notificationId,
    required this.title,
    this.notes = '',
    this.done = false,
    this.important = false,
    this.priority = TaskPriority.none,
    this.due,
    this.hasTime = false,
    this.reminder = ReminderOffset.none,
    this.repeat = Repeat.none,
    this.listId,
    this.subtasks = const [],
    this.order = 0,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String id;
  final int notificationId;
  final String title;
  final String notes;
  final bool done;
  final bool important;
  final TaskPriority priority;

  /// Due date in local time. When [hasTime] is false only the date matters.
  final DateTime? due;
  final bool hasTime;
  final ReminderOffset reminder;
  final Repeat repeat;
  final String? listId;
  final List<Subtask> subtasks;

  /// Position used by the "My order" sort.
  final double order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  factory Task.create({
    required String title,
    String notes = '',
    bool important = false,
    TaskPriority priority = TaskPriority.none,
    DateTime? due,
    bool hasTime = false,
    ReminderOffset reminder = ReminderOffset.none,
    Repeat repeat = Repeat.none,
    String? listId,
    List<Subtask> subtasks = const [],
    double order = 0,
  }) {
    final now = DateTime.now();
    return Task(
      id: newId(),
      notificationId: newNotificationId(),
      title: title,
      notes: notes,
      important: important,
      priority: priority,
      due: due,
      hasTime: hasTime,
      reminder: reminder,
      repeat: repeat,
      listId: listId,
      subtasks: subtasks,
      order: order,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Pass `null` explicitly to clear [due], [listId] or [completedAt].
  Task copyWith({
    String? id,
    int? notificationId,
    String? title,
    String? notes,
    bool? done,
    bool? important,
    TaskPriority? priority,
    Object? due = _keep,
    bool? hasTime,
    ReminderOffset? reminder,
    Repeat? repeat,
    Object? listId = _keep,
    List<Subtask>? subtasks,
    double? order,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _keep,
  }) {
    return Task(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      done: done ?? this.done,
      important: important ?? this.important,
      priority: priority ?? this.priority,
      due: identical(due, _keep) ? this.due : due as DateTime?,
      hasTime: hasTime ?? this.hasTime,
      reminder: reminder ?? this.reminder,
      repeat: repeat ?? this.repeat,
      listId: identical(listId, _keep) ? this.listId : listId as String?,
      subtasks: subtasks ?? this.subtasks,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _keep)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  /// The moment the due date is reached. Date-only tasks are due at the end
  /// of the day.
  DateTime? get dueMoment {
    final d = due;
    if (d == null) return null;
    return hasTime ? d : DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  /// When the reminder should fire. Date-only tasks remind at 09:00.
  DateTime? get reminderAt {
    final d = due;
    if (d == null || reminder == ReminderOffset.none) return null;
    final base = hasTime ? d : DateTime(d.year, d.month, d.day, 9);
    return base.subtract(reminder.before);
  }

  bool isOverdue([DateTime? now]) {
    final moment = dueMoment;
    if (done || moment == null) return false;
    return moment.isBefore(now ?? DateTime.now());
  }

  bool isDueToday([DateTime? now]) {
    final d = due;
    return d != null && daysBetween(now ?? DateTime.now(), d) == 0;
  }

  int get subtasksDone => subtasks.where((s) => s.done).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'notificationId': notificationId,
        'title': title,
        'notes': notes,
        'done': done,
        'important': important,
        'priority': priority.name,
        'due': due?.toIso8601String(),
        'hasTime': hasTime,
        'reminder': reminder.name,
        'repeat': repeat.name,
        'listId': listId,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'order': order,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawSubtasks = json['subtasks'];
    final rawNotificationId = json['notificationId'];
    final rawOrder = json['order'];
    return Task(
      id: (json['id'] as String?) ?? newId(),
      notificationId: rawNotificationId is int && rawNotificationId > 0
          ? rawNotificationId
          : newNotificationId(),
      title: (json['title'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      done: json['done'] == true,
      important: json['important'] == true,
      priority:
          enumByName(TaskPriority.values, json['priority'], TaskPriority.none),
      due: _parseDate(json['due']),
      hasTime: json['hasTime'] == true,
      reminder: enumByName(
          ReminderOffset.values, json['reminder'], ReminderOffset.none),
      repeat: enumByName(Repeat.values, json['repeat'], Repeat.none),
      listId: json['listId'] as String?,
      subtasks: rawSubtasks is List
          ? rawSubtasks
              .whereType<Map>()
              .map((m) => Subtask.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      order: rawOrder is num ? rawOrder.toDouble() : 0,
      createdAt: _parseDate(json['createdAt']) ?? now,
      updatedAt: _parseDate(json['updatedAt']) ?? now,
      completedAt: _parseDate(json['completedAt']),
    );
  }

  /// Reads a task saved by the previous version of the app, where
  /// `createdAt` held the due date and time.
  factory Task.fromLegacyJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final due = _parseDate(json['createdAt']);
    final done = json['isCompleted'] == true;
    return Task(
      id: (json['id'] as String?) ?? newId(),
      notificationId: newNotificationId(),
      title: (json['title'] as String?) ?? '',
      notes: (json['description'] as String?) ?? '',
      done: done,
      priority:
          enumByName(TaskPriority.values, json['priority'], TaskPriority.medium),
      due: due,
      hasTime: due != null,
      reminder: due != null ? ReminderOffset.atDue : ReminderOffset.none,
      createdAt: now,
      updatedAt: now,
      completedAt: done ? now : null,
    );
  }
}

/// The next due date for a repeating task.
DateTime nextOccurrence(DateTime from, Repeat repeat) {
  DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

  switch (repeat) {
    case Repeat.none:
      return from;
    case Repeat.daily:
      return addDays(from, 1);
    case Repeat.weekdays:
      var next = addDays(from, 1);
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = addDays(next, 1);
      }
      return next;
    case Repeat.weekly:
      return addDays(from, 7);
    case Repeat.monthly:
      return _addMonths(from, 1);
    case Repeat.yearly:
      return _addMonths(from, 12);
  }
}

DateTime _addMonths(DateTime d, int months) {
  final monthIndex = d.month - 1 + months;
  final year = d.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, min(d.day, lastDay), d.hour, d.minute);
}
