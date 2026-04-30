import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:intl/intl.dart";

import "../app_controller.dart";
import "../models.dart";
import "../services.dart";

/// Estado del LED junto al nombre del boss según última muerte y respawn.
enum _Pulse { red, green, gray }

_Pulse _pulseForBoss(BossDeath? latest, Duration expireGrace, DateTime now) {
  if (latest == null) return _Pulse.gray;
  final next = latest.nextRespawnAt;
  if (now.isBefore(next)) return _Pulse.red;
  final expired = next.isBefore(now.subtract(expireGrace));
  if (expired) return _Pulse.gray;
  return _Pulse.green;
}

/// Orden de filas: primero los que faltan para respawn, luego ventana verde, al final gris.
int _statusSortKey(_Pulse p) {
  return switch (p) {
    _Pulse.red => 0,
    _Pulse.green => 1,
    _Pulse.gray => 2,
  };
}

int _compareBossesByStatus(
  Boss a,
  Boss b, {
  required Map<String, BossDeath> latestByBoss,
  required DateTime now,
  required Duration expireGrace,
}) {
  final la = latestByBoss[a.id];
  final lb = latestByBoss[b.id];
  final pa = _pulseForBoss(la, expireGrace, now);
  final pb = _pulseForBoss(lb, expireGrace, now);
  final ka = _statusSortKey(pa);
  final kb = _statusSortKey(pb);
  if (ka != kb) return ka.compareTo(kb);

  switch (pa) {
    case _Pulse.red:
      return la!.nextRespawnAt.compareTo(lb!.nextRespawnAt);
    case _Pulse.green:
      // Ventana termina en next + grace; primero la que se cierra antes.
      final aEnd = la!.nextRespawnAt.add(expireGrace);
      final bEnd = lb!.nextRespawnAt.add(expireGrace);
      return aEnd.compareTo(bEnd);
    case _Pulse.gray:
      if (la == null && lb == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (la == null) return 1;
      if (lb == null) return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class _BossLedDot extends StatelessWidget {
  const _BossLedDot({required this.pulse});

  final _Pulse pulse;

  static const _r = Color(0xFFFF2D55);
  static const _g = Color(0xFF39FF14);
  static const _gr = Color(0xFF5C6378);

  @override
  Widget build(BuildContext context) {
    final Color core;
    final List<BoxShadow>? shadows;
    switch (pulse) {
      case _Pulse.red:
        core = _r;
        shadows = [BoxShadow(color: _r.withValues(alpha: 0.65), blurRadius: 10, spreadRadius: 0)];
      case _Pulse.green:
        core = _g;
        shadows = [BoxShadow(color: _g.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 1)];
      case _Pulse.gray:
        core = _gr;
        shadows = null;
    }
    return SizedBox(
      width: 10,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: core,
          boxShadow: shadows,
        ),
      ),
    );
  }
}

class BossListPage extends StatefulWidget {
  final AuthService auth;
  final AppController controller;
  final BossService bosses;
  final DeviceService devices;

  const BossListPage({
    super.key,
    required this.auth,
    required this.controller,
    required this.bosses,
    required this.devices,
  });

  @override
  State<BossListPage> createState() => _BossListPageState();
}

class _BossListPageState extends State<BossListPage> {
  bool _deviceInitDone = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca la UI por tiempo para que LEDs y textos cambien sin navegar.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_ensureDeviceOnce().catchError((_, __) {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _ensureDeviceOnce() async {
    if (_deviceInitDone) return;
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final platform = kIsWeb ? "web" : "android";
    try {
      await widget.devices.ensureDeviceRegistered(
        uid: uid,
        leadTimeMinutes: widget.controller.leadTimeMinutes,
        notificationsEnabled: widget.controller.notificationsEnabled,
        platform: platform,
      );
      _deviceInitDone = true;
    } catch (_) {
      /* evita Future sin listener en algunos errores JS (FCM) */
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat("HH:mm");
    const expireGrace = Duration(minutes: 15);
    final w = MediaQuery.sizeOf(context).width;
    // En web ancho, mantiene foco central; en Android usa casi todo el ancho.
    final isWideWeb = kIsWeb && w >= 1100;
    final gutter = isWideWeb ? w * 0.25 : 0.0;

    return StreamBuilder<List<Boss>>(
      stream: widget.bosses.bossesStream(),
      builder: (context, bossesSnap) {
        final bosses = bossesSnap.data ?? const <Boss>[];
        return StreamBuilder<List<BossDeath>>(
          stream: widget.bosses.latestDeaths(limit: 200),
          builder: (context, deathsSnap) {
            final deaths = deathsSnap.data ?? const <BossDeath>[];
            final latestByBoss = <String, BossDeath>{};
            for (final d in deaths) {
              latestByBoss.putIfAbsent(d.bossId, () => d);
            }
            final nowForSort = DateTime.now();
            final sortedBosses = [...bosses]..sort((a, b) {
              return _compareBossesByStatus(
                a,
                b,
                latestByBoss: latestByBoss,
                now: nowForSort,
                expireGrace: expireGrace,
              );
            });

            // En Android/móvil nativo: celdas más bajas y tipografía un poco mayor
            // (en web se mantiene el layout previo).
            final isPhoneNative = !kIsWeb;
            final theme = Theme.of(context);

            return LayoutBuilder(
              builder: (context, constraints) {
                final usableWidth = constraints.maxWidth - (gutter * 2) - 24;
                final minTileWidth = isPhoneNative
                    ? 158.0
                    : (w < 600 ? 210.0 : 260.0);
                final crossAxisCount =
                    (usableWidth / minTileWidth).floor().clamp(1, 6);
                final childAspectRatio = isPhoneNative
                    ? 2.75
                    : (w < 600 ? 1.75 : 2.15);
                final titleStyle = isPhoneNative
                    ? theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      )
                    : theme.textTheme.titleSmall;
                final subtitleStyle = isPhoneNative
                    ? theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.15,
                      )
                    : theme.textTheme.bodySmall;
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    gutter + (isPhoneNative ? 8 : 12),
                    isPhoneNative ? 8 : 12,
                    gutter + (isPhoneNative ? 8 : 12),
                    isPhoneNative ? 8 : 12,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: isPhoneNative ? 6 : 8,
                    mainAxisSpacing: isPhoneNative ? 6 : 8,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: sortedBosses.length,
                  itemBuilder: (context, i) {
                    final b = sortedBosses[i];
                    final latest = latestByBoss[b.id];
                    final now = DateTime.now();

                    String subtitle;
                    if (latest == null) {
                      subtitle = "Respawn ${b.respawnMinutes}m · Sin registro";
                    } else {
                      final next = latest.nextRespawnAt;
                      final remaining = next.difference(now);
                      final expired = next.isBefore(now.subtract(expireGrace));
                      final remText = expired
                          ? "Expirado"
                          : remaining.isNegative
                              ? "Listo"
                              : "${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m";
                      subtitle = "Resp ${df.format(next)} · $remText";
                    }

                    final pulse = _pulseForBoss(latest, expireGrace, now);

                    return Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.go("/boss/${b.id}"),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isPhoneNative ? 6 : 8,
                            vertical: isPhoneNative ? 4 : 8,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Tooltip(
                                    message: switch (pulse) {
                                      _Pulse.red =>
                                        "Cuenta atrás hasta respawn; luego pasará a verde (ventana activa)",
                                      _Pulse.green =>
                                        "Ventana activa: registra la muerte cuando lo mates (vuelve rojo)",
                                      _Pulse.gray =>
                                        latest == null
                                            ? "Sin muerte registrada todavía"
                                            : "Ventana vencida: registra nueva muerte para volver a sincronizar",
                                    },
                                    child: _BossLedDot(pulse: pulse),
                                  ),
                                  SizedBox(width: isPhoneNative ? 6 : 8),
                                  Expanded(
                                    child: Text(
                                      b.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: titleStyle,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: isPhoneNative ? 16 : 18,
                                  ),
                                ],
                              ),
                              SizedBox(height: isPhoneNative ? 1 : 4),
                              Text(
                                "$subtitle · ${bossInstanceLabel(b)}",
                                maxLines: isPhoneNative ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: subtitleStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

