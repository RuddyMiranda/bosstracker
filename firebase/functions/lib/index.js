"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendDueNotifications = exports.registerBossDeath = exports.joinGuildWithInvite = exports.createInvite = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firebase_admin_1 = __importDefault(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const node_crypto_1 = __importDefault(require("node:crypto"));
firebase_admin_1.default.initializeApp();
const db = firebase_admin_1.default.firestore();
function requireAuth(request) {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Debes iniciar sesión.");
    }
    return request.auth.uid;
}
async function requireGuildMember(guildId, uid) {
    const memberId = `${guildId}_${uid}`;
    const memberSnap = await db.collection("guildMembers").doc(memberId).get();
    if (!memberSnap.exists) {
        throw new https_1.HttpsError("permission-denied", "No perteneces a esta guild.");
    }
    const role = (memberSnap.data()?.role ?? "member");
    return role;
}
async function requireGuildAdmin(guildId, uid) {
    const role = await requireGuildMember(guildId, uid);
    if (role !== "admin") {
        throw new https_1.HttpsError("permission-denied", "Se requiere rol admin.");
    }
}
function normalizeCode(input) {
    const s = String(input ?? "")
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9-]/g, "");
    if (s.length < 6 || s.length > 24)
        return null;
    return s;
}
function generateCode() {
    // 12 chars, agrupado como XXXX-XXXX-XXXX
    const raw = node_crypto_1.default.randomBytes(9).toString("base64url").toUpperCase().replace(/[^A-Z0-9]/g, "");
    const s = raw.slice(0, 12);
    return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
}
exports.createInvite = (0, https_1.onCall)(async (request) => {
    const uid = requireAuth(request);
    const data = request.data;
    const guildId = String(data.guildId ?? "").trim();
    if (!guildId)
        throw new https_1.HttpsError("invalid-argument", "guildId es requerido.");
    await requireGuildAdmin(guildId, uid);
    const role = (data.role ?? "member");
    if (!["admin", "mod", "member"].includes(role)) {
        throw new https_1.HttpsError("invalid-argument", "role inválido.");
    }
    const ttl = Number(data.ttlMinutes ?? 60);
    const ttlClamped = Math.max(5, Math.min(60 * 24 * 7, Math.round(ttl))); // 5m .. 7d
    const now = firestore_1.Timestamp.now();
    const expiresAt = firestore_1.Timestamp.fromMillis(now.toMillis() + ttlClamped * 60_000);
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
        }
        catch (e) {
            // Already exists -> retry. Other errors -> throw.
            if (String(e?.code ?? "").includes("already-exists"))
                continue;
            throw new https_1.HttpsError("internal", "No se pudo crear invite.");
        }
    }
    throw new https_1.HttpsError("internal", "No se pudo generar un código único.");
});
exports.joinGuildWithInvite = (0, https_1.onCall)(async (request) => {
    const uid = requireAuth(request);
    const data = request.data;
    const code = normalizeCode(data.code);
    if (!code)
        throw new https_1.HttpsError("invalid-argument", "Código inválido.");
    const inviteRef = db.collection("invites").doc(code);
    const now = firestore_1.Timestamp.now();
    let guildId = "";
    let role = "member";
    await db.runTransaction(async (tx) => {
        const inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists)
            throw new https_1.HttpsError("not-found", "Código no existe.");
        const inv = inviteSnap.data();
        guildId = String(inv.guildId ?? "");
        role = String(inv.role ?? "member");
        const expiresAt = inv.expiresAt;
        const usedAt = inv.usedAt;
        if (!guildId)
            throw new https_1.HttpsError("failed-precondition", "Invite corrupto.");
        if (usedAt)
            throw new https_1.HttpsError("failed-precondition", "Este código ya fue usado.");
        if (!expiresAt || expiresAt.toMillis() <= now.toMillis()) {
            throw new https_1.HttpsError("failed-precondition", "Este código expiró.");
        }
        const guildRef = db.collection("guilds").doc(guildId);
        const guildSnap = await tx.get(guildRef);
        if (!guildSnap.exists)
            throw new https_1.HttpsError("not-found", "La guild ya no existe.");
        const memberRef = db.collection("guildMembers").doc(`${guildId}_${uid}`);
        tx.set(memberRef, {
            guildId,
            uid,
            role,
            createdAt: firebase_admin_1.default.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        tx.update(inviteRef, {
            usedAt: now,
            usedBy: uid
        });
    });
    return { guildId, role };
});
exports.registerBossDeath = (0, https_1.onCall)(async (request) => {
    const uid = requireAuth(request);
    const data = request.data;
    if (!data.guildId || !data.bossId || !data.killedAtMs) {
        throw new https_1.HttpsError("invalid-argument", "Faltan campos requeridos.");
    }
    const guildId = data.guildId;
    const bossId = data.bossId;
    const killedAt = firestore_1.Timestamp.fromMillis(data.killedAtMs);
    await requireGuildMember(guildId, uid);
    const bossSnap = await db.collection("bosses").doc(bossId).get();
    if (!bossSnap.exists) {
        throw new https_1.HttpsError("not-found", "Boss no existe.");
    }
    const boss = bossSnap.data();
    if (!boss.active) {
        throw new https_1.HttpsError("failed-precondition", "Boss inactivo.");
    }
    const respawnMinutes = Number(boss.respawnMinutes ?? 0);
    if (!Number.isFinite(respawnMinutes) || respawnMinutes <= 0) {
        throw new https_1.HttpsError("failed-precondition", "Boss sin respawnMinutes válido.");
    }
    const nextRespawnAt = firestore_1.Timestamp.fromMillis(killedAt.toMillis() + respawnMinutes * 60_000);
    const now = firestore_1.Timestamp.now();
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
exports.sendDueNotifications = (0, scheduler_1.onSchedule)("every 1 minutes", async () => {
    const nowMs = Date.now();
    const windowMs = 60_000;
    // Lead time varía por dispositivo (5/10/15/30/60). Para evitar escanear demasiado,
    // acotamos la búsqueda hacia adelante.
    const maxLeadMinutes = 120;
    const searchUpper = firestore_1.Timestamp.fromMillis(nowMs + maxLeadMinutes * 60_000);
    // Permite una pequeña tolerancia hacia atrás por desfases normales del scheduler.
    const searchLower = firestore_1.Timestamp.fromMillis(nowMs - windowMs);
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
        const d = doc.data();
        return { bossId: d.bossId, nextRespawnAt: d.nextRespawnAt };
    });
    const bossIds = Array.from(new Set(deaths.map((d) => d.bossId)));
    const bossesSnap = await db.getAll(...bossIds.map((id) => db.collection("bosses").doc(id)));
    const nameById = new Map();
    bossesSnap.forEach((s) => {
        if (s.exists)
            nameById.set(s.id, String(s.data().name ?? s.id));
    });
    let totalSuccess = 0;
    let totalFailure = 0;
    for (const device of enabledDevicesSnap.docs) {
        const lead = Number(device.data().leadTimeMinutes ?? 0);
        const token = String(device.data().fcmToken ?? "");
        if (!token)
            continue;
        if (!Number.isFinite(lead))
            continue;
        const leadClamped = Math.max(0, Math.min(maxLeadMinutes, Math.round(lead)));
        const notifyBossIds = deaths
            .filter((death) => {
            const targetMs = death.nextRespawnAt.toMillis() - leadClamped * 60_000;
            return targetMs > nowMs - windowMs && targetMs <= nowMs;
        })
            .map((death) => death.bossId);
        if (notifyBossIds.length === 0)
            continue;
        const uniqueBossIds = Array.from(new Set(notifyBossIds));
        const title = uniqueBossIds.length === 1
            ? "Boss por respawnear"
            : `Bosses por respawnear (${uniqueBossIds.length})`;
        const body = uniqueBossIds.length === 1
            ? `${nameById.get(uniqueBossIds[0]) ?? uniqueBossIds[0]} está por respawnear.`
            : uniqueBossIds.map((id) => `• ${nameById.get(id) ?? id}`).join("\n");
        try {
            await firebase_admin_1.default.messaging().send({
                token,
                notification: { title, body },
                data: {
                    type: "boss_respawn_soon",
                    bossIds: JSON.stringify(uniqueBossIds)
                },
                // Android: mismo channelId que [MainActivity] (sonido + prioridad).
                android: {
                    priority: "high",
                    notification: {
                        sound: "default",
                        channelId: "boss_respawn_soon"
                    }
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default"
                        }
                    }
                }
            });
            totalSuccess += 1;
        }
        catch (error) {
            totalFailure += 1;
            logger.error(`Error enviando notificación a device ${device.id}`, error);
        }
    }
    logger.info(`Notificaciones enviadas: ok=${totalSuccess} fail=${totalFailure}`);
});
