import 'package:flutter/material.dart';

import '../app.dart';
import '../models/task_list.dart';
import '../state/task_store.dart';
import 'common.dart';
import 'list_dialog.dart';
import 'settings_page.dart';

/// Navigation between smart views and lists. Used as a drawer on phones and
/// a permanent panel on wide screens.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onNavigate});

  /// Called after the user picks something (closes the drawer on phones).
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget nav(TaskView view, IconData icon, IconData selectedIcon, Color iconColor) {
      final selected = store.view == view;
      final count = store.activeCount(view);
      return _NavTile(
        selected: selected,
        leading: Icon(selected ? selectedIcon : icon, color: iconColor),
        title: store.viewTitle(view),
        count: count,
        onTap: () {
          store.setView(view);
          onNavigate();
        },
      );
    }

    return Material(
      color: cardColor(context),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(Icons.task_alt_rounded, color: scheme.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Tasks',
                            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Plan it. Do it.',
                            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            nav(TaskView.today, Icons.wb_sunny_outlined, Icons.wb_sunny, const Color(0xFFF59E0B)),
            nav(TaskView.upcoming, Icons.event_outlined, Icons.event, const Color(0xFF0EA5E9)),
            nav(TaskView.important, Icons.star_outline_rounded, Icons.star_rounded, const Color(0xFFF59E0B)),
            nav(TaskView.all, Icons.inbox_outlined, Icons.inbox, scheme.primary),
            nav(TaskView.completed, Icons.task_alt_outlined, Icons.task_alt, const Color(0xFF16A34A)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('LISTS',
                        style: textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant, letterSpacing: 1.1)),
                  ),
                  IconButton(
                    tooltip: 'New list',
                    icon: const Icon(Icons.add),
                    onPressed: () => _createList(context),
                  ),
                ],
              ),
            ),
            for (final list in store.lists)
              _NavTile(
                selected: store.view == TaskView(ViewKind.list, list.id),
                leading: Text(list.emoji, style: const TextStyle(fontSize: 20)),
                title: list.name,
                count: store.activeCount(TaskView(ViewKind.list, list.id)),
                accent: Color(list.color),
                onTap: () {
                  store.setView(TaskView(ViewKind.list, list.id));
                  onNavigate();
                },
                menu: PopupMenuButton<String>(
                  tooltip: 'List options',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') _editList(context, list);
                    if (value == 'delete') _deleteList(context, list);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Rename / change icon')),
                    PopupMenuItem(value: 'delete', child: Text('Delete list')),
                  ],
                ),
              ),
            if (store.lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('No lists yet. Tap + to create one.',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),
            _NavTile(
              selected: false,
              leading: Icon(Icons.settings_outlined, color: scheme.onSurfaceVariant),
              title: 'Settings',
              count: 0,
              onTap: () {
                onNavigate();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createList(BuildContext context) async {
    final store = StoreScope.read(context);
    final draft = await showListDialog(context);
    if (draft == null) return;
    final list = store.addList(draft.name, draft.emoji, draft.color);
    store.setView(TaskView(ViewKind.list, list.id));
    onNavigate();
  }

  Future<void> _editList(BuildContext context, TaskList list) async {
    final store = StoreScope.read(context);
    final draft = await showListDialog(context, existing: list);
    if (draft == null) return;
    store.updateList(list.copyWith(name: draft.name, emoji: draft.emoji, color: draft.color));
  }

  Future<void> _deleteList(BuildContext context, TaskList list) async {
    final store = StoreScope.read(context);
    final count = store.tasks.where((t) => t.listId == list.id).length;
    final ok = await confirmDialog(
      context,
      title: 'Delete "${list.name}"?',
      message: count == 0
          ? 'This list is empty.'
          : 'Its $count task${count == 1 ? '' : 's'} will be kept and moved to All tasks.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) store.deleteList(list.id);
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.selected,
    required this.leading,
    required this.title,
    required this.count,
    required this.onTap,
    this.accent,
    this.menu,
  });

  final bool selected;
  final Widget leading;
  final String title;
  final int count;
  final VoidCallback onTap;
  final Color? accent;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, menu == null ? 10 : 2, 4, menu == null ? 10 : 2),
            child: Row(
              children: [
                SizedBox(width: 28, child: Center(child: leading)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? scheme.onSecondaryContainer : null,
                        ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (accent ?? scheme.primary).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: accent ?? scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                if (menu != null) menu! else const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
