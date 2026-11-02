import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_list.dart';
import '../utils/format.dart';
import 'common.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.list,
    required this.showList,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleDone,
    required this.onToggleImportant,
    this.dragHandle,
  });

  final Task task;
  final TaskList? list;
  final bool showList;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleImportant;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final overdue = task.isOverdue(now);
    final muted = scheme.onSurfaceVariant;

    final meta = <Widget>[
      if (showList && list != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(list!.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              list!.name,
              style: theme.textTheme.labelSmall?.copyWith(color: Color(list!.color)),
            ),
          ],
        ),
      if (task.due != null)
        MetaChip(
          icon: overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
          label: overdue ? 'Overdue · ${formatDue(task, now: now)}' : formatDue(task, now: now),
          color: task.done
              ? muted
              : overdue
                  ? overdueColor(scheme)
                  : task.isDueToday(now)
                      ? scheme.primary
                      : muted,
        ),
      if (task.reminder != ReminderOffset.none && task.due != null && !task.done)
        Tooltip(
          message: task.reminder.label,
          child: Icon(Icons.notifications_active_outlined, size: 14, color: muted),
        ),
      if (task.repeat != Repeat.none)
        MetaChip(icon: Icons.repeat, label: task.repeat.label),
      if (task.subtasks.isNotEmpty)
        MetaChip(
          icon: Icons.checklist,
          label: '${task.subtasksDone}/${task.subtasks.length}',
          color: task.subtasksDone == task.subtasks.length ? scheme.primary : muted,
        ),
      if (task.priority != TaskPriority.none && !task.done)
        MetaChip(
          icon: Icons.flag,
          label: task.priority.label,
          color: priorityColor(task.priority, scheme),
        ),
      if (task.notes.trim().isNotEmpty)
        Icon(Icons.notes, size: 14, color: muted),
    ];

    final background = selected
        ? scheme.primaryContainer
        : cardColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (selectionMode)
                  Checkbox(value: selected, onChanged: (_) => onTap())
                else
                  CheckCircle(
                    checked: task.done,
                    color: priorityColor(task.priority, scheme),
                    onTap: onToggleDone,
                    tooltip: task.done ? 'Mark as not done' : 'Mark as done',
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            decoration: task.done ? TextDecoration.lineThrough : null,
                            color: task.done ? muted : null,
                          ),
                        ),
                        if (task.notes.trim().isNotEmpty && !task.done)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              task.notes.trim().split('\n').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: muted),
                            ),
                          ),
                        if (meta.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: meta,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: task.important ? 'Remove from Important' : 'Mark as important',
                  onPressed: selectionMode ? null : onToggleImportant,
                  icon: Icon(
                    task.important ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: task.important ? const Color(0xFFF59E0B) : muted,
                  ),
                ),
                if (dragHandle != null) dragHandle!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
