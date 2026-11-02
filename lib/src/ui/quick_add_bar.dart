import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';
import '../utils/format.dart';
import 'common.dart';
import 'task_editor_page.dart';

/// The "Add a task" card with quick options for due date, time, priority
/// and list.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  DateTime? _due;
  bool _hasTime = false;
  TaskPriority _priority = TaskPriority.none;
  String? _listId;
  bool _listChosen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.clear();
    setState(() {
      _due = null;
      _hasTime = false;
      _priority = TaskPriority.none;
      _listId = null;
      _listChosen = false;
    });
  }

  Task _buildTask(TaskStore store) {
    final draft = store.createDraft(title: _controller.text.trim());
    final due = _due ?? draft.due;
    final hasTime = _due != null && _hasTime;
    return draft.copyWith(
      due: due,
      hasTime: hasTime,
      priority: _priority,
      listId: _listChosen ? _listId : draft.listId,
      reminder: due != null && hasTime ? store.settings.defaultReminder : ReminderOffset.none,
    );
  }

  void _submit() {
    final store = StoreScope.read(context);
    if (_controller.text.trim().isEmpty) {
      widget.focusNode.requestFocus();
      return;
    }
    final task = _buildTask(store);
    store.saveTask(task);
    if (task.reminder != ReminderOffset.none) {
      unawaited(NotificationService.instance.requestPermission());
    }
    _reset();
    widget.focusNode.requestFocus();
  }

  Future<void> _openFullEditor() async {
    final store = StoreScope.read(context);
    final task = _buildTask(store);
    _reset();
    await TaskEditorPage.open(context, task, isNew: true);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() {
      final old = _due;
      _due = _hasTime && old != null
          ? DateTime(picked.year, picked.month, picked.day, old.hour, old.minute)
          : picked;
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final base = _due ?? dateOnly(now);
    final initial = _hasTime
        ? TimeOfDay.fromDateTime(base)
        : TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _due = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      _hasTime = true;
    });
  }

  void _setDay(int? daysFromToday) {
    setState(() {
      if (daysFromToday == null) {
        _due = null;
        _hasTime = false;
        return;
      }
      final day = dateOnly(DateTime.now()).add(Duration(days: daysFromToday));
      final old = _due;
      _due = _hasTime && old != null
          ? DateTime(day.year, day.month, day.day, old.hour, old.minute)
          : day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selectedList = store.listById(_listChosen ? _listId : store.createDraft().listId);
    final canSubmit = _controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.add_task, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Add a task',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              IconButton.filled(
                tooltip: 'Add task',
                onPressed: canSubmit ? _submit : null,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PopupMenuButton<int>(
                tooltip: 'Due date',
                onSelected: (value) {
                  if (value == 99) {
                    _pickDate();
                  } else if (value == -1) {
                    _setDay(null);
                  } else {
                    _setDay(value);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 0, child: Text('Today')),
                  const PopupMenuItem(value: 1, child: Text('Tomorrow')),
                  const PopupMenuItem(value: 7, child: Text('Next week')),
                  const PopupMenuItem(value: 99, child: Text('Pick a date…')),
                  if (_due != null) const PopupMenuItem(value: -1, child: Text('No date')),
                ],
                child: _OptionChip(
                  icon: Icons.event_outlined,
                  label: _due == null ? 'Due date' : formatDay(_due!),
                  active: _due != null,
                ),
              ),
              _OptionChip(
                icon: Icons.schedule,
                label: _hasTime && _due != null ? formatTime(_due!) : 'Time',
                active: _hasTime,
                onTap: _pickTime,
                onClear: _hasTime
                    ? () => setState(() {
                          final d = _due;
                          _hasTime = false;
                          if (d != null) _due = dateOnly(d);
                        })
                    : null,
              ),
              PopupMenuButton<TaskPriority>(
                tooltip: 'Priority',
                onSelected: (p) => setState(() => _priority = p),
                itemBuilder: (_) => [
                  for (final p in TaskPriority.values.reversed)
                    PopupMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          Icon(Icons.flag, color: priorityColor(p, scheme), size: 20),
                          const SizedBox(width: 12),
                          Text(p == TaskPriority.none ? 'No priority' : p.label),
                        ],
                      ),
                    ),
                ],
                child: _OptionChip(
                  icon: Icons.flag_outlined,
                  iconColor: _priority == TaskPriority.none
                      ? null
                      : priorityColor(_priority, scheme),
                  label: _priority == TaskPriority.none ? 'Priority' : _priority.label,
                  active: _priority != TaskPriority.none,
                ),
              ),
              if (store.lists.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'List',
                  onSelected: (id) => setState(() {
                    _listChosen = true;
                    _listId = id.isEmpty ? null : id;
                  }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('No list')),
                    for (final l in store.lists)
                      PopupMenuItem(value: l.id, child: Text('${l.emoji}  ${l.name}')),
                  ],
                  child: _OptionChip(
                    icon: Icons.folder_outlined,
                    label: selectedList == null
                        ? 'List'
                        : '${selectedList.emoji} ${selectedList.name}',
                    active: selectedList != null,
                  ),
                ),
              _OptionChip(
                icon: Icons.tune,
                label: 'More options',
                active: false,
                onTap: _openFullEditor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.onClear,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final content = Container(
      padding: EdgeInsets.fromLTRB(10, 6, onClear == null ? 12 : 4, 6),
      decoration: BoxDecoration(
        color: active ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? Colors.transparent : scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor ?? fg),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
          if (onClear != null)
            InkResponse(
              onTap: onClear,
              radius: 14,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 16, color: fg),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: content,
    );
  }
}
