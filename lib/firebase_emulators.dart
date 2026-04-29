import 'package:flutter/foundation.dart' show kDebugMode;

class FirebaseEmulators {
  static Future<void> connectIfNeeded() async {
    // ✅ en release NO hace nada
    if (!kDebugMode) return;
    // si en algún momento usas emuladores, lo activas en debug con flags
  }
}
