import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import crypto from "node:crypto";

admin.initializeApp();
const db = admin.firestore();

function requireAuth(request: { auth?: { uid: string } }) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  return request.auth.uid;
}

async function requireGuildMember(guildId: string, uid: string) {
  const memberId = `${guildId}_${uid}`;
  const memberSnap = await db.collection("guildMembers").doc(memberId).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "No perteneces a esta guild.");
  }
  const role = (memberSnap.data()?.role ?? "member") as string;
  return role;
}

async function requireGuildAdmin(guildId: string, uid: string) {
  const role = await requireGuildMember(guildId, uid);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Se requiere rol admin.");
  }
}

function normalizeCode(input: unknown) {
  const s = String(input ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9-]/g, "");
  if (s.length < 6 || s.length > 24) return null;
  return s;
}

function generateCode() {
  // 12 chars, agrupado como XXXX-XXXX-XXXX
  const raw = crypto.randomBytes(9).toString("base64url").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const s = raw.slice(0, 12);
  return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
}

export const createInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data as {
    guildId?: string;
    role?: "admin" | "mod" | "member";
    ttlMinutes?: number;
  };

  const guildId = String(data.guildId ?? "").trim();
  if (!guildId) throw new HttpsError("invalid-argument", "guildId es requerido.");

  await requireGuildAdmin(guildId, uid);

  const role = (data.role ?? "member") as "admin" | "mod" | "member";
  if (!["admin", "mod", "member"].includes(role)) {
    throw new HttpsError("invalid-argument", "role inválido.");
  }

  const ttl = Number(data.ttlMinutes ?? 60);
  const ttlClamped = Math.max(5, Math.min(60 * 24 * 7, Math.round(ttl))); // 5m .. 7d
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(now.toMillis() + ttlClamped * 60_000);

  // Intentar algunos códigos por colisión (muy raro).
  for (let i = 0; i < 5; i++) {
    const code = generateCode();
    const ref = db.collection("invites").doc(code);
    try {
      await ref.create({
        guildId,
        role,
        createdBy: uid,
        createdAt: now,
        expiresAt,
        usedBy: null,
        usedAt: null
      });
      return { code, guildId, role, expiresAtMs: expiresAt.toMillis() };
    } catch (e: any) {
      // Already exists -> retry. Other errors -> throw.
      if (String(e?.code ?? "").includes("already-exists")) continue;
      throw new HttpsError("internal", "No se pudo crear invite.");
    }
  }

  throw new HttpsError("internal", "No se pudo generar un código único.");
});

export const joinGuildWithInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data as { code?: string };
  const code = normalizeCode(data.code);
  if (!code) throw new HttpsError("invalid-argument", "Código inválido.");

  const inviteRef = db.collection("invites").doc(code);
  const now = Timestamp.now();

  let guildId = "";
  let role: string = "member";

  await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    if (!inviteSnap.exists) throw new HttpsError("not-found", "Código no existe.");
    const inv = inviteSnap.data() as any;

    guildId = String(inv.guildId ?? "");
    role = String(inv.role ?? "member");
    const expiresAt = inv.expiresAt as Timestamp | undefined;
    const usedAt = inv.usedAt as Timestamp | null | undefined;

    if (!guildId) throw new HttpsError("failed-precondition", "Invite corrupto.");
    if (usedAt) throw new HttpsError("failed-precondition", "Este código ya fue usado.");
    if (!expiresAt || expiresAt.toMillis() <= now.toMillis()) {
      throw new HttpsError("failed-precondition", "Este código expiró.");
    }

    const guildRef = db.collection("guilds").doc(guildId);
    const guildSnap = await tx.get(guildRef);
    if (!guildSnap.exists) throw new HttpsError("not-found", "La guild ya no existe.");

    const memberRef = db.collection("guildMembers").doc(`${guildId}_${uid}`);
    tx.set(
      memberRef,
      {
        guildId,
        uid,
        role,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );

    tx.update(inviteRef, {
      usedAt: now,
      usedBy: uid
    });
  });

  return { guildId, role };
});

export const registerBossDeath = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data as {
    guildId?: string;
    bossId?: string;
    killedAtMs?: number; // epoch ms
    notes?: string;
  };

  if (!data.guildId || !data.bossId || !data.killedAtMs) {
    throw new HttpsError("invalid-argument", "Faltan campos requeridos.");
  }
  const guildId = data.guildId;
  const bossId = data.bossId;
  const killedAt = Timestamp.fromMillis(data.killedAtMs);

  await requireGuildMember(guildId, uid);

  const bossSnap = await db.collection("bosses").doc(bossId).get();
  if (!bossSnap.exists) {
    throw new HttpsError("not-found", "Boss no existe.");
  }
  const boss = bossSnap.data() as { respawnMinutes?: number; active?: boolean; name?: string };
  if (!boss.active) {
    throw new HttpsError("failed-precondition", "Boss inactivo.");
  }
  const respawnMinutes = Number(boss.respawnMinutes ?? 0);
  if (!Number.isFinite(respawnMinutes) || respawnMinutes <= 0) {
    throw new HttpsError("failed-precondition", "Boss sin respawnMinutes válido.");
  }

  const nextRespawnAt = Timestamp.fromMillis(killedAt.toMillis() + respawnMinutes * 60_000);
  const now = Timestamp.now();

  const deathRef = db.collection("bossDeaths").doc();
  await deathRef.set({
    guildId,
    bossId,
    killedAt,
    registeredBy: uid,
    notes: data.notes ?? null,
    nextRespawnAt,
    createdAt: now,
    updatedAt: now
  });

  return {
    deathId: deathRef.id,
    nextRespawnAtMs: nextRespawnAt.toMillis(),
    bossName: boss.name ?? null
  };
});

export const sendDueNotifications = onSchedule("every 1 minutes", async () => {
  const nowMs = Date.now();
  const windowMs = 60_000;

  // Lead time varía por dispositivo (5/10/15/30/60). Para evitar escanear demasiado,
  // acotamos la búsqueda hacia adelante.
  const maxLeadMinutes = 120;
  const searchUpper = Timestamp.fromMillis(nowMs + maxLeadMinutes * 60_000);
  // Permite una pequeña tolerancia hacia atrás por desfases normales del scheduler.
  const searchLower = Timestamp.fromMillis(nowMs - windowMs);

  const dueDeathsSnap = await db
    .collection("bossDeaths")
    .where("nextRespawnAt", ">=", searchLower)
    .where("nextRespawnAt", "<=", searchUpper)
    .get();

  if (dueDeathsSnap.empty) {
    return;
  }

  logger.info(`Upcoming respawns (<=${maxLeadMinutes}m): ${dueDeathsSnap.size}`);

  const enabledDevicesSnap = await db
    .collection("devices")
    .where("notificationsEnabled", "==", true)
    .get();

  if (enabledDevicesSnap.empty) {
    logger.info("No hay dispositivos habilitados para notificaciones.");
    return;
  }

  const deaths = dueDeathsSnap.docs.map((doc) => {
    const d = doc.data() as { bossId: string; nextRespawnAt: Timestamp };
    return { bossId: d.bossId, nextRespawnAt: d.nextRespawnAt };
  });

  const bossIds = Array.from(new Set(deaths.map((d) => d.bossId)));
  const bossesSnap = await db.getAll(...bossIds.map((id) => db.collection("bosses").doc(id)));
  const nameById = new Map<string, string>();
  bossesSnap.forEach((s) => {
    if (s.exists) nameById.set(s.id, String((s.data() as any).name ?? s.id));
  });

  let totalSuccess = 0;
  let totalFailure = 0;

  for (const device of enabledDevicesSnap.docs) {
    const lead = Number((device.data() as any).leadTimeMinutes ?? 0);
    const token = String((device.data() as any).fcmToken ?? "");
    if (!token) continue;
    if (!Number.isFinite(lead)) continue;
    const leadClamped = Math.max(0, Math.min(maxLeadMinutes, Math.round(lead)));

    const notifyBossIds = deaths
      .filter((death) => {
        const targetMs = death.nextRespawnAt.toMillis() - leadClamped * 60_000;
        return targetMs > nowMs - windowMs && targetMs <= nowMs;
      })
      .map((death) => death.bossId);

    if (notifyBossIds.length === 0) continue;

    const uniqueBossIds = Array.from(new Set(notifyBossIds));
    const title =
      uniqueBossIds.length === 1
        ? "Boss por respawnear"
        : `Bosses por respawnear (${uniqueBossIds.length})`;
    const body =
      uniqueBossIds.length === 1
        ? `${nameById.get(uniqueBossIds[0]) ?? uniqueBossIds[0]} está por respawnear.`
        : uniqueBossIds.map((id) => `• ${nameById.get(id) ?? id}`).join("\n");

    try {
      await admin.messaging().send({
        token,
        notification: { title, body },
        data: {
          type: "boss_respawn_soon",
          bossIds: JSON.stringify(uniqueBossIds)
        }
      });
      totalSuccess += 1;
    } catch (error) {
      totalFailure += 1;
      logger.error(`Error enviando notificación a device ${device.id}`, error);
    }
  }

  logger.info(`Notificaciones enviadas: ok=${totalSuccess} fail=${totalFailure}`);
});

