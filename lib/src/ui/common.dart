import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';

/// Background for cards and panels that sit on the page background.
Color cardColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.light
      ? scheme.surfaceContainerLowest
      : scheme.surfaceContainerHigh;
}

Color priorityColor(TaskPriority priority, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (priority) {
    TaskPriority.high => dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
    TaskPriority.medium => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    TaskPriority.low => dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
    TaskPriority.none => scheme.outline,
  };
}

Color overdueColor(ColorScheme scheme) => scheme.error;

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _currentSnack;

/// Shows a short message, optionally with an action such as "Undo".
/// It always closes itself after a few seconds.
void showMessage(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      showCloseIcon: actionLabel == null,
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
  _currentSnack = controller;
  controller.closed.then((_) {
    if (identical(_currentSnack, controller)) _currentSnack = null;
  });
  Timer(duration, () {
    if (identical(_currentSnack, controller)) {
      _currentSnack = null;
      try {
        messenger.hideCurrentSnackBar();
      } catch (_) {}
    }
  });
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// A rounded, priority-coloured check circle.
class CheckCircle extends StatelessWidget {
  const CheckCircle({
    super.key,
    required this.checked,
    required this.color,
    required this.onTap,
    this.size = 24,
    this.tooltip,
  });

  final bool checked;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = checked ? scheme.primary : Colors.transparent;
    final border = checked ? scheme.primary : color;
    final circle = InkResponse(
      onTap: onTap,
      radius: size,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
          child: checked
              ? Icon(Icons.check, size: size * 0.7, color: scheme.onPrimary)
              : null,
        ),
      ),
    );
    return Semantics(
      checked: checked,
      button: true,
      label: tooltip,
      child: tooltip == null ? circle : Tooltip(message: tooltip!, child: circle),
    );
  }
}

/// Small icon + text used in task metadata rows.
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
      ],
    );
  }
}
