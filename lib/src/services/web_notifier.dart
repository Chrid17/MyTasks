// Browser notifications on the web; does nothing on other platforms.
export 'web_notifier_stub.dart'
    if (dart.library.js_interop) 'web_notifier_web.dart';
