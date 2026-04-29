import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

import "compat/notification_permission.dart";
import "models.dart";

class AuthService {
  final FirebaseAuth _auth;
  AuthService(this._auth);

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signInGoogle() async {
    if (kIsWeb) {
      // Popup: misma página, sin redirect OAuth (en localhost redirect suele dejar sesión inconsistente).
      final cred =
          await _auth.signInWithPopup(GoogleAuthProvider());
      if (cred.user == null) {
        throw StateError("Inicio de sesión incompleto tras el popup.");
      }
      return;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return; // cancelado
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signInEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> registerEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> signOut() async {
    if (kIsWeb) await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}

class GuildService {
  final FirebaseFirestore _db;
  GuildService(this._db, FirebaseFunctions _functions);

  Stream<List<Guild>> myGuildsStream(String uid) {
    // MVP: el usuario pertenece a una sola guild (guardada en prefs),
    // pero dejamos el stream por si luego se soporta multi-guild.
    return _db
        .collection("guildMembers")
        .where("uid", isEqualTo: uid)
        .snapshots()
        .asyncMap((snap) async {
      final guildIds = snap.docs
          .map((d) => (d.data()["guildId"] as String?) ?? "")
          .where((x) => x.isNotEmpty)
          .toList();
      if (guildIds.isEmpty) return <Guild>[];
      final guildDocs = await Future.wait(
          guildIds.map((id) => _db.collection("guilds").doc(id).get()));
      return guildDocs
          .where((g) => g.exists)
          .map((g) => Guild.fromDoc(g))
          .toList();
    });
  }

  Future<String> createGuildAndJoin({
    required String uid,
    required String name,
  }) async {
    throw UnimplementedError("Guilds deshabilitadas (app de una sola comunidad).");
  }

  Future<void> joinGuild({
    required String uid,
    required String guildId,
  }) async {
    throw UnimplementedError("Guilds deshabilitadas (app de una sola comunidad).");
  }

  Future<String> joinWithInviteCode({
    required String code,
  }) async {
    throw UnimplementedError("Invites deshabilitadas (app de una sola comunidad).");
  }
}

class BossService {
  final FirebaseFirestore _db;
  BossService(this._db);

  Stream<List<Boss>> bossesStream() {
    return _db
        .collection("bosses")
        .where("active", isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Boss.fromDoc(d as DocumentSnapshot<DocMap>))
              .toList()
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        );
  }

  Stream<List<BossDeath>> latestDeaths({int limit = 50}) {
    return _db
        .collection("bossDeaths")
        .orderBy("killedAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BossDeath.fromDoc(d as DocumentSnapshot<DocMap>))
            .toList());
  }

  Stream<BossDeath?> latestDeathForBoss(String bossId) {
    return _db
        .collection("bossDeaths")
        .where("bossId", isEqualTo: bossId)
        .orderBy("killedAt", descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : BossDeath.fromDoc(snap.docs.first as DocumentSnapshot<DocMap>));
  }

  Future<void> registerBossDeath({
    required String bossId,
    required DateTime killedAt,
    required String uid,
    String? notes,
  }) async {
    // MVP (cliente): calcula nextRespawnAt también en cliente.
    // Producción: usar Cloud Function registerBossDeath (callable) para validar y centralizar lógica.
    final bossSnap = await _db.collection("bosses").doc(bossId).get();
    if (!bossSnap.exists) throw StateError("Boss no existe.");
    final respawnMinutes =
        (bossSnap.data()?["respawnMinutes"] as num?)?.toInt() ?? 0;
    if (respawnMinutes <= 0) throw StateError("Boss sin respawnMinutes.");

    final nextRespawnAt = killedAt.add(Duration(minutes: respawnMinutes));

    await _db.collection("bossDeaths").add({
      "bossId": bossId,
      "killedAt": Timestamp.fromDate(killedAt),
      "registeredBy": uid,
      "notes": (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      "nextRespawnAt": Timestamp.fromDate(nextRespawnAt),
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp()
    });
  }
}

class DeviceService {
  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging;
  DeviceService(this._db, this._messaging);

  static const _prefsKey = "deviceId";

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_prefsKey, id);
    return id;
  }

  Future<void> ensureDeviceRegistered({
    required String uid,
    required int leadTimeMinutes,
    required bool notificationsEnabled,
    required String platform,
  }) async {
    final deviceId = await _getOrCreateDeviceId();
    final docRef = _db.collection("devices").doc("${uid}_$deviceId");

    Future<void> saveWithoutFcmToken() async {
      await docRef.set({
        "uid": uid,
        "deviceId": deviceId,
        "platform": platform,
        "notificationsEnabled": false,
        "leadTimeMinutes": leadTimeMinutes,
        "updatedAt": FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    }

    if (kIsWeb && webNotificationsClearlyDenied()) {
      await saveWithoutFcmToken();
      return;
    }

    try {
      final perm = await _messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        await saveWithoutFcmToken();
        return;
      }

      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        await saveWithoutFcmToken();
        return;
      }

      await docRef.set({
        "uid": uid,
        "deviceId": deviceId,
        "fcmToken": token,
        "platform": platform,
        "notificationsEnabled": notificationsEnabled,
        "leadTimeMinutes": leadTimeMinutes,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    } catch (_) {
      // Ej. firebase_messaging/permission-blocked en web si el usuario denegó antes.
      await saveWithoutFcmToken();
    }
  }
}
