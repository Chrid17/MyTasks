import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../models/app_settings.dart';
import '../models/task.dart';
import '../models/task_list.dart';

/// Something that can put reminders in front of the user.
abstract class ReminderScheduler {
  Future<void> schedule(Task task);
  Future<void> cancel(Task task);
  Future<void> rescheduleAll(Iterable<Task> tasks);
  Future<void> showNow(Task task);
}

enum ViewKind { today, upcoming, important, all, completed, list }

class TaskView {
  const TaskView(this.kind, [this.listId]);

  final ViewKind kind;
  final String? listId;

  static const today = TaskView(ViewKind.today);
  static const upcoming = TaskView(ViewKind.upcoming);
  static const important = TaskView(ViewKind.important);
  static const all = TaskView(ViewKind.all);
  static const completed = TaskView(ViewKind.completed);

  @override
  bool operator ==(Object other) =>
      other is TaskView && other.kind == kind && other.listId == listId;

  @override
  int get hashCode => Object.hash(kind, listId);
}

class ViewStats {
  const ViewStats({
    required this.total,
    required this.active,
    required this.completed,
    required this.overdue,
    required this.dueToday,
  });

  final int total;
  final int active;
  final int completed;
  final int overdue;
  final int dueToday;

  double get progress => total == 0 ? 0.0 : completed / total;
}

/// All app state and the actions that change it.
class TaskStore extends ChangeNotifier {
  TaskStore({required Storage storage, ReminderScheduler? reminders})
      : _storage = storage,
        _reminders = reminders;

  final Storage _storage;
  final ReminderScheduler? _reminders;

  static const tasksKey = 'my_tasks.tasks.v2';
  static const listsKey = 'my_tasks.lists.v2';
  static const settingsKey = 'my_tasks.settings.v2';
  static const legacyKey = 'todos';

  List<Task> _tasks = [];
  List<TaskList> _lists = [];
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  TaskView _view = TaskView.all;
  StatusFilter _filter = StatusFilter.all;
  String _query = '';
  bool _selectionMode = false;
  final Set<String> _selected = {};

  Future<void> _pendingWrite = Future.value();

  // ---------------------------------------------------------------------------
  // Reading state
  // ---------------------------------------------------------------------------

  bool get isLoaded => _loaded;
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<TaskList> get lists => List.unmodifiable(_lists);
  AppSettings get settings => _settings;
  TaskView get view => _view;
  StatusFilter get filter => _filter;
  String get query => _query;
  bool get selectionMode => _selectionMode;
  Set<String> get selectedIds => Set.unmodifiable(_selected);
  bool isSelected(String id) => _selected.contains(id);

  Task? taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  TaskList? listById(String? id) {
    if (id == null) return null;
    for (final l in _lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  String viewTitle(TaskView v) => switch (v.kind) {
        ViewKind.today => 'Today',
        ViewKind.upcoming => 'Upcoming',
        ViewKind.important => 'Important',
        ViewKind.all => 'All tasks',
        ViewKind.completed => 'Completed',
        ViewKind.list => listById(v.listId)?.name ?? 'List',
      };

  bool inView(Task t, TaskView v, [DateTime? now]) {
    final today = dateOnly(now ?? DateTime.now());
    switch (v.kind) {
      case ViewKind.today:
        final due = t.due;
        if (due == null) return false;
        final day = dateOnly(due);
        return t.done ? day == today : !day.isAfter(today);
      case ViewKind.upcoming:
        final due = t.due;
        return due != null && dateOnly(due).isAfter(today);
      case ViewKind.important:
        return t.important;
      case ViewKind.all:
        return true;
      case ViewKind.completed:
        return t.done;
      case ViewKind.list:
        return t.listId == v.listId;
    }
  }

  /// Tasks for the current view, search and filter: active first, then done.
  List<Task> get visibleTasks {
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    Iterable<Task> items = _tasks.where((t) => inView(t, _view, now));
    if (q.isNotEmpty) {
      items = items.where((t) =>
          t.title.toLowerCase().contains(q) ||
          t.notes.toLowerCase().contains(q) ||
          t.subtasks.any((s) => s.title.toLowerCase().contains(q)) ||
          (listById(t.listId)?.name.toLowerCase().contains(q) ?? false));
    }
    if (_view.kind != ViewKind.completed) {
      if (_filter == StatusFilter.active) items = items.where((t) => !t.done);
      if (_filter == StatusFilter.completed) items = items.where((t) => t.done);
    }
    final active = items.where((t) => !t.done).toList()..sort(_compare);
    final done = items.where((t) => t.done).toList()
      ..sort((a, b) => (b.completedAt ?? b.updatedAt)
          .compareTo(a.completedAt ?? a.updatedAt));
    return [...active, ...done];
  }

  int _compare(Task a, Task b) {
    int byOrder() => a.order.compareTo(b.order);
    int byDue() {
      final ad = a.dueMoment;
      final bd = b.dueMoment;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }

    int byPriority() => b.priority.index.compareTo(a.priority.index);

    int chain(List<int Function()> comparisons) {
      for (final c in comparisons) {
        final r = c();
        if (r != 0) return r;
      }
      return 0;
    }

    return switch (_settings.sortMode) {
      SortMode.manual => chain([byOrder, () => b.createdAt.compareTo(a.createdAt)]),
      SortMode.dueDate => chain([byDue, byPriority, byOrder]),
      SortMode.priority => chain([byPriority, byDue, byOrder]),
      SortMode.created => b.createdAt.compareTo(a.createdAt),
      SortMode.alphabetical =>
        chain([() => a.title.toLowerCase().compareTo(b.title.toLowerCase()), byOrder]),
    };
  }

  /// Number of unfinished tasks in a view, for sidebar badges.
  int activeCount(TaskView v) {
    final now = DateTime.now();
    if (v.kind == ViewKind.completed) {
      return _tasks.where((t) => t.done).length;
    }
    return _tasks.where((t) => !t.done && inView(t, v, now)).length;
  }

  ViewStats statsFor(TaskView v) {
    final now = DateTime.now();
    final items = _tasks.where((t) => inView(t, v, now)).toList();
    return ViewStats(
      total: items.length,
      active: items.where((t) => !t.done).length,
      completed: items.where((t) => t.done).length,
      overdue: items.where((t) => t.isOverdue(now)).length,
      dueToday: items.where((t) => !t.done && t.isDueToday(now)).length,
    );
  }

  // ---------------------------------------------------------------------------
  // Loading and saving
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    var tasksOk = true;
    try {
      final raw = await _storage.read(tasksKey);
      if (raw != null) {
        _tasks = _decodeTasks(raw);
      } else {
        _tasks = await _migrateLegacy();
      }
    } catch (e) {
      tasksOk = false;
      debugPrint('Could not read saved tasks: $e');
    }
    try {
      final raw = await _storage.read(listsKey);
      _lists = raw == null
          ? _defaultLists()
          : (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((m) => TaskList.fromJson(Map<String, dynamic>.from(m)))
              .toList();
    } catch (e) {
      _lists = _defaultLists();
    }
    try {
      final raw = await _storage.read(settingsKey);
      if (raw != null) {
        _settings = AppSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (e) {
      _settings = const AppSettings();
    }
    _loaded = true;
    if (tasksOk) {
      _save();
    } else {
      // Keep the unreadable data aside instead of overwriting it.
      final raw = await _storage.read(tasksKey);
      if (raw != null) await _storage.write('$tasksKey.backup', raw);
      _save();
    }
    unawaited(_reminders?.rescheduleAll(_tasks));
    notifyListeners();
  }

  List<Task> _decodeTasks(String raw) => (jsonDecode(raw) as List)
      .whereType<Map>()
      .map((m) => Task.fromJson(Map<String, dynamic>.from(m)))
      .where((t) => t.title.trim().isNotEmpty)
      .toList();

  Future<List<Task>> _migrateLegacy() async {
    try {
      final raw = await _storage.read(legacyKey);
      if (raw == null || raw.isEmpty) return [];
      final items = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => Task.fromLegacyJson(Map<String, dynamic>.from(m)))
          .where((t) => t.title.trim().isNotEmpty)
          .toList();
      for (var i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(order: i.toDouble());
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  List<TaskList> _defaultLists() => [
        const TaskList(id: 'personal', name: 'Personal', emoji: '🏠', color: 0xFF2563EB),
        const TaskList(id: 'work', name: 'Work', emoji: '💼', color: 0xFFEA580C),
        const TaskList(id: 'shopping', name: 'Shopping', emoji: '🛒', color: 0xFF16A34A),
      ];

  void _save() {
    if (!_loaded) return;
    final tasks = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    final lists = jsonEncode(_lists.map((l) => l.toJson()).toList());
    final settings = jsonEncode(_settings.toJson());
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _storage.write(tasksKey, tasks);
        await _storage.write(listsKey, lists);
        await _storage.write(settingsKey, settings);
      } catch (e) {
        debugPrint('Could not save: $e');
      }
    });
  }

  /// Completes when everything changed so far has been written.
  Future<void> flush() => _pendingWrite;

  void _commit() {
    _save();
    notifyListeners();
  }

  void _syncReminder(Task task) {
    final r = _reminders;
    if (r == null) return;
    unawaited(task.done ? r.cancel(task) : r.schedule(task));
  }

  // ---------------------------------------------------------------------------
  // Navigation, search and selection
  // ---------------------------------------------------------------------------

  void setView(TaskView v) {
    if (_view == v) return;
    _view = v;
    _filter = StatusFilter.all;
    _selectionMode = false;
    _selected.clear();
    notifyListeners();
  }

  void setFilter(StatusFilter f) {
    if (_filter == f) return;
    _filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void startSelection([String? id]) {
    _selectionMode = true;
    if (id != null) _selected.add(id);
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _selected.addAll(ids);
    notifyListeners();
  }

  void endSelection() {
    _selectionMode = false;
    _selected.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  /// A new, unsaved task with sensible defaults for the current view.
  Task createDraft({String title = ''}) {
    final now = DateTime.now();
    final minOrder = _tasks.isEmpty
        ? 0.0
        : _tasks.map((t) => t.order).reduce((a, b) => a < b ? a : b);
    return Task.create(
      title: title,
      listId: _view.kind == ViewKind.list ? _view.listId : null,
      important: _view.kind == ViewKind.important,
      due: _view.kind == ViewKind.today
          ? dateOnly(now)
          : _view.kind == ViewKind.upcoming
              ? dateOnly(now).add(const Duration(days: 1))
              : null,
      order: minOrder - 1,
    );
  }

  /// Adds a new task or replaces an existing one with the same id.
  void saveTask(Task task) {
    final updated = task.copyWith(
      title: task.title.trim(),
      updatedAt: DateTime.now(),
      reminder: task.due == null ? ReminderOffset.none : task.reminder,
      repeat: task.due == null ? Repeat.none : task.repeat,
    );
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _tasks.add(updated);
    } else {
      _tasks[i] = updated;
    }
    _syncReminder(updated);
    _commit();
  }

  /// Marks a task done or not done. Completing a repeating task creates its
  /// next occurrence, which is returned.
  Task? toggleDone(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return null;
    final now = DateTime.now();
    final task = _tasks[i];
    Task? next;
    if (!task.done) {
      _tasks[i] = task.copyWith(done: true, completedAt: now, updatedAt: now);
      final due = task.due;
      if (task.repeat != Repeat.none && due != null) {
        var nextDue = nextOccurrence(due, task.repeat);
        var guard = 0;
        while (guard++ < 1000 &&
            (task.hasTime
                ? !nextDue.isAfter(now)
                : dateOnly(nextDue).isBefore(dateOnly(now)))) {
          nextDue = nextOccurrence(nextDue, task.repeat);
        }
        next = task.copyWith(
          id: newId(),
          notificationId: newNotificationId(),
          done: false,
          completedAt: null,
          due: nextDue,
          subtasks: task.subtasks.map((s) => s.copyWith(done: false)).toList(),
          createdAt: now,
          updatedAt: now,
        );
        _tasks.add(next);
        _syncReminder(next);
      }
    } else {
      _tasks[i] = task.copyWith(done: false, completedAt: null, updatedAt: now);
    }
    _syncReminder(_tasks[i]);
    _commit();
    return next;
  }

  void toggleImportant(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _tasks[i] = _tasks[i]
        .copyWith(important: !_tasks[i].important, updatedAt: DateTime.now());
    _commit();
  }

  void toggleSubtask(String taskId, String subtaskId) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final task = _tasks[i];
    _tasks[i] = task.copyWith(
      subtasks: [
        for (final s in task.subtasks)
          s.id == subtaskId ? s.copyWith(done: !s.done) : s,
      ],
      updatedAt: DateTime.now(),
    );
    _commit();
  }

  void deleteTasks(Iterable<String> ids) {
    final remove = ids.toSet();
    final removed = _tasks.where((t) => remove.contains(t.id)).toList();
    if (removed.isEmpty) return;
    _tasks.removeWhere((t) => remove.contains(t.id));
    _selected.removeAll(remove);
    for (final t in removed) {
      final r = _reminders;
      if (r != null) unawaited(r.cancel(t));
    }
    _commit();
  }

  void setDone(Iterable<String> ids, bool done) {
    for (final id in ids.toList()) {
      final t = taskById(id);
      if (t != null && t.done != done) toggleDone(id);
    }
  }

  void _updateMany(Iterable<String> ids, Task Function(Task) change) {
    final targets = ids.toSet();
    final now = DateTime.now();
    for (var i = 0; i < _tasks.length; i++) {
      if (targets.contains(_tasks[i].id)) {
        _tasks[i] = change(_tasks[i]).copyWith(updatedAt: now);
        _syncReminder(_tasks[i]);
      }
    }
    _commit();
  }

  void setImportant(Iterable<String> ids, bool important) =>
      _updateMany(ids, (t) => t.copyWith(important: important));

  void setPriority(Iterable<String> ids, TaskPriority priority) =>
      _updateMany(ids, (t) => t.copyWith(priority: priority));

  void moveToList(Iterable<String> ids, String? listId) =>
      _updateMany(ids, (t) => t.copyWith(listId: listId));

  void setDue(Iterable<String> ids, DateTime? due) => _updateMany(
        ids,
        (t) => t.copyWith(
          due: due == null
              ? null
              : t.hasTime && t.due != null
                  ? DateTime(due.year, due.month, due.day, t.due!.hour, t.due!.minute)
                  : dateOnly(due),
          hasTime: due == null ? false : t.hasTime,
          reminder: due == null ? ReminderOffset.none : t.reminder,
          repeat: due == null ? Repeat.none : t.repeat,
        ),
      );

  /// Removes completed tasks in the current view. Returns how many.
  int clearCompleted() {
    final ids = _tasks
        .where((t) => t.done && inView(t, _view))
        .map((t) => t.id)
        .toList();
    deleteTasks(ids);
    return ids.length;
  }

  /// Moves a task within the visible active tasks ("My order" sort).
  void reorder(List<Task> visibleActive, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= visibleActive.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > visibleActive.length - 1) newIndex = visibleActive.length - 1;
    if (newIndex == oldIndex) return;
    final items = List<Task>.of(visibleActive);
    final slots = items.map((t) => t.order).toList()..sort();
    // Make sure every slot is distinct so the new order is stable.
    for (var k = 1; k < slots.length; k++) {
      if (slots[k] <= slots[k - 1]) slots[k] = slots[k - 1] + 1;
    }
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final newOrder = <String, double>{
      for (var k = 0; k < items.length; k++) items[k].id: slots[k],
    };
    for (var i = 0; i < _tasks.length; i++) {
      final order = newOrder[_tasks[i].id];
      if (order != null) _tasks[i] = _tasks[i].copyWith(order: order);
    }
    _commit();
  }

  /// A copy of all tasks, for undo.
  List<Task> snapshot() => List<Task>.of(_tasks);

  /// Puts back a [snapshot].
  void restore(List<Task> snapshot) {
    _tasks = List<Task>.of(snapshot);
    _selected.removeWhere((id) => taskById(id) == null);
    unawaited(_reminders?.rescheduleAll(_tasks));
    _commit();
  }

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  TaskList addList(String name, String emoji, int color) {
    final list = TaskList(id: newId(), name: name.trim(), emoji: emoji, color: color);
    _lists.add(list);
    _commit();
    return list;
  }

  void updateList(TaskList list) {
    final i = _lists.indexWhere((l) => l.id == list.id);
    if (i == -1) return;
    _lists[i] = list;
    _commit();
  }

  /// Deletes a list. Its tasks are kept and moved out of the list.
  void deleteList(String id) {
    _lists.removeWhere((l) => l.id == id);
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].listId == id) _tasks[i] = _tasks[i].copyWith(listId: null);
    }
    if (_view.kind == ViewKind.list && _view.listId == id) {
      _view = TaskView.all;
    }
    _commit();
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _commit();
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'app': 'my_tasks',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'lists': _lists.map((l) => l.toJson()).toList(),
        'tasks': _tasks.map((t) => t.toJson()).toList(),
      });

  /// Imports a backup made with [exportJson] (or the old app's data).
  /// Returns the number of tasks imported. Throws [FormatException] for
  /// anything that is not a backup.
  int importJson(String raw, {bool replace = false}) {
    final data = jsonDecode(raw.trim());
    List<dynamic> rawTasks;
    List<dynamic> rawLists = const [];
    if (data is Map && data['tasks'] is List) {
      rawTasks = data['tasks'] as List;
      if (data['lists'] is List) rawLists = data['lists'] as List;
    } else if (data is List) {
      rawTasks = data;
    } else {
      throw const FormatException('This is not a My Tasks backup.');
    }

    final imported = rawTasks.whereType<Map>().map((m) {
      final json = Map<String, dynamic>.from(m);
      return json.containsKey('isCompleted')
          ? Task.fromLegacyJson(json)
          : Task.fromJson(json);
    }).where((t) => t.title.trim().isNotEmpty).toList();
    final importedLists = rawLists
        .whereType<Map>()
        .map((m) => TaskList.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    if (rawTasks.isNotEmpty && imported.isEmpty) {
      throw const FormatException('No tasks found in this backup.');
    }

    if (replace) {
      _tasks = imported;
      if (importedLists.isNotEmpty) _lists = importedLists;
    } else {
      final byId = {for (final t in _tasks) t.id: t};
      for (final t in imported) {
        byId[t.id] = t;
      }
      _tasks = byId.values.toList();
      for (final l in importedLists) {
        final i = _lists.indexWhere((x) => x.id == l.id);
        if (i == -1) {
          _lists.add(l);
        } else {
          _lists[i] = l;
        }
      }
    }
    // Tasks pointing to lists that no longer exist go back to "no list".
    final listIds = _lists.map((l) => l.id).toSet();
    for (var i = 0; i < _tasks.length; i++) {
      final listId = _tasks[i].listId;
      if (listId != null && !listIds.contains(listId)) {
        _tasks[i] = _tasks[i].copyWith(listId: null);
      }
    }
    unawaited(_reminders?.rescheduleAll(_tasks));
    _commit();
    return imported.length;
  }

  /// Deletes every task and restores the default lists.
  void deleteAllData() {
    final old = List<Task>.of(_tasks);
    _tasks = [];
    _lists = _defaultLists();
    _view = TaskView.all;
    _selected.clear();
    _selectionMode = false;
    final r = _reminders;
    if (r != null) {
      for (final t in old) {
        unawaited(r.cancel(t));
      }
    }
    _commit();
  }

  // ---------------------------------------------------------------------------
  // In-app reminders (desktop and web, and a fallback everywhere else)
  // ---------------------------------------------------------------------------

  final StreamController<Task> _dueController = StreamController<Task>.broadcast();
  final Set<String> _firedReminders = {};
  Timer? _ticker;
  DateTime _lastTick = DateTime.now().subtract(const Duration(minutes: 10));
  int _lastMinute = -1;

  /// Tasks whose reminder time has just been reached while the app is open.
  Stream<Task> get dueReminders => _dueController.stream;

  void startReminderTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 15), (_) => checkReminders());
    checkReminders();
  }

  @visibleForTesting
  void checkReminders([DateTime? at]) {
    final now = at ?? DateTime.now();
    for (final t in _tasks) {
      final reminderAt = t.reminderAt;
      if (t.done || reminderAt == null) continue;
      if (reminderAt.isAfter(now) || !reminderAt.isAfter(_lastTick)) continue;
      final key = '${t.id}@${reminderAt.millisecondsSinceEpoch}';
      if (_firedReminders.add(key)) {
        _dueController.add(t);
        final r = _reminders;
        if (r != null) unawaited(r.showNow(t));
      }
    }
    _lastTick = now;
    // Refresh "overdue" and "today" labels as time passes.
    if (now.minute != _lastMinute) {
      _lastMinute = now.minute;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dueController.close();
    super.dispose();
  }
}
