import { Timestamp } from "firebase-admin/firestore";

export type GuildRole = "admin" | "mod" | "member";

export interface BossDoc {
  guildId: string;
  name: string;
  zone?: string;
  respawnMinutes: number;
  active: boolean;
}

export interface BossDeathDoc {
  guildId: string;
  bossId: string;
  killedAt: Timestamp;
  registeredBy: string;
  notes?: string;
  nextRespawnAt: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface DeviceDoc {
  guildId: string;
  uid: string;
  deviceId: string;
  fcmToken: string;
  platform?: "android" | "ios" | "web";
  notificationsEnabled: boolean;
  leadTimeMinutes: number; // minutos antes para alertar
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface InviteDoc {
  guildId: string;
  role: GuildRole;
  createdBy: string;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  usedBy?: string | null;
  usedAt?: Timestamp | null;
}

