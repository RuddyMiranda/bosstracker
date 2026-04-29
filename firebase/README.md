# Firebase (backend)

Aquí vive la configuración de Firestore + Cloud Functions.

## Archivos
- `firebase.json`: emuladores y configuración
- `firestore.rules`: reglas por guild/rol
- `firestore.indexes.json`: índices recomendados
- `functions/`: Functions en TypeScript

## Primeros pasos
1. Copia `.firebaserc.example` a `.firebaserc` y reemplaza el `projectId`.
2. Instala dependencias:
   - `cd firebase/functions && npm i`
3. Emuladores:
   - `cd firebase && firebase emulators:start`

