import "notification_permission_stub.dart"
    if (dart.library.html) "notification_permission_web.dart";

bool webNotificationsClearlyDenied() => isWebNotificationsDenied();
