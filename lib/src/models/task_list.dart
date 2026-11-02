import 'task.dart';

/// A user-created list such as "Work" or "Shopping".
class TaskList {
  const TaskList({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
  });

  final String id;
  final String name;
  final String emoji;

  /// ARGB colour value.
  final int color;

  TaskList copyWith({String? name, String? emoji, int? color}) => TaskList(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'emoji': emoji, 'color': color};

  factory TaskList.fromJson(Map<String, dynamic> json) {
    final color = json['color'];
    return TaskList(
      id: (json['id'] as String?) ?? newId(),
      name: (json['name'] as String?) ?? 'List',
      emoji: (json['emoji'] as String?) ?? '📋',
      color: color is int ? color : 0xFF7C3AED,
    );
  }
}

const List<String> listEmojis = [
  '📋', '🏠', '💼', '🛒', '🎓', '💪', '💰', '✈️',
  '🎯', '📚', '🍽️', '🧹', '🎉', '❤️', '🌱', '💻',
];

const List<int> listColors = [
  0xFF7C3AED, // violet
  0xFF2563EB, // blue
  0xFF0D9488, // teal
  0xFF16A34A, // green
  0xFFEA580C, // orange
  0xFFDB2777, // pink
  0xFFDC2626, // red
  0xFF475569, // slate
];
