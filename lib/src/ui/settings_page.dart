import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/app_settings.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _exactAlarms;

  @override
  void initState() {
    super.initState();
    _checkExactAlarms();
  }

  Future<void> _checkExactAlarms() async {
    if (!NotificationService.instance.isAndroid) return;
    final ok = await NotificationService.instance.canUseExactAlarms();
    if (mounted) setState(() => _exactAlarms = ok);
  }

  Future<void> _testNotification() async {
    final ok = await NotificationService.instance.showTest();
    if (!mounted) return;
    setState(() {});
    showMessage(
      context,
      ok
          ? 'Test notification sent.'
          : 'Notifications are blocked. Allow them in your device or browser settings.',
    );
  }

  Future<void> _export() async {
    final store = StoreScope.read(context);
    final json = store.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup copied'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your tasks have been copied to the clipboard. Paste them into a note, '
                'email or file to keep them safe. Use "Restore from backup" to bring them back.',
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final store = StoreScope.read(context);
    final controller = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text?.trim() ?? '';
    if (clipText.startsWith('{') || clipText.startsWith('[')) {
      controller.text = clipText;
    }
    if (!mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste a backup made with "Back up tasks".'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{ "app": "my_tasks", ... }',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('replace'),
            child: const Text('Replace all'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('merge'),
            child: const Text('Add to my tasks'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (mode == null || !mounted) return;
    try {
      final count = store.importJson(text, replace: mode == 'replace');
      showMessage(context, 'Restored ${count == 1 ? '1 task' : '$count tasks'}.');
    } on FormatException catch (e) {
      showMessage(context, e.message.isEmpty ? 'That backup could not be read.' : e.message);
    } catch (_) {
      showMessage(context, 'That backup could not be read.');
    }
  }

  Future<void> _clearCompleted() async {
    final store = StoreScope.read(context);
    final done = store.tasks.where((t) => t.done).map((t) => t.id).toList();
    if (done.isEmpty) {
      showMessage(context, 'There are no completed tasks.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Delete completed tasks?',
      message: '${done.length} completed task${done.length == 1 ? '' : 's'} will be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final snapshot = store.snapshot();
    store.deleteTasks(done);
    showMessage(context, 'Completed tasks deleted',
        actionLabel: 'Undo', onAction: () => store.restore(snapshot));
  }

  Future<void> _deleteEverything() async {
    final store = StoreScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'Delete all data?',
      message: 'All tasks and lists will be permanently deleted. Make a backup first if '
          'you might want them later.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!ok || !mounted) return;
    store.deleteAllData();
    showMessage(context, 'All data deleted.');
  }

  String get _reminderStatus => switch (NotificationService.instance.support) {
        ReminderSupport.always => 'Reminders arrive even when the app is closed.',
        ReminderSupport.whileOpen => kIsWeb
            ? 'Reminders arrive while this tab is open.'
            : 'Reminders arrive while My Tasks is open or minimised.',
        ReminderSupport.unavailable =>
          'Notifications are blocked. Reminders still show inside the app.',
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final settings = store.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _Group(
                  title: 'Appearance',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('Theme', style: theme.textTheme.titleSmall),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto_outlined),
                                label: Text('System')),
                            ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode_outlined),
                                label: Text('Light')),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode_outlined),
                                label: Text('Dark')),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              store.updateSettings(settings.copyWith(themeMode: s.first)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text('Accent colour', style: theme.textTheme.titleSmall),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < accentColors.length; i++)
                            Tooltip(
                              message: 'Accent ${i + 1}',
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    store.updateSettings(settings.copyWith(accentIndex: i)),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: accentColors[i],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: settings.accentIndex == i
                                          ? scheme.onSurface
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                  child: settings.accentIndex == i
                                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                _Group(
                  title: 'Reminders',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: const Text('Notifications'),
                      subtitle: Text(_reminderStatus),
                      trailing: TextButton(
                        onPressed: _testNotification,
                        child: const Text('Test'),
                      ),
                    ),
                    if (_exactAlarms == false)
                      ListTile(
                        leading: const Icon(Icons.alarm_on_outlined),
                        title: const Text('On-time reminders'),
                        subtitle: const Text(
                            'Android may delay reminders by a few minutes. Allow "Alarms & reminders" '
                            'so they arrive exactly on time.'),
                        trailing: TextButton(
                          onPressed: () async {
                            await NotificationService.instance.requestExactAlarms();
                            await _checkExactAlarms();
                          },
                          child: const Text('Allow'),
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Default reminder'),
                      subtitle: const Text('Used when you give a task a due time'),
                      trailing: PopupMenuButton<ReminderOffset>(
                        tooltip: 'Default reminder',
                        initialValue: settings.defaultReminder,
                        onSelected: (r) =>
                            store.updateSettings(settings.copyWith(defaultReminder: r)),
                        itemBuilder: (_) => [
                          for (final r in ReminderOffset.values)
                            PopupMenuItem(value: r, child: Text(r.label)),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(settings.defaultReminder.label,
                                  style: theme.textTheme.labelLarge
                                      ?.copyWith(color: scheme.primary)),
                              Icon(Icons.arrow_drop_down, color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _Group(
                  title: 'Your data',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Back up tasks'),
                      subtitle: const Text('Copy all tasks and lists to the clipboard'),
                      onTap: _export,
                    ),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Restore from backup'),
                      subtitle: const Text('Paste a backup to bring tasks back'),
                      onTap: _import,
                    ),
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('Delete completed tasks'),
                      onTap: _clearCompleted,
                    ),
                    ListTile(
                      leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                      title: Text('Delete all data', style: TextStyle(color: scheme.error)),
                      onTap: _deleteEverything,
                    ),
                  ],
                ),
                _Group(
                  title: 'About',
                  children: [
                    const ListTile(
                      leading: Icon(Icons.task_alt),
                      title: Text('My Tasks'),
                      subtitle: Text('Version 2.0.0 · Made by Christian Bwendo'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Private by design'),
                      subtitle: Text('Your tasks are stored only on this device.'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.keyboard_outlined),
                      title: const Text('Keyboard shortcuts'),
                      subtitle: Text(
                        defaultTargetPlatform == TargetPlatform.macOS
                            ? '⌘N new task · ⌘F search · Esc cancel'
                            : 'Ctrl+N new task · Ctrl+F search · Esc cancel',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
