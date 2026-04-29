# OSR Boss Tracker release checklist

## 1. Android package and signing

- Package final configurado en el proyecto: `com.ruddy.osrbosstracker`
- Namespace final configurado en Android: `com.ruddy.osrbosstracker`
- Firma release preparada mediante:
  - `apps/client/android/key.properties`
  - `apps/client/android/key.properties.example`

Comandos útiles:

```bash
cd apps/client
flutter build apk --release
```

Para crear el keystore:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

## 2. Firebase Android

En Firebase Console:

1. Añadir una app Android con package `com.ruddy.osrbosstracker`.
2. Añadir SHA-1 y SHA-256 del keystore release.
3. Descargar el nuevo `google-services.json`.
4. Reemplazar `apps/client/android/app/google-services.json`.

Nota:
- El archivo actual del repo está alineado al package final para que Gradle encuentre un cliente coincidente.
- Para que Google Sign-In funcione en release, sigue siendo obligatorio registrar la app Android real y sus huellas en Firebase.

## 3. Firebase Auth para web

En Firebase Authentication > Settings > Authorized domains:

- Añadir el dominio de Netlify, por ejemplo:
  - `osr-boss-tracker.netlify.app`
  - o el dominio personalizado que uses

## 4. Netlify

Archivos preparados:

- `netlify.toml`
- `apps/client/web/_redirects`

Opciones de despliegue:

### Manual

```bash
cd apps/client
flutter build web
```

Subir la carpeta `apps/client/build/web` a Netlify.

### Desde repositorio

- Conectar el repo en Netlify.
- Usar la configuración de `netlify.toml`.
- Verificar que el build descargue Flutter correctamente.

## 5. Verificaciones finales

### Android debug / release

- La app instala correctamente.
- Google login abre y vuelve con sesión válida.
- Firestore muestra y actualiza bosses.

### Web Netlify

- Carga `index.html`.
- Muestra nombre e iconos correctos.
- Google login funciona en el dominio publicado.
- Los cambios de bosses se reflejan compartiendo el mismo proyecto Firebase.

## 6. Posibles fallos

- `No matching client found for package name`: el `google-services.json` no coincide con `com.ruddy.osrbosstracker`.
- `PlatformException(sign_in_failed, ApiException: 10)`: faltan SHA-1/SHA-256 o la app Android no está bien registrada en Firebase.
- Login web falla en producción: falta el dominio de Netlify en `Authorized domains`.
