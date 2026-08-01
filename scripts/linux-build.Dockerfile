# =====================================================================
#  linux-build.Dockerfile  —  Imagen de compilación de la app de Linux
# =====================================================================
#  Flutter NO compila Linux en cruzado desde Windows, así que la app de
#  escritorio de Linux se compila DENTRO de este contenedor. El repo ya
#  depende de Docker (compose.yaml), así que no hace falta instalar nada
#  nuevo en el PC de desarrollo.
#
#  La usa scripts/build-linux.ps1 (Windows) o directamente:
#    docker build -f scripts/linux-build.Dockerfile -t portal-familia/linux-build:3.44.6 scripts
#    docker run --rm -v "$PWD:/src" -w /src portal-familia/linux-build:3.44.6 \
#           bash scripts/build-linux.sh
#
#  ⚠️  BASE UBUNTU 22.04 A PROPÓSITO — NO LA SUBAS SIN LEER ESTO:
#  glibc es compatible HACIA ATRÁS pero NO HACIA ADELANTE. Un binario
#  compilado contra una glibc NUEVA muere en una distro con una MÁS VIEJA
#  ("version 'GLIBC_2.xx' not found"), y ni AppImage ni .deb lo arreglan
#  (empaquetan las librerías de la app, no la libc del sistema). La única
#  solución es compilar sobre la base más antigua que se quiera soportar.
#  22.04 = glibc 2.35, que cubre Ubuntu 22.04+, Debian 12+, Kali rolling,
#  Arch, Fedora 36+, Mint 21+ y Pop 22.04+.
# =====================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# Misma versión que app_flutter/ci_scripts/flutter_ci_bootstrap.sh, para que
# la build de Linux == la de Apple == la local.
ENV FLUTTER_VERSION=3.44.6
ENV PATH="/opt/flutter/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
      # Toolchain que exige `flutter doctor` para el target linux.
      clang cmake ninja-build pkg-config build-essential \
      # GTK3: aporta los pkg-config gtk+-3.0 / glib-2.0 / gio-2.0.
      libgtk-3-dev \
      # flutter_secure_storage_linux 3.0.1 → solo libsecret-1 >= 0.18.4.
      # (libjsoncpp-dev NO hace falta: la 3.x vendoriza nlohmann/json.)
      libsecret-1-dev libsecret-1-0 \
      # SDK de Flutter + utilidades de empaquetado.
      git curl ca-certificates unzip xz-utils zip file desktop-file-utils \
      # .deb: dpkg-deb, dpkg-shlibdeps y construcción sin ser root.
      dpkg-dev fakeroot \
      # AppImage: el runtime type-2 se automonta con FUSE 2.
      libfuse2 \
      # Comprobaciones sin escritorio: arranque headless y objdump/ldd.
      xvfb mesa-utils libgl1-mesa-dri binutils \
  && rm -rf /var/lib/apt/lists/*

# Flutter FIJADO por tag (mismo patrón que ci_scripts/flutter_ci_bootstrap.sh).
RUN git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" /opt/flutter \
 && git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --enable-linux-desktop \
 && flutter precache --linux \
 && flutter --version

# appimagetool empaqueta el AppDir en el .AppImage final. Es a su vez un
# AppImage y necesita /dev/fuse para automontarse; dentro de un contenedor
# normal eso no existe, así que se fuerza el modo extraer-y-ejecutar.
RUN curl -fsSL -o /usr/local/bin/appimagetool \
      https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage \
 && chmod +x /usr/local/bin/appimagetool
ENV APPIMAGE_EXTRACT_AND_RUN=1

# El repo se monta aquí (-v "$PWD:/src").
WORKDIR /src
