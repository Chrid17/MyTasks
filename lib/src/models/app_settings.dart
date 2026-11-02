import 'package:flutter/material.dart';

import 'task.dart';

enum SortMode { manual, dueDate, priority, created, alphabetical }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.manual => 'My order',
        SortMode.dueDate => 'Due date',
        SortMode.priority => 'Priority',
        SortMode.created => 'Newest first',
        SortMode.alphabetical => 'Alphabetical',
      };

  IconData get icon => switch (this) {
        SortMode.manual => Icons.drag_indicator,
        SortMode.dueDate => Icons.event_outlined,
        SortMode.priority => Icons.flag_outlined,
        SortMode.created => Icons.schedule,
        SortMode.alphabetical => Icons.sort_by_alpha,
      };
}

enum StatusFilter { all, active, completed }

/// Accent colours the user can pick in Settings.
const List<Color> accentColors = [
  Color(0xFF7C3AED),
  Color(0xFF2563EB),
  Color(0xFF0D9488),
  Color(0xFF16A34A),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFFDC2626),
  Color(0xFF475569),
];

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.accentIndex = 0,
    this.defaultReminder = ReminderOffset.atDue,
    this.sortMode = SortMode.manual,
  });

  final ThemeMode themeMode;
  final int accentIndex;

  /// Reminder applied to new tasks that get a due time.
  final ReminderOffset defaultReminder;
  final SortMode sortMode;

  Color get accent => accentIndex >= 0 && accentIndex < accentColors.length
      ? accentColors[accentIndex]
      : accentColors.first;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? accentIndex,
    ReminderOffset? defaultReminder,
    SortMode? sortMode,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accentIndex: accentIndex ?? this.accentIndex,
        defaultReminder: defaultReminder ?? this.defaultReminder,
        sortMode: sortMode ?? this.sortMode,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accentIndex': accentIndex,
        'defaultReminder': defaultReminder.name,
        'sortMode': sortMode.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final accent = json['accentIndex'];
    return AppSettings(
      themeMode: enumByName(ThemeMode.values, json['themeMode'], ThemeMode.system),
      accentIndex: accent is int ? accent : 0,
      defaultReminder: enumByName(
          ReminderOffset.values, json['defaultReminder'], ReminderOffset.atDue),
      sortMode: enumByName(SortMode.values, json['sortMode'], SortMode.manual),
    );
  }
}
