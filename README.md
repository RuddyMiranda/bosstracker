# OSR Boss Respawn Tracker

App Flutter (Android + Web) y backend serverless (Firebase) para registrar muertes de bosses por **guild**, calcular `nextRespawnAt` y enviar notificaciones push (FCM).

## Estructura
- `apps/client/`: Flutter (Android + Web)
- `firebase/`: Cloud Functions (TypeScript), reglas Firestore, índices, config Firebase

## Requisitos
- Flutter SDK (estable)
- Node.js 20+
- Firebase CLI (`npm i -g firebase-tools`)

## Configuración Firebase (dev)
1. Crea un proyecto Firebase (consola) y habilita:
   - Authentication (Google o Email/Password)
   - Firestore
   - Cloud Messaging (FCM)
   - Cloud Functions
2. En `osr-boss-tracker/firebase/`:
   - Copia `.firebaserc.example` a `.firebaserc` y pon tu `projectId`.
3. Flutter:
   - Entra a `apps/client/` y ejecuta `flutterfire configure` (requiere FlutterFire CLI).

## Desarrollo local (emuladores)
Desde `osr-boss-tracker/firebase/`:
- `npm i`
- `firebase emulators:start`

## Despliegue (resumen)
Desde `osr-boss-tracker/firebase/`:
- `firebase deploy`

