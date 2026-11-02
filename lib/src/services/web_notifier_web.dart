import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class WebNotifier {
  static bool get isSupported {
    try {
      return globalContext.has('Notification');
    } catch (_) {
      return false;
    }
  }

  static String get _permission {
    if (!isSupported) return 'denied';
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'denied';
    }
  }

  static bool get isGranted => _permission == 'granted';
  static bool get isDenied => _permission == 'denied';

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (isGranted) return true;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body) {
    if (!isGranted) return;
    try {
      web.Notification(
        title,
        web.NotificationOptions(body: body, icon: 'icons/Icon-192.png'),
      );
    } catch (_) {
      // Some browsers only allow notifications from a service worker.
    }
  }
}
