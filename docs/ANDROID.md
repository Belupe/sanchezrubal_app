# Android — distribución (Google Play)

> ⚠️ **La distribución por APK self-hosted quedó RETIRADA.** Android ahora se distribuye por
> **Google Play (por invitación)** → ver **[GOOGLE.md](GOOGLE.md)**. Se eliminaron `build-android.ps1`
> y `server/updates/android/`. Este documento se conserva por la **configuración del keystore**, que
> Google Play reutiliza como *clave de subida*.

- **applicationId:** `net.sanchezrubal.portal_familia` · **compileSdk 36** (AGP 9).
- La app usa el mismo backend que las demás (Supabase + MinIO): toda la funcionalidad va incluida.

## Keystore de firma (lo reutiliza Google Play como clave de subida)
- Ya está creado en `C:\Users\ignac\keystores\portal-familia-release.jks`, referenciado desde
  `app_flutter/android/key.properties` (gitignored).
- **🔐 Haz copia de seguridad del `.jks` y del `key.properties`**: si los pierdes no podrás publicar
  actualizaciones. Para crear uno nuevo:
  ```bash
  keytool -genkeypair -v -keystore portal-familia-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias portal-familia
  ```

## Compilar y publicar
Android se sube a **Google Play** con el App Bundle (`.aab`):
```powershell
./scripts/build-aab.ps1        # genera dist/googleplay/*.aab
```
Los pasos completos (Play Console, pista de prueba interna, enlace de invitación en
`DOWNLOAD_ANDROID_PLAY_URL`) están en **[GOOGLE.md](GOOGLE.md)**.
