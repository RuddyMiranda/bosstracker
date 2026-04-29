import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../app_controller.dart";
import "../models.dart";
import "../services.dart";

class WebAdminPage extends StatefulWidget {
  final AuthService auth;
  final AppController controller;

  const WebAdminPage({
    super.key,
    required this.auth,
    required this.controller,
  });

  @override
  State<WebAdminPage> createState() => _WebAdminPageState();
}

class _WebAdminPageState extends State<WebAdminPage> {
  final _name = TextEditingController();
  final _zone = TextEditingController();
  final _respawn = TextEditingController(text: "120");
  int _canalSeleccion = 0;
  bool _saving = false;
  String? _error;

  String _slug(String s) {
    final lower = s.trim().toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r"[áàä]"), "a")
        .replaceAll(RegExp(r"[éèë]"), "e")
        .replaceAll(RegExp(r"[íìï]"), "i")
        .replaceAll(RegExp(r"[óòö]"), "o")
        .replaceAll(RegExp(r"[úùü]"), "u")
        .replaceAll(RegExp(r"[^a-z0-9]+"), "_")
        .replaceAll(RegExp(r"_+"), "_")
        .replaceAll(RegExp(r"^_|_$"), "");
    return cleaned.isEmpty ? "boss" : cleaned;
  }

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    _respawn.dispose();
    super.dispose();
  }

  Future<void> _createBoss() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final zone = _zone.text.trim();
      final respawnMinutes = int.tryParse(_respawn.text.trim()) ?? 0;
      if (name.isEmpty || respawnMinutes <= 0) {
        throw StateError("Nombre y respawnMinutes son requeridos.");
      }
      await FirebaseFirestore.instance.collection("bosses").add({
        "name": name,
        "zone": zone.isEmpty ? null : zone,
        "canal": _canalSeleccion.clamp(0, 1),
        "respawnMinutes": respawnMinutes,
        "active": true,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
      _name.clear();
      _zone.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _seedBosses() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final presets = <Map<String, dynamic>>[
        {"name": "Skady", "respawnMinutes": 180, "canal": 0},
        {"name": "Bishop Blue", "docId": "bishop_blue", "respawnMinutes": 360, "canal": 0},
        {"name": "Bishop Red", "docId": "bishop_red", "respawnMinutes": 360, "canal": 0},
        {"name": "Bishop Black", "docId": "bishop_black", "respawnMinutes": 360, "canal": 0},
        {"name": "Quetzal", "docId": "quetzal_ani", "respawnMinutes": 120, "canal": 0},
        {"name": "Quetzal", "docId": "quetzal_bcu", "respawnMinutes": 120, "canal": 1},
        {"name": "Grypho", "docId": "grypho_ani", "respawnMinutes": 120, "canal": 0},
        {"name": "Grypho", "docId": "grypho_bcu", "respawnMinutes": 120, "canal": 1},
        {"name": "Rock emperador", "respawnMinutes": 180, "canal": 0},
        {"name": "Egma", "respawnMinutes": 1440, "canal": 0},
        {"name": "Pathos", "respawnMinutes": 120, "canal": 0},
        {"name": "Nipar", "respawnMinutes": 120, "canal": 0},
        {"name": "Base militar", "respawnMinutes": 120, "zone": "militar", "canal": 0},
        {"name": "Shire", "docId": "shire_canal_0", "respawnMinutes": 120, "canal": 0},
        {"name": "Shire", "docId": "shire_canal_1", "respawnMinutes": 120, "canal": 1},
        {"name": "Core", "docId": "core_canal_0", "respawnMinutes": 120, "canal": 0},
        {"name": "Core", "docId": "core_canal_1", "respawnMinutes": 120, "canal": 1},
        {"name": "Mensager", "docId": "mensager_canal_0", "respawnMinutes": 120, "canal": 0},
        {"name": "Mensager", "docId": "mensager_canal_1", "respawnMinutes": 120, "canal": 1},
      ];

      final batch = FirebaseFirestore.instance.batch();
      final now = FieldValue.serverTimestamp();
      for (final p in presets) {
        final name = p["name"] as String;
        final explicitId = p["docId"] as String?;
        final docId = explicitId != null && explicitId.trim().isNotEmpty
            ? explicitId.trim()
            : _slug(name);
        final ref = FirebaseFirestore.instance.collection("bosses").doc(docId);
        batch.set(
          ref,
          {
            "name": name,
            "zone": p["zone"],
            "canal": ((p["canal"] as num?)?.toInt() ?? 0).clamp(0, 1),
            "respawnMinutes": p["respawnMinutes"],
            "active": true,
            "createdAt": now,
            "updatedAt": now,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<int> _deleteAllDocsIn(CollectionReference<DocMap> col) async {
    var total = 0;
    while (true) {
      final qs = await col.limit(500).get();
      if (qs.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in qs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      total += qs.docs.length;
    }
    return total;
  }

  Future<void> _wipeBossDeathsAsk() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Borrar registros de muerte"),
        content: const Text(
          "Se eliminarán todos los documentos de la colección «bossDeaths». "
          "No se pueden deshacer. ¿Continuar?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Borrar todo"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final n = await _deleteAllDocsIn(FirebaseFirestore.instance.collection("bossDeaths"));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Eliminados $n registros de bossDeaths.")),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _wipeBossesAsk() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Borrar bosses"),
        content: const Text(
          "Se eliminarán todos los documentos de la colección «bosses». "
          "Los registros de muerte pueden quedar huérfanos: conviene antes vaciar bossDeaths. "
          "¿Continuar igualmente?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Borrar bosses"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final n = await _deleteAllDocsIn(FirebaseFirestore.instance.collection("bosses"));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Eliminados $n bosses.")),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text("Inicia sesión."));
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(text: "Bosses"),
                Tab(text: "Registros"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BossesTab(
                  saving: _saving,
                  error: _error,
                  name: _name,
                  zone: _zone,
                  respawn: _respawn,
                  canal: _canalSeleccion,
                  onCanalChanged: (v) => setState(() => _canalSeleccion = v),
                  onCreate: _createBoss,
                  onSeed: _seedBosses,
                  onWipeDeaths: _wipeBossDeathsAsk,
                  onWipeBosses: _wipeBossesAsk,
                ),
                _DeathsTab(
                  canEdit: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BossesTab extends StatelessWidget {
  final bool saving;
  final String? error;
  final TextEditingController name;
  final TextEditingController zone;
  final TextEditingController respawn;
  final int canal;
  final ValueChanged<int> onCanalChanged;
  final Future<void> Function() onCreate;
  final Future<void> Function() onSeed;
  final Future<void> Function() onWipeDeaths;
  final Future<void> Function() onWipeBosses;

  const _BossesTab({
    required this.saving,
    required this.error,
    required this.name,
    required this.zone,
    required this.respawn,
    required this.canal,
    required this.onCanalChanged,
    required this.onCreate,
    required this.onSeed,
    required this.onWipeDeaths,
    required this.onWipeBosses,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 420,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Admin (bosses)", style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        "Para crear/editar bosses necesitas ser admin de la guild.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot<DocMap>>(
                        stream: FirebaseFirestore.instance
                            .collection("bosses")
                            .limit(1)
                            .snapshots(),
                        builder: (context, snap) {
                          final hayBosses =
                              snap.hasData && (snap.data?.docs ?? []).isNotEmpty;
                          return FilledButton.tonalIcon(
                            onPressed: saving || hayBosses ? null : onSeed,
                            icon: const Icon(Icons.playlist_add),
                            label: const Text("Cargar bosses base"),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: name, decoration: const InputDecoration(labelText: "Nombre")),
                      const SizedBox(height: 8),
                      TextField(controller: zone, decoration: const InputDecoration(labelText: "Zona (opcional)")),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: "Canal"),
                        value: canal.clamp(0, 1),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text("0")),
                          DropdownMenuItem(value: 1, child: Text("1")),
                        ],
                        onChanged: saving
                            ? null
                            : (v) {
                                if (v != null) onCanalChanged(v);
                              },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: respawn,
                        decoration: const InputDecoration(labelText: "Respawn (min)"),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      if (error != null) ...[
                        Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        onPressed: saving ? null : onCreate,
                        child: Text(saving ? "..." : "Crear boss"),
                      ),
                      const SizedBox(height: 24),
                      ExpansionTile(
                        leading: Icon(Icons.delete_sweep_outlined, color: Theme.of(context).colorScheme.error),
                        title: Text(
                          "Reinicio de datos",
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        subtitle: const Text(
                          "Elimina colecciones en Firestore para empezar de cero. "
                          "Solo cuenta con admins en reglas.",
                        ),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              "Orden recomendado: primero registros de muerte, luego bosses. "
                              "Así podrás volver a usar «Cargar bosses base».",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: saving ? null : onWipeDeaths,
                            icon: const Icon(Icons.clear_all),
                            label: const Text("Vaciar bossDeaths (registros)"),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.error,
                              side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6)),
                            ),
                            onPressed: saving ? null : onWipeBosses,
                            icon: const Icon(Icons.warning_amber),
                            label: const Text("Vaciar bosses (definiciones)"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<DocMap>>(
              stream: FirebaseFirestore.instance
                  .collection("bosses")
                  .orderBy("name")
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final boss = Boss.fromDoc(docs[i] as DocumentSnapshot<DocMap>);
                    return ListTile(
                      title: Text(boss.name),
                      subtitle: Text([
                        boss.zone ?? "sin zona",
                        bossInstanceLabel(boss),
                        "${boss.respawnMinutes} min",
                        boss.active ? "activo" : "inactivo",
                      ].join(" · ")),
                      trailing: IconButton(
                        tooltip: boss.active ? "Desactivar" : "Activar",
                        onPressed: saving
                            ? null
                            : () async {
                                await docs[i].reference.update({
                                  "active": !boss.active,
                                  "updatedAt": FieldValue.serverTimestamp(),
                                });
                              },
                        icon: Icon(boss.active ? Icons.visibility : Icons.visibility_off),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class _DeathsTab extends StatelessWidget {
  final bool canEdit;

  const _DeathsTab({required this.canEdit});

  Future<void> _editDeath(BuildContext context, DocumentSnapshot<DocMap> doc) async {
    final d = doc.data() ?? {};
    final bossId = (d["bossId"] as String?) ?? "";
    final killedAt = (d["killedAt"] as Timestamp?)?.toDate();
    if (bossId.isEmpty || killedAt == null) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 14)),
      lastDate: now.add(const Duration(days: 1)),
      initialDate: killedAt,
    );
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(killedAt));
    if (time == null) return;
    final newKilledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    final bossSnap = await FirebaseFirestore.instance.collection("bosses").doc(bossId).get();
    final respawnMinutes = (bossSnap.data()?["respawnMinutes"] as num?)?.toInt() ?? 0;
    if (respawnMinutes <= 0) return;
    final newNext = newKilledAt.add(Duration(minutes: respawnMinutes));

    await doc.reference.update({
      "killedAt": Timestamp.fromDate(newKilledAt),
      "nextRespawnAt": Timestamp.fromDate(newNext),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat("yyyy-MM-dd HH:mm");
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<QuerySnapshot<DocMap>>(
        stream: FirebaseFirestore.instance
            .collection("bossDeaths")
            .orderBy("killedAt", descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) return const Center(child: Text("Sin registros."));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final bossId = (d["bossId"] as String?) ?? "";
              final killedAt = (d["killedAt"] as Timestamp?)?.toDate();
              final nextAt = (d["nextRespawnAt"] as Timestamp?)?.toDate();
              final by = (d["registeredBy"] as String?) ?? "";
              return ListTile(
                title: Text("bossId: $bossId"),
                subtitle: Text("muerte: ${killedAt == null ? "-" : df.format(killedAt)} · respawn: ${nextAt == null ? "-" : df.format(nextAt)} · por: $by"),
                trailing: canEdit
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: "Editar hora de muerte",
                            onPressed: () => _editDeath(context, docs[i] as DocumentSnapshot<DocMap>),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: "Borrar",
                            onPressed: () async => docs[i].reference.delete(),
                            icon: const Icon(Icons.delete),
                          ),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

