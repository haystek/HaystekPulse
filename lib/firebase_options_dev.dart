// Dev Firebase project (haystek-pulse-dev). Used by: flutter run --flavor dev
// Made from android/app/src/dev/google-services.json and
// ios/config/dev/GoogleService-Info.plist.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return android;
        case TargetPlatform.iOS:
          return ios;
        default:
          break;
      }
    }
    throw UnsupportedError('Dev build: Android and iPhone only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCgY8Cj5pyzzuvtD2p0ebsEdDw9NvRZCvo',
    appId: '1:760971786685:android:f51684be530a6ed4b4fad4',
    messagingSenderId: '760971786685',
    projectId: 'haystek-pulse-dev',
    storageBucket: 'haystek-pulse-dev.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyABAEhym0eSayrT6tTLSwN-dYl-1ra2Jq0',
    appId: '1:760971786685:ios:032a6c4f3ac12ff6b4fad4',
    messagingSenderId: '760971786685',
    projectId: 'haystek-pulse-dev',
    storageBucket: 'haystek-pulse-dev.firebasestorage.app',
    iosBundleId: 'com.haystek.haystekPulse',
  );
}
