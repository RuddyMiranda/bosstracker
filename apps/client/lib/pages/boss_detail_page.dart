import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:intl/intl.dart";

import "../app_controller.dart";
import "../models.dart";
import "../services.dart";

class BossDetailPage extends StatefulWidget {
  final String bossId;
  final AuthService auth;
  final AppController controller;
  final BossService bosses;

  const BossDetailPage({
    super.key,
    required this.bossId,
    required this.auth,
    required this.controller,
    required this.bosses,
  });

  @override
  State<BossDetailPage> createState() => _BossDetailPageState();
}

class _BossDetailPageState extends State<BossDetailPage> {
  final _notes = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _register({required DateTime killedAt}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.bosses.registerBossDeath(
        bossId: widget.bossId,
        killedAt: killedAt,
        uid: uid,
        notes: _notes.text,
      );
      if (mounted) {
        _notes.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Registrado.")));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndRegister() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 1)),
      initialDate: now,
    );
    if (date == null) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null) return;
    final killedAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _register(killedAt: killedAt);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat("yyyy-MM-dd HH:mm");

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<DocMap>>(
        stream: FirebaseFirestore.instance
            .collection("bosses")
            .doc(widget.bossId)
            .snapshots(),
        builder: (context, bossSnap) {
          final bossDoc = bossSnap.data;
          if (bossDoc == null || !bossDoc.exists) {
            return const Center(child: Text("Cargando boss..."));
          }
          final boss = Boss.fromDoc(bossDoc);

          return StreamBuilder<BossDeath?>(
            stream: widget.bosses.latestDeathForBoss(widget.bossId),
            builder: (context, deathSnap) {
              final latest = deathSnap.data;
              final now = DateTime.now();
              final next = latest?.nextRespawnAt;
              final remaining = next?.difference(now);
              const expireGrace = Duration(minutes: 15);
              final expired = next != null && next.isBefore(now.subtract(expireGrace));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go("/"),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(boss.name,
                            style: Theme.of(context).textTheme.headlineSmall),
                      ),
                    ],
                  ),
                  if (boss.zone != null) Text("Zona: ${boss.zone}"),
                  Text("Respawn: ${boss.respawnMinutes} min"),
                  Text("Instancia: ${bossInstanceLabel(boss)}"),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Último registro",
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (latest == null)
                            const Text("Aún no hay registros en esta guild."),
                          if (latest != null) ...[
                            Text("Muerte: ${df.format(latest.killedAt)}"),
                            Text("Respawn: ${df.format(latest.nextRespawnAt)}"),
                            if (remaining != null)
                              Text(
                                expired
                                    ? "Estado: expirado (sin registro nuevo en +15 min)"
                                    : remaining.isNegative
                                        ? "Estado: listo"
                                        : "Falta: ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m",
                              ),
                            if (latest.notes != null)
                              Text("Notas: ${latest.notes}"),
                          ]
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Registrar muerte",
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notes,
                            decoration: const InputDecoration(
                              labelText: "Notas (opcional)",
                              hintText: "ej. ANI / BCU / canal 1 / lo mató X",
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_error != null) ...[
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 8),
                          ],
                          FilledButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _register(killedAt: DateTime.now()),
                            icon: const Icon(Icons.timer),
                            label: Text(_loading ? "..." : "Registrar ahora"),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _pickAndRegister,
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text("Elegir fecha/hora"),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
