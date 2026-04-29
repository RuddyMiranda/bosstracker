import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart" show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Reemplaza este archivo ejecutando `flutterfire configure`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          "Plataforma no soportada en este proyecto (por ahora).",
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCg6qoQwSFohtYyMv2TgcwSMc1mKC0VMZc',
    appId: '1:551025639019:web:d9ed8e85bb93c8a71efb2e',
    messagingSenderId: '551025639019',
    projectId: 'bosstracker-9f91f',
    authDomain: 'bosstracker-9f91f.firebaseapp.com',
    storageBucket: 'bosstracker-9f91f.firebasestorage.app',
    measurementId: 'G-4SSE2ST2FX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD5i3q7XxrS_339LxE6bKNRZorNhvx39_g',
    appId: '1:551025639019:android:2dfd79c0fc4712251efb2e',
    messagingSenderId: '551025639019',
    projectId: 'bosstracker-9f91f',
    storageBucket: 'bosstracker-9f91f.firebasestorage.app',
  );

}
