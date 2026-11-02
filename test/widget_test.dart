import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tasks/src/app.dart';
import 'package:my_tasks/src/data/storage.dart';
import 'package:my_tasks/src/models/app_settings.dart';
import 'package:my_tasks/src/models/task.dart';
import 'package:my_tasks/src/state/task_store.dart';

Future<TaskStore> newStore([Map<String, String>? data]) async {
  final store = TaskStore(storage: MemoryStorage(data));
  await store.load();
  return store;
}

void main() {
  group('TaskStore', () {
    test('adds, completes and undoes a task', () async {
      final store = await newStore();
      final task = store.createDraft(title: 'Buy milk');
      store.saveTask(task);
      expect(store.tasks, hasLength(1));

      final snapshot = store.snapshot();
      store.toggleDone(task.id);
      expect(store.taskById(task.id)!.done, isTrue);
      expect(store.taskById(task.id)!.completedAt, isNotNull);

      store.restore(snapshot);
      expect(store.taskById(task.id)!.done, isFalse);
    });

    test('saves to storage and loads it back', () async {
      final storage = MemoryStorage();
      final first = TaskStore(storage: storage);
      await first.load();
      first.saveTask(first.createDraft(title: 'Persist me'));
      await first.flush();

      final second = TaskStore(storage: storage);
      await second.load();
      expect(second.tasks.single.title, 'Persist me');
      expect(second.lists, isNotEmpty);
    });

    test('completing a repeating task creates the next occurrence', () async {
      final store = await newStore();
      final tomorrow = dateOnly(DateTime.now()).add(const Duration(days: 1));
      final due = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      final task = store
          .createDraft(title: 'Water plants')
          .copyWith(due: due, hasTime: true, repeat: Repeat.daily);
      store.saveTask(task);

      final next = store.toggleDone(task.id);
      expect(next, isNotNull);
      expect(next!.done, isFalse);
      expect(next.due, DateTime(due.year, due.month, due.day + 1, 9));
      expect(store.tasks, hasLength(2));
    });

    test('monthly repeat clamps to the end of shorter months', () {
      expect(nextOccurrence(DateTime(2027, 1, 31), Repeat.monthly), DateTime(2027, 2, 28));
      expect(nextOccurrence(DateTime(2027, 12, 15), Repeat.monthly), DateTime(2028, 1, 15));
      expect(nextOccurrence(DateTime(2026, 11, 6), Repeat.weekdays), DateTime(2026, 11, 9));
    });

    test('views and filters pick the right tasks', () async {
      final store = await newStore();
      final today = dateOnly(DateTime.now());
      store.saveTask(store.createDraft(title: 'Today').copyWith(due: today));
      store.saveTask(store.createDraft(title: 'Later')
          .copyWith(due: today.add(const Duration(days: 3))));
      store.saveTask(store.createDraft(title: 'Star').copyWith(important: true));

      store.setView(TaskView.today);
      expect(store.visibleTasks.map((t) => t.title), ['Today']);
      store.setView(TaskView.upcoming);
      expect(store.visibleTasks.map((t) => t.title), ['Later']);
      store.setView(TaskView.important);
      expect(store.visibleTasks.map((t) => t.title), ['Star']);

      store.setView(TaskView.all);
      store.setQuery('lat');
      expect(store.visibleTasks.map((t) => t.title), ['Later']);
    });

    test('sorting by priority puts high first', () async {
      final store = await newStore();
      store.saveTask(store.createDraft(title: 'Low').copyWith(priority: TaskPriority.low));
      store.saveTask(store.createDraft(title: 'High').copyWith(priority: TaskPriority.high));
      store.updateSettings(store.settings.copyWith(sortMode: SortMode.priority));
      expect(store.visibleTasks.first.title, 'High');
    });

    test('reordering changes "My order"', () async {
      final store = await newStore();
      for (final title in ['A', 'B', 'C']) {
        store.saveTask(store.createDraft(title: title));
      }
      // Newest is on top: C, B, A.
      expect(store.visibleTasks.map((t) => t.title), ['C', 'B', 'A']);
      store.reorder(store.visibleTasks, 0, 3);
      expect(store.visibleTasks.map((t) => t.title), ['B', 'A', 'C']);
    });

    test('backup round trip', () async {
      final source = await newStore();
      source.saveTask(source.createDraft(title: 'One').copyWith(
          subtasks: [Subtask(id: newId(), title: 'Step')]));
      source.saveTask(source.createDraft(title: 'Two'));
      final backup = source.exportJson();

      final target = await newStore();
      final count = target.importJson(backup, replace: true);
      expect(count, 2);
      expect(target.tasks.map((t) => t.title).toSet(), {'One', 'Two'});
      expect(target.tasks.firstWhere((t) => t.title == 'One').subtasks, hasLength(1));
      expect(() => target.importJson('{"hello": 1}'), throwsFormatException);
    });

    test('tasks from the old app are migrated', () async {
      final legacy = jsonEncode([
        {
          'id': 'old-1',
          'title': 'Old task',
          'description': 'From version 1',
          'isCompleted': false,
          'createdAt': DateTime(2030, 1, 1, 10).toIso8601String(),
          'priority': 'high',
        },
      ]);
      final store = await newStore({TaskStore.legacyKey: legacy});
      final task = store.tasks.single;
      expect(task.title, 'Old task');
      expect(task.notes, 'From version 1');
      expect(task.priority, TaskPriority.high);
      expect(task.due, DateTime(2030, 1, 1, 10));
      expect(task.hasTime, isTrue);
    });

    test('in-app reminder fires once when its time is reached', () async {
      final store = await newStore();
      final due = DateTime.now().add(const Duration(minutes: 1));
      store.saveTask(store
          .createDraft(title: 'Call mum')
          .copyWith(due: due, hasTime: true, reminder: ReminderOffset.atDue));
      final fired = <Task>[];
      final sub = store.dueReminders.listen(fired.add);

      store.checkReminders(due.subtract(const Duration(seconds: 30)));
      store.checkReminders(due.add(const Duration(seconds: 5)));
      store.checkReminders(due.add(const Duration(seconds: 20)));
      await Future<void>.delayed(Duration.zero);

      expect(fired.map((t) => t.title), ['Call mum']);
      await sub.cancel();
    });

    test('deleting a list keeps its tasks', () async {
      final store = await newStore();
      final list = store.addList('Gym', '💪', 0xFF16A34A);
      store.saveTask(store.createDraft(title: 'Leg day').copyWith(listId: list.id));
      store.deleteList(list.id);
      expect(store.tasks.single.listId, isNull);
      expect(store.lists.any((l) => l.id == list.id), isFalse);
    });
  });

  testWidgets('quick add puts a new task on the list', (tester) async {
    final store = await newStore();
    await tester.pumpWidget(MyTasksApp(store: store, enableReminders: false));
    await tester.pumpAndSettle();

    expect(find.text('All tasks'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Add a task'), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(store.tasks.single.title, 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);
  });
}
