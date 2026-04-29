import "dart:html";

bool isWebNotificationsDenied() {
  try {
    if (!Notification.supported) return false;
    // Dart expone los mismos valores que el DOM: denied | granted | default.
    return Notification.permission == "denied";
  } catch (_) {
    return false;
  }
}
