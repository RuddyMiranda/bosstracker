# OSR Boss Tracker client

Cliente Flutter para Android y Web.

## Branding actual

- Nombre visible: `OSR Boss Tracker`
- Logo fuente: `assets/branding/logo.png`
- Generación de iconos: `flutter_launcher_icons`

Para regenerar iconos si cambias el logo:

```bash
cd apps/client
flutter pub get
dart run flutter_launcher_icons
```

## APK release

El proyecto ya está preparado para usar firma release mediante `android/key.properties`.

1. Crea el keystore:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Copia `android/key.properties.example` a `android/key.properties` y ajusta valores.
3. Coloca el keystore en la ruta indicada por `storeFile`.
4. Genera huellas para Firebase:

```bash
cd apps/client/android
keytool -list -v -keystore ../upload-keystore.jks -alias upload
```

5. Construye el APK release:

```bash
cd apps/client
flutter build apk --release
```

## Firebase antes de publicar

### Android

- Registrar la app `com.ruddy.osrbosstracker` en Firebase.
- Añadir SHA-1 y SHA-256 del keystore release.
- Descargar y reemplazar `android/app/google-services.json`.

### Web

- Añadir el dominio de Netlify en Firebase Auth > Authorized domains.
- Verificar login Google y acceso a Firestore tras el deploy.

## Netlify

Se añadió `netlify.toml` en la raíz del repo y `web/_redirects` para fallback SPA.

Despliegue manual rápido:

```bash
cd apps/client
flutter build web
```

Luego publica `apps/client/build/web` en Netlify.

Despliegue desde repo:

- Conectar el repo a Netlify.
- Dejar que use `netlify.toml`.
- Verificar que el build descargue Flutter correctamente.

## Verificación final

- Android debug: login correcto.
- Android release: login correcto con SHA release cargado.
- Web publicada: login correcto en dominio Netlify.
- Branding correcto en navegador, PWA y launcher de Android.

