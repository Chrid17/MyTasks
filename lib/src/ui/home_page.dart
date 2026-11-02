import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/app_settings.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';
import '../utils/format.dart';
import 'common.dart';
import 'quick_add_bar.dart';
import 'settings_page.dart';
import 'sidebar.dart';
import 'task_editor_page.dart';
import 'task_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.enableReminders = true});

  /// Turned off in widget tests, which can't have running timers.
  final bool enableReminders;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _quickAddFocus = FocusNode();
  StreamSubscription<Task>? _dueSub;
  StreamSubscription<String>? _tapSub;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final store = StoreScope.read(context);
    _dueSub = store.dueReminders.listen(_onReminderDue);
    _tapSub = NotificationService.instance.taps.listen(_openTaskById);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.enableReminders) store.startReminderTicker();
      final launchId = NotificationService.instance.launchTaskId;
      if (launchId != null) {
        NotificationService.instance.launchTaskId = null;
        _openTaskById(launchId);
      }
    });
  }

  @override
  void dispose() {
    _dueSub?.cancel();
    _tapSub?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _onReminderDue(Task task) {
    if (!mounted) return;
    showMessage(
      context,
      '⏰ ${task.title}${task.due != null ? ' · ${formatDue(task)}' : ''}',
      actionLabel: 'Open',
      onAction: () => _openTaskById(task.id),
      duration: const Duration(seconds: 8),
    );
  }

  void _openTaskById(String id) {
    if (!mounted) return;
    final task = StoreScope.read(context).taskById(id);
    if (task != null) TaskEditorPage.open(context, task);
  }

  void _newTask() {
    final store = StoreScope.read(context);
    if (store.view.kind == ViewKind.completed) store.setView(TaskView.all);
    TaskEditorPage.open(context, store.createDraft(), isNew: true);
  }

  void _toggleDone(Task task) {
    final store = StoreScope.read(context);
    final snapshot = store.snapshot();
    final next = store.toggleDone(task.id);
    if (task.done) return;
    final nextDue = next?.due;
    showMessage(
      context,
      nextDue == null
          ? 'Completed "${task.title}"'
          : 'Completed. Next one due ${formatDue(next!)}',
      actionLabel: 'Undo',
      onAction: () => store.restore(snapshot),
    );
  }

  void _delete(List<String> ids) {
    if (ids.isEmpty) return;
    final store = StoreScope.read(context);
    final snapshot = store.snapshot();
    store.deleteTasks(ids);
    showMessage(
      context,
      ids.length == 1 ? 'Task deleted' : '${ids.length} tasks deleted',
      actionLabel: 'Undo',
      onAction: () => store.restore(snapshot),
    );
  }

  void _clearCompleted() {
    final store = StoreScope.read(context);
    final count = store.visibleTasks.where((t) => t.done).length;
    if (count == 0) {
      showMessage(context, 'No completed tasks here.');
      return;
    }
    final snapshot = store.snapshot();
    final removed = store.clearCompleted();
    if (!mounted) return;
    showMessage(
      context,
      'Cleared ${pluralize(removed, 'completed task')}',
      actionLabel: 'Undo',
      onAction: () => store.restore(snapshot),
    );
  }

  void _bulk(String action) {
    final store = StoreScope.read(context);
    final ids = store.selectedIds.toList();
    if (ids.isEmpty) return;
    final snapshot = store.snapshot();
    final now = DateTime.now();
    String message;
    if (action == 'done') {
      store.setDone(ids, true);
      message = 'Marked ${pluralize(ids.length, 'task')} as done';
    } else if (action == 'undone') {
      store.setDone(ids, false);
      message = 'Marked ${pluralize(ids.length, 'task')} as not done';
    } else if (action == 'important') {
      store.setImportant(ids, true);
      message = 'Marked as important';
    } else if (action == 'unimportant') {
      store.setImportant(ids, false);
      message = 'Removed from Important';
    } else if (action.startsWith('priority:')) {
      final p = enumByName(TaskPriority.values, action.substring(9), TaskPriority.none);
      store.setPriority(ids, p);
      message = 'Priority set to ${p.label}';
    } else if (action == 'due:today') {
      store.setDue(ids, dateOnly(now));
      message = 'Moved to today';
    } else if (action == 'due:tomorrow') {
      store.setDue(ids, dateOnly(now).add(const Duration(days: 1)));
      message = 'Moved to tomorrow';
    } else if (action == 'due:none') {
      store.setDue(ids, null);
      message = 'Due dates removed';
    } else if (action.startsWith('list:')) {
      final id = action.substring(5);
      store.moveToList(ids, id.isEmpty ? null : id);
      final list = store.listById(id);
      message = list == null ? 'Removed from lists' : 'Moved to ${list.name}';
    } else {
      return;
    }
    store.endSelection();
    showMessage(context, message, actionLabel: 'Undo', onAction: () => store.restore(snapshot));
  }

  Future<void> _deleteSelected() async {
    final store = StoreScope.read(context);
    final ids = store.selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete ${pluralize(ids.length, 'task')}?',
      message: 'You can undo this straight after.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    store.endSelection();
    _delete(ids);
  }

  void _escape() {
    final store = StoreScope.read(context);
    if (store.selectionMode) {
      store.endSelection();
    } else if (_search.text.isNotEmpty) {
      _search.clear();
      store.setQuery('');
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final showFab = !store.selectionMode;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newTask,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newTask,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final fab = showFab
                ? FloatingActionButton.extended(
                    onPressed: _newTask,
                    icon: const Icon(Icons.add),
                    label: const Text('New task'),
                  )
                : null;
            final pane = _buildPane(context, store, wide);
            if (wide) {
              return Scaffold(
                body: Row(
                  children: [
                    SizedBox(width: 290, child: Sidebar(onNavigate: () {})),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: SafeArea(left: false, child: pane)),
                  ],
                ),
                floatingActionButton: fab,
              );
            }
            return Scaffold(
              key: _scaffoldKey,
              drawer: Drawer(
                child: Sidebar(onNavigate: () => _scaffoldKey.currentState?.closeDrawer()),
              ),
              body: SafeArea(child: pane),
              floatingActionButton: fab,
            );
          },
        ),
      ),
    );
  }

  Widget _buildPane(BuildContext context, TaskStore store, bool wide) {
    final tasks = store.visibleTasks;
    final active = tasks.where((t) => !t.done).toList();
    final done = tasks.where((t) => t.done).toList();
    final manual = store.settings.sortMode == SortMode.manual &&
        store.query.trim().isEmpty &&
        !store.selectionMode;
    final showDoneHeader = active.isNotEmpty && done.isNotEmpty;
    final itemCount = active.length + done.length + (showDoneHeader ? 1 : 0);
    final showList = store.view.kind != ViewKind.list;
    final horizontal = wide ? 32.0 : 16.0;

    Widget buildTask(Task task, int index) {
      final tile = TaskTile(
        task: task,
        list: store.listById(task.listId),
        showList: showList,
        selectionMode: store.selectionMode,
        selected: store.isSelected(task.id),
        onTap: () {
          if (store.selectionMode) {
            store.toggleSelected(task.id);
          } else {
            TaskEditorPage.open(context, task);
          }
        },
        onLongPress: () {
          if (store.selectionMode) {
            store.toggleSelected(task.id);
          } else {
            store.startSelection(task.id);
          }
        },
        onToggleDone: () => _toggleDone(task),
        onToggleImportant: () => store.toggleImportant(task.id),
        dragHandle: manual && !task.done
            ? ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
              )
            : null,
      );
      if (store.selectionMode) {
        return KeyedSubtree(key: ValueKey(task.id), child: tile);
      }
      return Dismissible(
        key: ValueKey(task.id),
        background: _SwipeBackground(
          color: const Color(0xFF16A34A),
          icon: task.done ? Icons.undo : Icons.check,
          label: task.done ? 'Not done' : 'Done',
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: _SwipeBackground(
          color: Theme.of(context).colorScheme.error,
          icon: Icons.delete_outline,
          label: 'Delete',
          alignment: Alignment.centerRight,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            _toggleDone(task);
            return false;
          }
          return true;
        },
        onDismissed: (_) => _delete([task.id]),
        child: tile,
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ReorderableListView.builder(
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 120),
          buildDefaultDragHandles: false,
          header: _buildHeader(context, store, wide),
          itemCount: tasks.isEmpty ? 1 : itemCount,
          onReorder: (oldIndex, newIndex) {
            if (!manual || oldIndex >= active.length) return;
            store.reorder(active, oldIndex, newIndex > active.length ? active.length : newIndex);
          },
          itemBuilder: (context, index) {
            if (tasks.isEmpty) {
              return _EmptyState(key: const ValueKey('__empty__'), store: store);
            }
            if (index < active.length) return buildTask(active[index], index);
            if (showDoneHeader && index == active.length) {
              return _CompletedHeader(
                key: const ValueKey('__completed_header__'),
                count: done.length,
                onClear: _clearCompleted,
              );
            }
            final doneIndex = index - active.length - (showDoneHeader ? 1 : 0);
            return buildTask(done[doneIndex], index);
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TaskStore store, bool wide) {
    final stats = store.statsFor(store.view);
    final isCompletedView = store.view.kind == ViewKind.completed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        store.selectionMode
            ? _buildSelectionBar(context, store)
            : _buildTitleRow(context, store, wide),
        const SizedBox(height: 16),
        _StatsRow(
          stats: stats,
          onActive: () => store.setFilter(StatusFilter.active),
          onDone: () {
            if (!isCompletedView) store.setFilter(StatusFilter.completed);
          },
          onToday: () => store.setView(TaskView.today),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: store.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search tasks',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      store.setQuery('');
                    },
                  ),
            filled: true,
            fillColor: cardColor(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (!isCompletedView && !store.selectionMode) ...[
          const SizedBox(height: 12),
          QuickAddBar(focusNode: _quickAddFocus),
        ],
        const SizedBox(height: 12),
        if (!isCompletedView) _buildFilterRow(context, store, stats),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context, TaskStore store, bool wide) {
    final theme = Theme.of(context);
    final view = store.view;
    final list = view.kind == ViewKind.list ? store.listById(view.listId) : null;
    final title = list == null ? store.viewTitle(view) : '${list.emoji}  ${list.name}';
    return Row(
      children: [
        if (!wide)
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: wide ? 0 : 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: list == null ? theme.colorScheme.primary : Color(list.color),
                  ),
                ),
                Text(
                  formatLongDate(DateTime.now()),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<SortMode>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: store.settings.sortMode,
          onSelected: (mode) => store.updateSettings(store.settings.copyWith(sortMode: mode)),
          itemBuilder: (_) => [
            const PopupMenuItem<SortMode>(enabled: false, child: Text('Sort by')),
            for (final mode in SortMode.values)
              CheckedPopupMenuItem<SortMode>(
                value: mode,
                checked: store.settings.sortMode == mode,
                child: Text(mode.label),
              ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'select':
                store.startSelection();
              case 'clear':
                _clearCompleted();
              case 'settings':
                _openSettings();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'select',
              child: ListTile(leading: Icon(Icons.checklist), title: Text('Select tasks')),
            ),
            PopupMenuItem(
              value: 'clear',
              child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Clear completed')),
            ),
            PopupMenuItem(
              value: 'settings',
              child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context, TaskStore store) {
    final theme = Theme.of(context);
    final count = store.selectedIds.length;
    final hasSelection = count > 0;
    final visibleIds = store.visibleTasks.map((t) => t.id).toList();
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel selection',
            icon: const Icon(Icons.close),
            onPressed: store.endSelection,
          ),
          Expanded(
            child: Text(
              hasSelection ? '$count selected' : 'Select tasks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(Icons.select_all),
            onPressed: () => store.selectAll(visibleIds),
          ),
          IconButton(
            tooltip: 'Mark as done',
            icon: const Icon(Icons.done_all),
            onPressed: hasSelection ? () => _bulk('done') : null,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: hasSelection ? scheme.error : null),
            onPressed: hasSelection ? _deleteSelected : null,
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            enabled: hasSelection,
            icon: const Icon(Icons.more_vert),
            onSelected: _bulk,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'undone', child: Text('Mark as not done')),
              const PopupMenuItem(value: 'important', child: Text('Mark as important')),
              const PopupMenuItem(value: 'unimportant', child: Text('Remove from Important')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'due:today', child: Text('Due today')),
              const PopupMenuItem(value: 'due:tomorrow', child: Text('Due tomorrow')),
              const PopupMenuItem(value: 'due:none', child: Text('Remove due date')),
              const PopupMenuDivider(),
              for (final p in TaskPriority.values.reversed)
                PopupMenuItem(
                  value: 'priority:${p.name}',
                  child: Text(p == TaskPriority.none ? 'No priority' : '${p.label} priority'),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'list:', child: Text('Remove from list')),
              for (final l in store.lists)
                PopupMenuItem(value: 'list:${l.id}', child: Text('Move to ${l.emoji} ${l.name}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context, TaskStore store, ViewStats stats) {
    String label(StatusFilter f) => switch (f) {
          StatusFilter.all => 'All ${stats.total}',
          StatusFilter.active => 'Active ${stats.active}',
          StatusFilter.completed => 'Done ${stats.completed}',
        };
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in StatusFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label(f)),
                      selected: store.filter == f,
                      onSelected: (_) => store.setFilter(f),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!store.selectionMode)
          TextButton.icon(
            onPressed: () => store.startSelection(),
            icon: const Icon(Icons.checklist, size: 20),
            label: const Text('Select'),
          ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.onActive,
    required this.onDone,
    required this.onToday,
  });

  final ViewStats stats;
  final VoidCallback onActive;
  final VoidCallback onDone;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = [
      _StatCard(
        icon: Icons.radio_button_unchecked,
        color: scheme.primary,
        label: 'Active',
        value: '${stats.active}',
        onTap: onActive,
      ),
      _StatCard(
        icon: Icons.today_outlined,
        color: const Color(0xFFF59E0B),
        label: 'Due today',
        value: '${stats.dueToday}',
        onTap: onToday,
      ),
      _StatCard(
        icon: Icons.warning_amber_rounded,
        color: scheme.error,
        label: 'Overdue',
        value: '${stats.overdue}',
        onTap: onToday,
      ),
      _StatCard(
        icon: Icons.task_alt,
        color: const Color(0xFF16A34A),
        label: stats.total == 0 ? 'Done' : 'Done · ${(stats.progress * 100).round()}%',
        value: '${stats.completed}',
        onTap: onDone,
        progress: stats.progress,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(children: [
              Expanded(child: cards[0]),
              const SizedBox(width: gap),
              Expanded(child: cards[1]),
            ]),
            const SizedBox(height: gap),
            Row(children: [
              Expanded(child: cards[2]),
              const SizedBox(width: gap),
              Expanded(child: cards[3]),
            ]),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.progress,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: cardColor(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (progress != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedHeader extends StatelessWidget {
  const _CompletedHeader({super.key, required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
      child: Row(
        children: [
          Icon(Icons.task_alt, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Completed ($count)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft ? children : children.reversed.toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.store});

  final TaskStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = store.query.trim().isNotEmpty;
    final (IconData icon, String title, String subtitle) = searching
        ? (Icons.search_off, 'No matching tasks', 'Try a different search.')
        : switch (store.view.kind) {
            ViewKind.today => (Icons.wb_sunny_outlined, 'Nothing due today', 'Enjoy your day, or plan something new.'),
            ViewKind.upcoming => (Icons.event_available_outlined, 'Nothing coming up', 'Tasks with a future due date show here.'),
            ViewKind.important => (Icons.star_outline_rounded, 'No important tasks', 'Tap the star on a task to add it here.'),
            ViewKind.completed => (Icons.task_alt, 'No completed tasks yet', 'Tasks you finish will appear here.'),
            _ => store.filter == StatusFilter.completed
                ? (Icons.task_alt, 'Nothing completed yet', 'Finished tasks will show here.')
                : (Icons.playlist_add_check_rounded, 'You are all caught up', 'Add a task above to get started.'),
          };
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
