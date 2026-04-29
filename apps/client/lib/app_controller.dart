import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

class AppController extends ChangeNotifier {
  static const _leadTimeKey = "leadTimeMinutes";
  static const _notifEnabledKey = "notificationsEnabled";

  int _leadTimeMinutes = 30;
  bool _notificationsEnabled = true;

  int get leadTimeMinutes => _leadTimeMinutes;
  bool get notificationsEnabled => _notificationsEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _leadTimeMinutes = prefs.getInt(_leadTimeKey) ?? 30;
    _notificationsEnabled = prefs.getBool(_notifEnabledKey) ?? true;
    notifyListeners();
  }

  Future<void> setLeadTimeMinutes(int minutes) async {
    _leadTimeMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_leadTimeKey, minutes);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifEnabledKey, enabled);
    notifyListeners();
  }
}

