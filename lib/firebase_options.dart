// Ligação da app ao projeto Firebase "mia-comercio".
// Os valores vêm de: Firebase → Project settings → Your apps.
// (Estas chaves não são secretas: a segurança está nas regras do Firestore.)
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Plataforma não configurada.');
  }

  // Web app (iPad, telemóveis e computador pelo browser)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD_eg9g1Nl71TMZNeBqWd8XlsBs-quMREM',
    appId: '1:1061289111896:web:40ec991fcc10e17efc752d',
    messagingSenderId: '1061289111896',
    projectId: 'mia-comercio',
    authDomain: 'mia-comercio.firebaseapp.com',
    storageBucket: 'mia-comercio.firebasestorage.app',
  );

  // Android app (.apk) — preencher quando registar a app Android no Firebase
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PREENCHER',
    appId: 'PREENCHER',
    messagingSenderId: 'PREENCHER',
    projectId: 'mia-comercio',
    storageBucket: 'PREENCHER',
  );
}
