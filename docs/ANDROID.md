# Android — APK propio + auto-update

Android **no necesita servidor para ejecutarse** (corre en el móvil). Tu Docker solo **aloja el
`.apk`** y un `version.json` (servicio `updates`) para distribuir e ir actualizando sin Google Play.

- **applicationId:** `net.sanchezrubal.portal_familia` · **compileSdk 36** (AGP 9).
- La app usa el mismo backend que las demás (Supabase + MinIO): toda la funcionalidad y el
  almacenamiento local de media van incluidos sin tocar nada.

## Requisitos (en tu PC)
- **Android SDK** (Android Studio o cmdline-tools). `flutter doctor` con Android en verde
  (`flutter doctor --android-licenses` para aceptar licencias).
- **Keystore release** (firma). Ya está creado en
  `C:\Users\ignac\keystores\portal-familia-release.jks`, referenciado desde
  `app_flutter/android/key.properties` (gitignored).
  **🔐 Haz copia de seguridad del `.jks` y del `key.properties`**: si los pierdes no podrás
  publicar actualizaciones que se instalen sobre la app existente. Para crear uno nuevo:
  ```bash
  keytool -genkeypair -v -keystore portal-familia-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias portal-familia
  ```

## Compilar y publicar
```powershell
./scripts/release.ps1 -Bump        # Android + Windows; o solo Android:
./scripts/build-android.ps1
```
Genera `dist/android/portal-familia.apk` + `version.json` + `instalar-android.txt`. Si
`UPDATES_DATA_DIR` es accesible, `release.ps1` lo publica; si no, copia esos archivos a la carpeta
`UPDATES_DATA_DIR/android/` de tu servidor Docker.

## Cómo funciona el auto-update
- Tras el login, la app consulta `${UPDATES_PUBLIC_URL}/android/version.json`
  ([update_service.dart](../app_flutter/lib/services/update_service.dart)).
- Si el `versionCode` remoto (el `+N` de `pubspec.yaml`) es mayor que el instalado, ofrece
  descargar e instalar el `.apk` (pide el permiso "instalar apps desconocidas" la primera vez).
- **Importante:** sube siempre el `+N` en cada release (lo hace `release.ps1 -Bump`).

## Instalar (familia)
Abre `https://app.sanchezrubal.net`, pulsa **Android — Descargar e instalar**, permite
"orígenes desconocidos" una vez y confirma. Las siguientes versiones se avisan solas.
