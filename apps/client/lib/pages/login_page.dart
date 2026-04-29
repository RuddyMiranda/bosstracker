import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../services.dart";

class LoginPage extends StatefulWidget {
  final AuthService auth;
  const LoginPage({super.key, required this.auth});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInGoogle();
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser != null) {
        context.go("/");
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "OSR Boss Tracker",
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Inicia sesión con tu cuenta de Google para continuar.",
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _loading ? null : _google,
                    icon: const Icon(Icons.login),
                    label: Text(_loading ? "..." : "Continuar con Google"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

