#!/bin/sh
# Bootstrap de Flutter para Xcode Cloud.
#
# La VM de Xcode Cloud clona el repo y ejecuta `xcodebuild` directamente: NO trae Flutter ni
# genera los ficheros que el proyecto necesita (ephemeral/Flutter-Generated.xcconfig, que define
# FLUTTER_ROOT, y el paquete SPM local FlutterGeneratedPluginSwiftPackage). Sin este paso previo,
# xcodebuild falla en segundos (exit 65). Este script lo prepara.
#
# Los plugins nativos se resuelven con Swift Package Manager (igual que iOS). En macOS es SPM puro
# (sin Podfile); iOS es híbrido (SPM + un Podfile mínimo), por eso `pod` debe estar disponible.
#
# Uso: flutter_ci_bootstrap.sh <ios|macos>
# Lo invoca app_flutter/<plataforma>/ci_scripts/ci_post_clone.sh
set -e

PLATFORM="$1"
case "$PLATFORM" in
  ios|macos) ;;
  *) echo "uso: $0 <ios|macos>" >&2; exit 1 ;;
esac

# Versión de Flutter fijada = la que se usa en local (flutter --version), para que CI == local.
FLUTTER_VERSION="3.44.6"

# 1. Instalar Flutter (la VM de Xcode Cloud no lo trae).
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
flutter --version

# 2. CocoaPods: normalmente ya viene en la imagen de Xcode Cloud. iOS lo necesita para la parte
#    híbrida de su Podfile; garantizarlo por si acaso.
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

# 3. Forzar Swift Package Manager de forma determinista (no depender del default de Flutter).
flutter config --enable-swift-package-manager

# 4. Resolver dependencias Dart y generar la config de build de Apple SIN compilar:
#    ephemeral/Flutter-Generated.xcconfig + el paquete SPM local (y pod install en iOS).
#    NO invoca xcodebuild (de eso se encarga Xcode Cloud después).
cd "$CI_PRIMARY_REPOSITORY_PATH/app_flutter"
if [ "$PLATFORM" = "macos" ]; then
  flutter config --enable-macos-desktop
fi
flutter precache --"$PLATFORM"
flutter pub get
flutter build "$PLATFORM" --config-only --release
