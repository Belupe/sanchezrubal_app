#!/bin/sh
# Xcode Cloud ejecuta este hook tras clonar el repo, para el target macOS.
# Delega en el bootstrap compartido (instala Flutter + genera config + Podfile + pod install).
set -e
exec "$CI_PRIMARY_REPOSITORY_PATH/app_flutter/ci_scripts/flutter_ci_bootstrap.sh" macos
