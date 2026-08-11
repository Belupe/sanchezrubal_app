import 'package:flutter_test/flutter_test.dart';
import 'package:portal_familia/config.dart';
import 'package:portal_familia/services/update_service.dart';

void main() {
  final host = Uri.parse(AppConfig.updateBaseUrl).host;

  group('UpdateService.esUrlDeConfianza', () {
    test('acepta https del mismo host', () {
      expect(
        UpdateService.esUrlDeConfianza(
            'https://$host/linux/portal-familia-x86_64.AppImage'),
        isTrue,
      );
    });

    test('rechaza http aunque sea el mismo host', () {
      expect(
        UpdateService.esUrlDeConfianza('http://$host/linux/x.AppImage'),
        isFalse,
      );
    });

    test('rechaza otro dominio', () {
      expect(
        UpdateService.esUrlDeConfianza('https://malicioso.example/x.AppImage'),
        isFalse,
      );
    });

    test('rechaza un subdominio parecido', () {
      expect(
        UpdateService.esUrlDeConfianza('https://$host.malicioso.example/x.deb'),
        isFalse,
      );
    });

    test('rechaza credenciales incrustadas que simulan el host', () {
      expect(
        UpdateService.esUrlDeConfianza('https://$host@malicioso.example/x.deb'),
        isFalse,
      );
    });

    test('rechaza file:// y otros esquemas', () {
      expect(UpdateService.esUrlDeConfianza('file:///tmp/x.AppImage'), isFalse);
      expect(UpdateService.esUrlDeConfianza('ftp://$host/x.deb'), isFalse);
    });

    test('rechaza cadenas vacías o sin host', () {
      expect(UpdateService.esUrlDeConfianza(''), isFalse);
      expect(UpdateService.esUrlDeConfianza('no-es-una-url'), isFalse);
      expect(UpdateService.esUrlDeConfianza('https://'), isFalse);
    });
  });

  group('UpdateInfo', () {
    UpdateInfo conCanal(UpdateChannel c) => UpdateInfo(
          versionName: '1.0.1',
          url: AppConfig.updateBaseUrl,
          sha256: 'abc',
          notes: '',
          mandatory: false,
          channel: c,
        );

    test('solo el canal de sistema pide contraseña', () {
      expect(conCanal(UpdateChannel.linuxSistema).pideContrasena, isTrue);
      for (final c in [
        UpdateChannel.windows,
        UpdateChannel.linuxAppImage,
        UpdateChannel.linuxUsuario,
        UpdateChannel.soloAvisar,
      ]) {
        expect(conCanal(c).pideContrasena, isFalse, reason: c.name);
      }
    });

    test('el canal "solo avisar" no instala nada', () {
      expect(conCanal(UpdateChannel.soloAvisar).puedeInstalarSola, isFalse);
      expect(conCanal(UpdateChannel.linuxAppImage).puedeInstalarSola, isTrue);
    });
  });
}
