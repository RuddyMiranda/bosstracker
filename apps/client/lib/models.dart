import "package:cloud_firestore/cloud_firestore.dart";

typedef DocMap = Map<String, dynamic>;

class Guild {
  final String id;
  final String name;

  Guild({required this.id, required this.name});

  static Guild fromDoc(DocumentSnapshot<DocMap> doc) {
    final d = doc.data() ?? {};
    return Guild(id: doc.id, name: (d["name"] as String?) ?? doc.id);
  }
}

class Boss {
  final String id;
  final String name;
  final String? zone;
  /// Canal de juego OSR: 0, 1 ó 2.
  final int canal;
  final int respawnMinutes;
  final bool active;

  Boss({
    required this.id,
    required this.name,
    required this.respawnMinutes,
    required this.active,
    this.zone,
    this.canal = 0,
  });

  static Boss fromDoc(DocumentSnapshot<DocMap> doc) {
    final d = doc.data() ?? {};
    final canalRaw = (d["canal"] as num?)?.toInt();
    return Boss(
      id: doc.id,
      name: (d["name"] as String?) ?? doc.id,
      zone: d["zone"] as String?,
      canal: (canalRaw != null && canalRaw >= 0 && canalRaw <= 2)
          ? canalRaw
          : 0,
      respawnMinutes: (d["respawnMinutes"] as num?)?.toInt() ?? 0,
      active: (d["active"] as bool?) ?? true,
    );
  }
}

String bossInstanceLabel(Boss boss) {
  final lower = boss.name.trim().toLowerCase();
  final usesAniBcu = lower == "quetzal" || lower == "grypho";
  if (usesAniBcu) {
    return boss.canal == 1 ? "BCU" : "ANI";
  }
  return "Canal ${boss.canal}";
}

class BossDeath {
  final String id;
  final String bossId;
  final DateTime killedAt;
  final DateTime nextRespawnAt;
  final String registeredBy;
  final String? notes;

  BossDeath({
    required this.id,
    required this.bossId,
    required this.killedAt,
    required this.nextRespawnAt,
    required this.registeredBy,
    this.notes,
  });

  static BossDeath fromDoc(DocumentSnapshot<DocMap> doc) {
    final d = doc.data() ?? {};
    DateTime dt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return BossDeath(
      id: doc.id,
      bossId: (d["bossId"] as String?) ?? "",
      killedAt: dt(d["killedAt"]),
      nextRespawnAt: dt(d["nextRespawnAt"]),
      registeredBy: (d["registeredBy"] as String?) ?? "",
      notes: d["notes"] as String?,
    );
  }
}

