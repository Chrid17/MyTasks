import 'package:flutter/material.dart';

import 'state/task_store.dart';
import 'ui/home_page.dart';

/// Makes the [TaskStore] available to every widget below it.
class StoreScope extends InheritedNotifier<TaskStore> {
  const StoreScope({super.key, required TaskStore store, required super.child})
      : super(notifier: store);

  /// The store, rebuilding the caller when it changes.
  static TaskStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// The store, without listening (for callbacks).
  static TaskStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

ThemeData buildTheme(Color seed, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final light = brightness == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? scheme.surfaceContainerLow : scheme.surface,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
  );
}

class MyTasksApp extends StatelessWidget {
  const MyTasksApp({super.key, required this.store, this.enableReminders = true});

  final TaskStore store;

  /// Turned off in widget tests, which can't have running timers.
  final bool enableReminders;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final settings = store.settings;
          return MaterialApp(
            title: 'My Tasks',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: buildTheme(settings.accent, Brightness.light),
            darkTheme: buildTheme(settings.accent, Brightness.dark),
            home: HomePage(enableReminders: enableReminders),
          );
        },
      ),
    );
  }
}
