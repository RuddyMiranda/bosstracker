import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "../app_controller.dart";
import "../services.dart";

class SettingsPage extends StatefulWidget {
  final AuthService auth;
  final AppController controller;
  final DeviceService devices;

  const SettingsPage({
    super.key,
    required this.auth,
    required this.controller,
    required this.devices,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _saving = false;
  String? _error;

  Future<void> _syncDevice() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final platform = kIsWeb ? "web" : "android";
      await widget.devices.ensureDeviceRegistered(
        uid: uid,
        leadTimeMinutes: widget.controller.leadTimeMinutes,
        notificationsEnabled: widget.controller.notificationsEnabled,
        platform: platform,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes guardados.")));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.controller.leadTimeMinutes;
    final enabled = widget.controller.notificationsEnabled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Notificaciones", style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text("Habilitar notificaciones push"),
          value: enabled,
          onChanged: _saving
              ? null
              : (v) async {
                  await widget.controller.setNotificationsEnabled(v);
                  await _syncDevice();
                },
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text("Avisar con anticipación"),
          subtitle: Text("$lead minutos antes del respawn"),
          trailing: DropdownButton<int>(
            value: lead,
            onChanged: _saving
                ? null
                : (v) async {
                    if (v == null) return;
                    await widget.controller.setLeadTimeMinutes(v);
                    await _syncDevice();
                  },
            items: const [5, 10, 15, 30, 60].map((m) => DropdownMenuItem(value: m, child: Text("$m min"))).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saving ? null : _syncDevice,
          child: Text(_saving ? "..." : "Sincronizar dispositivo"),
        ),
      ],
    );
  }
}

