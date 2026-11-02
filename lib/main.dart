import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/storage.dart';
import 'src/services/notification_service.dart';
import 'src/state/task_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService.instance;
  await notifications.init();
  final store = TaskStore(storage: PrefsStorage(), reminders: notifications);
  await store.load();
  runApp(MyTasksApp(store: store));
}
