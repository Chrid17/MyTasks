import 'package:intl/intl.dart';

import '../models/task.dart';

/// "Today", "Tomorrow", "Friday", "Mon 3 Nov" or "3 Nov 2027".
String formatDay(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final diff = daysBetween(today, day);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat('EEEE').format(day);
  if (day.year == today.year) return DateFormat('EEE d MMM').format(day);
  return DateFormat('d MMM y').format(day);
}

String formatTime(DateTime time) => DateFormat('HH:mm').format(time);

/// Due label for a task, e.g. "Today, 14:30".
String formatDue(Task task, {DateTime? now}) {
  final due = task.due;
  if (due == null) return '';
  final day = formatDay(due, now: now);
  return task.hasTime ? '$day, ${formatTime(due)}' : day;
}

String formatLongDate(DateTime date) => DateFormat('EEEE, d MMMM').format(date);

String formatDateTime(DateTime date) =>
    DateFormat('d MMM y, HH:mm').format(date);

String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
