class WebNotifier {
  static bool get isSupported => false;
  static bool get isGranted => false;
  static bool get isDenied => false;
  static Future<bool> requestPermission() async => false;
  static void show(String title, String body) {}
}
