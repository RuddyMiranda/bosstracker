import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "app_controller.dart";
import "compat/web_url_cleanup.dart";
import "firebase_bootstrap_gate.dart";
import "pages/boss_detail_page.dart";
import "pages/boss_list_page.dart";
import "pages/login_page.dart";
import "pages/settings_page.dart";
import "pages/web_admin_page.dart";
import "services.dart";

String _normalizePath(String p) {
  if (p.isEmpty) return "/";
  return p.length > 1 && p.endsWith("/") ? p.substring(0, p.length - 1) : p;
}

/// Con [usePathUrlStrategy] el path real suele ser `/login`; se mantiene fallback al hash por enlaces antiguos #/….
String _routerInitialLocation() {
  if (!kIsWeb) return "/";
  var p = Uri.base.path;
  if (p.isEmpty || p == "/") {
    final raw = Uri.base.fragment.split("?").first;
    if (raw.isEmpty) return "/";
    p = raw.startsWith("/") ? raw : "/$raw";
  }
  return _normalizePath(p);
}

/// Ruta efectiva para el redirect (`matchedLocation`; `fullPath` en redirect global; fallback URI/hash).
String _effectivePath(GoRouterState state) {
  final m = state.matchedLocation;
  if (m.isNotEmpty) {
    return _normalizePath(m);
  }
  final fp = state.fullPath ?? "";
  if (fp.isNotEmpty) {
    return _normalizePath(fp);
  }
  var p = state.uri.path;
  if (kIsWeb && (p.isEmpty || p == "/")) {
    final frag = Uri.base.fragment.split("?").first;
    if (frag.isNotEmpty) {
      p = frag.startsWith("/") ? frag : "/$frag";
    }
  }
  return _normalizePath(p.isEmpty ? "/" : p);
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const FirebaseBootstrapGate(
      child: BossTrackerApp(),
    ),
  );
}

class BossTrackerApp extends StatefulWidget {
  const BossTrackerApp({super.key});

  @override
  State<BossTrackerApp> createState() => _BossTrackerAppState();
}

class _BossTrackerAppState extends State<BossTrackerApp> {
  final _controller = AppController();

  late final _auth = AuthService(FirebaseAuth.instance);
  late final _bosses = BossService(FirebaseFirestore.instance);
  late final _devices = DeviceService(FirebaseFirestore.instance, FirebaseMessaging.instance);
  
  static const _neonRed = Color(0xFFFF2D55);
  static const _neonGreen = Color(0xFF39FF14);
  static const _neonCyan = Color(0xFF00E5FF);
  static const _neonPurple = Color(0xFFB026FF);
  static const _neonPink = Color(0xFFFF2FB9);
  static const _bg = Color(0xFF0B0D12);
  static const _surface = Color(0xFF121524);

  late final GoRouter _router = GoRouter(
    initialLocation: _routerInitialLocation(),
    routes: [
      GoRoute(
        path: "/login",
        builder: (context, state) => LoginPage(auth: _auth),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(
          auth: _auth,
          controller: _controller,
          child: child,
        ),
        routes: [
          GoRoute(
            path: "/",
            builder: (context, state) => BossListPage(
              auth: _auth,
              controller: _controller,
              bosses: _bosses,
              devices: _devices,
            ),
            routes: [
              GoRoute(
                path: "boss/:bossId",
                builder: (context, state) => BossDetailPage(
                  bossId: state.pathParameters["bossId"]!,
                  auth: _auth,
                  controller: _controller,
                  bosses: _bosses,
                ),
              )
            ],
          ),
          GoRoute(
            path: "/settings",
            builder: (context, state) => SettingsPage(
              auth: _auth,
              controller: _controller,
              devices: _devices,
            ),
          ),
          GoRoute(
            path: "/admin",
            builder: (context, state) => WebAdminPage(
              auth: _auth,
              controller: _controller,
            ),
          )
        ],
      ),
    ],
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final path = _effectivePath(state);
      final loggingIn = path == "/login";

      if (user == null) {
        return loggingIn ? null : "/login";
      }
      if (loggingIn) {
        return "/";
      }
      return null;
    },
    // Solo auth: no incluir AppController aquí o cada notifyListeners() re-ejecuta
    // el redirect durante la primera carga y puede buclear con #/login en web.
    refreshListenable: GoRouterRefreshStream(
      FirebaseAuth.instance.authStateChanges(),
    ),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        normalizeWebPathAndFragment();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: "OSR Boss Tracker",
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: _neonGreen,
          onPrimary: Color(0xFF001400),
          secondary: _neonCyan,
          onSecondary: Color(0xFF001014),
          tertiary: _neonPurple,
          onTertiary: Color(0xFF140019),
          error: _neonRed,
          onError: Color(0xFF1A0006),
          surface: _surface,
          onSurface: Color(0xFFE8E9FF),
        ),
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: Color(0xFFE8E9FF),
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: _surface,
          indicatorColor: Color(0x3329FF9A),
        ),
        cardTheme: const CardThemeData(
          color: _surface,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _neonGreen,
            foregroundColor: const Color(0xFF001400),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _neonCyan,
            side: const BorderSide(color: _neonCyan),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _neonPink),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFF191D33),
          selectedColor: Color(0x3329FF9A),
          labelStyle: TextStyle(color: Color(0xFFE8E9FF)),
          secondaryLabelStyle: TextStyle(color: Color(0xFFE8E9FF)),
          side: BorderSide(color: Color(0xFF262B48)),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF262B48)),
      ),
      routerConfig: _router,
    );
  }
}

class MainScaffold extends StatelessWidget {
  final Widget child;
  final AuthService auth;
  final AppController controller;

  const MainScaffold({
    super.key,
    required this.child,
    required this.auth,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    int indexFromLocation(String loc) {
      if (loc.startsWith("/settings")) return 1;
      if (loc.startsWith("/admin")) return 2;
      return 0;
    }

    final selected = indexFromLocation(location);

    return Scaffold(
      appBar: AppBar(
        title: const Text("OSR Boss Tracker"),
        actions: [
          IconButton(
            tooltip: "Cerrar sesión",
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) context.go("/login");
            },
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.list), label: "Bosses"),
          const NavigationDestination(icon: Icon(Icons.settings), label: "Ajustes"),
          const NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: "Admin"),
        ],
        onDestinationSelected: (i) {
          if (i == 0) context.go("/");
          if (i == 1) context.go("/settings");
          if (i == 2) context.go("/admin");
        },
      ),
    );
  }
}

