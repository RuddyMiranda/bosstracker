import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "compat/web_url_cleanup.dart";
import "firebase_options.dart";

/// Inicia Firebase y solo entonces monta [child].
class FirebaseBootstrapGate extends StatefulWidget {
  const FirebaseBootstrapGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirebaseBootstrapGate> createState() => _FirebaseBootstrapGateState();
}

class _FirebaseBootstrapGateState extends State<FirebaseBootstrapGate> {
  static const Color _splashBg = Color(0xFF0B0D12);

  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_warmUp());
  }

  Future<void> _warmUp() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (kIsWeb) {
        await FirebaseAuth.instance.getRedirectResult();
        normalizeWebPathAndFragment();
      }
      // Esperar el primer estado de auth: en web restore async evita redirect bucle /
      // (/login cuando currentUser aún es null un frame).
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .timeout(const Duration(seconds: 12))
            .first;
      } on TimeoutException {
        /* montar igual */
      }
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      assert(() {
        debugPrint("$e\n$st");
        return true;
      }());
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: _splashBg,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "No se pudo iniciar Firebase: $_error",
                style: const TextStyle(color: Color(0xFFE8E9FF)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          backgroundColor: _splashBg,
          body: Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF39FF14),
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
