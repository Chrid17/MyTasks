import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';
import 'common.dart';

/// Full-screen editor for creating or editing a task.
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, required this.task, required this.isNew});

  final Task task;
  final bool isNew;

  static Future<void> open(BuildContext context, Task task, {bool isNew = false}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: isNew,
        builder: (_) => TaskEditorPage(task: task, isNew: isNew),
      ),
    );
  }

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late Task _draft = widget.task;
  late final TextEditingController _title =
      TextEditingController(text: widget.task.title);
  late final TextEditingController _notes =
      TextEditingController(text: widget.task.notes);
  final TextEditingController _newStep = TextEditingController();
  final FocusNode _newStepFocus = FocusNode();
  late final String _original = _fingerprint(widget.task);
  bool _showTitleError = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _notes.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _newStep.dispose();
    _newStepFocus.dispose();
    super.dispose();
  }

  String _fingerprint(Task t) => jsonEncode(t.toJson()..remove('updatedAt'));

  Task get _current => _draft.copyWith(title: _title.text, notes: _notes.text);

  bool get _dirty => widget.isNew
      ? _title.text.trim().isNotEmpty
      : _fingerprint(_current) != _original;

  void _update(Task Function(Task) change) => setState(() => _draft = change(_draft));

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _showTitleError = true);
      return;
    }
    final store = StoreScope.read(context);
    final pendingStep = _newStep.text.trim();
    var task = _current.copyWith(title: title, notes: _notes.text.trim());
    if (pendingStep.isNotEmpty) {
      task = task.copyWith(subtasks: [...task.subtasks, Subtask(id: newId(), title: pendingStep)]);
    }
    final wasDone = widget.isNew ? false : widget.task.done;
    final wantsDone = task.done;
    // Save with the old done state, then toggle so repeating tasks roll over.
    store.saveTask(task.copyWith(
      done: wasDone,
      completedAt: wasDone ? (widget.task.completedAt ?? DateTime.now()) : null,
    ));
    if (wantsDone != wasDone) store.toggleDone(task.id);
    if (task.due != null && task.reminder != ReminderOffset.none && !task.done) {
      unawaited(NotificationService.instance.requestPermission());
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final store = StoreScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Delete task?',
      message: '"${widget.task.title}" will be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final snapshot = store.snapshot();
    store.deleteTasks([widget.task.id]);
    showMessage(context, 'Task deleted',
        actionLabel: 'Undo', onAction: () => store.restore(snapshot));
    navigator.pop();
  }

  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final discard = await confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your changes to this task have not been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard && mounted) navigator.pop();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _draft.due;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) _setDate(picked);
  }

  void _setDate(DateTime? day) {
    _update((t) {
      if (day == null) {
        return t.copyWith(
          due: null,
          hasTime: false,
          reminder: ReminderOffset.none,
          repeat: Repeat.none,
        );
      }
      final old = t.due;
      final due = t.hasTime && old != null
          ? DateTime(day.year, day.month, day.day, old.hour, old.minute)
          : dateOnly(day);
      return t.copyWith(due: due);
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final base = _draft.due ?? dateOnly(now);
    final initial = _draft.hasTime
        ? TimeOfDay.fromDateTime(base)
        : TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final store = StoreScope.read(context);
    _update((t) => t.copyWith(
          due: DateTime(base.year, base.month, base.day, picked.hour, picked.minute),
          hasTime: true,
          reminder: t.reminder == ReminderOffset.none
              ? store.settings.defaultReminder
              : t.reminder,
        ));
  }

  void _addStep() {
    final text = _newStep.text.trim();
    if (text.isEmpty) return;
    _update((t) => t.copyWith(subtasks: [...t.subtasks, Subtask(id: newId(), title: text)]));
    _newStep.clear();
    _newStepFocus.requestFocus();
  }

  Future<void> _renameStep(Subtask step) async {
    final controller = TextEditingController(text: step.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit step'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = result?.trim() ?? '';
    if (title.isEmpty || !mounted) return;
    _update((t) => t.copyWith(subtasks: [
          for (final s in t.subtasks) s.id == step.id ? s.copyWith(title: title) : s,
        ]));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final task = _draft;
    final now = DateTime.now();
    final today = dateOnly(now);
    final due = task.due;
    final dueDay = due == null ? null : dateOnly(due);
    final isCustomDay = dueDay != null &&
        dueDay != today &&
        dueDay != today.add(const Duration(days: 1)) &&
        dueDay != today.add(const Duration(days: 7));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'New task' : 'Edit task'),
          actions: [
            if (!widget.isNew)
              IconButton(
                tooltip: 'Delete task',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: FilledButton(onPressed: _save, child: const Text('Save')),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _Card(
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: CheckCircle(
                                checked: task.done,
                                color: priorityColor(task.priority, scheme),
                                size: 26,
                                tooltip: task.done ? 'Mark as not done' : 'Mark as done',
                                onTap: () => _update((t) => t.copyWith(
                                      done: !t.done,
                                      completedAt: !t.done ? DateTime.now() : null,
                                    )),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _title,
                                autofocus: widget.isNew && _title.text.isEmpty,
                                textCapitalization: TextCapitalization.sentences,
                                maxLines: null,
                                style: theme.textTheme.titleLarge,
                                decoration: InputDecoration(
                                  hintText: 'What do you need to do?',
                                  border: InputBorder.none,
                                  errorText: _showTitleError && _title.text.trim().isEmpty
                                      ? 'Give your task a title'
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: task.important ? 'Remove from Important' : 'Mark as important',
                              onPressed: () => _update((t) => t.copyWith(important: !t.important)),
                              icon: Icon(
                                task.important ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: task.important ? const Color(0xFFF59E0B) : null,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Add notes',
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.notes),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    icon: Icons.checklist,
                    title: 'Steps',
                    trailing: task.subtasks.isEmpty
                        ? null
                        : Text('${task.subtasksDone} of ${task.subtasks.length}',
                            style: theme.textTheme.labelMedium),
                    child: Column(
                      children: [
                        for (final step in task.subtasks)
                          Row(
                            children: [
                              Checkbox(
                                value: step.done,
                                onChanged: (_) => _update((t) => t.copyWith(subtasks: [
                                      for (final s in t.subtasks)
                                        s.id == step.id ? s.copyWith(done: !s.done) : s,
                                    ])),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _renameStep(step),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      step.title,
                                      style: TextStyle(
                                        decoration: step.done ? TextDecoration.lineThrough : null,
                                        color: step.done ? scheme.onSurfaceVariant : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove step',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => _update((t) => t.copyWith(
                                    subtasks: t.subtasks.where((s) => s.id != step.id).toList())),
                              ),
                            ],
                          ),
                        Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.add, size: 20),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _newStep,
                                focusNode: _newStepFocus,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Add a step',
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _addStep(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    icon: Icons.event_outlined,
                    title: 'Due date',
                    trailing: due == null
                        ? null
                        : Text(formatDue(task),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: task.isOverdue(now) ? scheme.error : scheme.primary,
                            )),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Today'),
                              selected: dueDay == today,
                              onSelected: (_) => _setDate(today),
                            ),
                            ChoiceChip(
                              label: const Text('Tomorrow'),
                              selected: dueDay == today.add(const Duration(days: 1)),
                              onSelected: (_) => _setDate(today.add(const Duration(days: 1))),
                            ),
                            ChoiceChip(
                              label: const Text('Next week'),
                              selected: dueDay == today.add(const Duration(days: 7)),
                              onSelected: (_) => _setDate(today.add(const Duration(days: 7))),
                            ),
                            ChoiceChip(
                              avatar: const Icon(Icons.calendar_month, size: 18),
                              label: Text(isCustomDay ? formatDay(dueDay!) : 'Pick date'),
                              selected: isCustomDay,
                              onSelected: (_) => _pickDate(),
                            ),
                            if (due != null)
                              ActionChip(
                                avatar: const Icon(Icons.close, size: 18),
                                label: const Text('No date'),
                                onPressed: () => _setDate(null),
                              ),
                          ],
                        ),
                        if (due != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.schedule, size: 18),
                                label: Text(task.hasTime ? formatTime(due) : 'Add time'),
                                onPressed: _pickTime,
                              ),
                              if (task.hasTime)
                                ActionChip(
                                  avatar: const Icon(Icons.close, size: 18),
                                  label: const Text('All day'),
                                  onPressed: () => _update((t) => t.copyWith(
                                        due: dateOnly(due),
                                        hasTime: false,
                                      )),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _Section(
                    icon: Icons.notifications_outlined,
                    title: 'Reminder',
                    child: due == null
                        ? Text('Set a due date to add a reminder.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final r in ReminderOffset.values)
                                    ChoiceChip(
                                      label: Text(r.label),
                                      selected: task.reminder == r,
                                      onSelected: (_) => _update((t) => t.copyWith(reminder: r)),
                                    ),
                                ],
                              ),
                              if (task.reminder != ReminderOffset.none) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _reminderHint(task),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                  ),
                  _Section(
                    icon: Icons.repeat,
                    title: 'Repeat',
                    child: due == null
                        ? Text('Set a due date to make this task repeat.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant))
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final r in Repeat.values)
                                ChoiceChip(
                                  label: Text(r.label),
                                  selected: task.repeat == r,
                                  onSelected: (_) => _update((t) => t.copyWith(repeat: r)),
                                ),
                            ],
                          ),
                  ),
                  _Section(
                    icon: Icons.flag_outlined,
                    title: 'Priority',
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<TaskPriority>(
                        showSelectedIcon: false,
                        segments: [
                          for (final p in TaskPriority.values)
                            ButtonSegment(
                              value: p,
                              label: Text(p.label),
                              icon: p == TaskPriority.none
                                  ? null
                                  : Icon(Icons.flag, color: priorityColor(p, scheme)),
                            ),
                        ],
                        selected: {task.priority},
                        onSelectionChanged: (s) => _update((t) => t.copyWith(priority: s.first)),
                      ),
                    ),
                  ),
                  _Section(
                    icon: Icons.folder_outlined,
                    title: 'List',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('No list'),
                          selected: task.listId == null,
                          onSelected: (_) => _update((t) => t.copyWith(listId: null)),
                        ),
                        for (final l in store.lists)
                          ChoiceChip(
                            label: Text('${l.emoji}  ${l.name}'),
                            selected: task.listId == l.id,
                            onSelected: (_) => _update((t) => t.copyWith(listId: l.id)),
                          ),
                      ],
                    ),
                  ),
                  if (!widget.isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        [
                          'Created ${formatDateTime(widget.task.createdAt)}',
                          if (widget.task.completedAt != null)
                            'Completed ${formatDateTime(widget.task.completedAt!)}',
                        ].join('  ·  '),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _reminderHint(Task task) {
    final at = task.reminderAt;
    if (at == null) return '';
    final when = '${formatDay(at)} at ${formatTime(at)}';
    final support = NotificationService.instance.support;
    final suffix = switch (support) {
      ReminderSupport.always => '',
      ReminderSupport.whileOpen => ' (while My Tasks is open)',
      ReminderSupport.unavailable => ' — notifications are off; you will see it in the app',
    };
    if (!at.isAfter(DateTime.now())) return 'This reminder time has already passed.';
    return 'Reminds you $when$suffix';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
