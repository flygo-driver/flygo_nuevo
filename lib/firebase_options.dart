// Android: flygo-rd / com.flygo.rd2 (Play Store)
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // 🌐 WEB
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD9hmXBF2HX5mTWlYubbL84zuONAT950w0',
    appId: '1:237301602510:web:62c537a6e3fe7e6859589f',
    messagingSenderId: '237301602510',
    projectId: 'flygo-rd',
    authDomain: 'flygo-rd.firebaseapp.com',
    storageBucket: 'flygo-rd.firebasestorage.app',
    measurementId: 'G-Q3YEXEKHX4',
  );

  // 🤖 ANDROID — flygo-rd / com.flygo.rd2
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDp-DhgbYE70S0PrpuXzbdZ41Ojs-hKh0w',
    appId: '1:237301602510:android:abf9f6fb3992a51259589f',
    messagingSenderId: '237301602510',
    projectId: 'flygo-rd',
    storageBucket: 'flygo-rd.firebasestorage.app',
  );

  // 🍎 iOS
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD7fyU8LwTh_64WY_ArI6Nm8J29UrQEiAs',
    appId: '1:237301602510:ios:f1acf596c68ff9bf59589f',
    messagingSenderId: '237301602510',
    projectId: 'flygo-rd',
    storageBucket: 'flygo-rd.firebasestorage.app',
    iosBundleId: 'com.flygo.rd2',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyD7fyU8LwTh_64WY_ArI6Nm8J29UrQEiAs',
    appId: '1:237301602510:ios:f1acf596c68ff9bf59589f',
    messagingSenderId: '237301602510',
    projectId: 'flygo-rd',
    storageBucket: 'flygo-rd.firebasestorage.app',
    iosBundleId: 'com.flygo.rd2',
  );

  // 🪟 WINDOWS
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD9hmXBF2HX5mTWlYubbL84zuONAT950w0',
    appId: '1:237301602510:web:9cc0e64c00dc60f059589f',
    messagingSenderId: '237301602510',
    projectId: 'flygo-rd',
    authDomain: 'flygo-rd.firebaseapp.com',
    storageBucket: 'flygo-rd.firebasestorage.app',
    measurementId: 'G-K4415HDX4',
  );
}
