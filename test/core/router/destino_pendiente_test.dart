import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/core/router/destino_pendiente.dart';

String? decidir(String ruta,
        {bool cargando = false, bool logueado = false}) =>
    decidirRedireccion(
      uri: Uri.parse(ruta),
      rutaActual: Uri.parse(ruta).path,
      cargandoSesion: cargando,
      logueado: logueado,
    );

void main() {
  group('el link de invitacion sobrevive el login', () {
    test('sin sesion, el link se guarda en vez de perderse', () {
      // Este es EL bug: antes esto devolvia '/auth/login' pelado y la
      // invitacion se perdia para siempre.
      expect(decidir('/join/abc123'), '/auth/login?from=%2Fjoin%2Fabc123');
    });

    test('en el login con el link guardado, no se mueve', () {
      expect(decidir('/auth/login?from=%2Fjoin%2Fabc123'), isNull);
    });

    test('al loguearse, va al link y no al dashboard', () {
      expect(decidir('/auth/login?from=%2Fjoin%2Fabc123', logueado: true),
          '/join/abc123');
    });

    test('el recorrido completo de quien no tenia cuenta', () {
      // 1. Abre el link. Firebase todavia esta resolviendo la sesion.
      var paso = decidir('/join/abc123', cargando: true);
      expect(paso, '/splash?from=%2Fjoin%2Fabc123');
      // 2. Resuelve: no hay sesion.
      paso = decidir(paso!);
      expect(paso, '/auth/login?from=%2Fjoin%2Fabc123');
      // 3. Toca "Crear cuenta".
      paso = rutaConservandoDestino('/auth/register', Uri.parse(paso!));
      expect(paso, '/auth/register?from=%2Fjoin%2Fabc123');
      // 4. Se crea la cuenta.
      expect(decidir(paso, logueado: true), '/join/abc123');
    });

    test('el link tambien sobrevive el rebote por el splash', () {
      expect(decidir('/splash?from=%2Fjoin%2Fabc123', logueado: true),
          '/join/abc123');
    });
  });

  group('sin link, el comportamiento de siempre', () {
    test('sin sesion va al login', () {
      expect(decidir('/dashboard'), '/auth/login?from=%2Fdashboard');
      expect(decidir('/auth/login'), isNull);
    });

    test('con sesion, entrar por el login lleva al dashboard', () {
      expect(decidir('/auth/login', logueado: true), '/dashboard');
      expect(decidir('/splash', logueado: true), '/dashboard');
    });

    test('con sesion y ya adentro, no redirige', () {
      expect(decidir('/dashboard', logueado: true), isNull);
      expect(decidir('/groups', logueado: true), isNull);
    });

    test('mientras carga la sesion espera en el splash', () {
      expect(decidir('/splash', cargando: true), isNull);
      expect(decidir('/dashboard', cargando: true),
          '/splash?from=%2Fdashboard');
    });

    test('cargando desde el login no se guarda el login como destino', () {
      // Volver al login despues de loguearse seria un rulo.
      expect(decidir('/auth/login', cargando: true), '/splash');
    });
  });

  group('un from de afuera no puede llevarte a otro dominio', () {
    // El `from` viene en la URL, que es lo que se comparte por WhatsApp.
    // Los navegadores leen `//dominio` y `/\dominio` como otro sitio.
    for (final malo in [
      '//evil.example',
      r'/\evil.example',
      'https://evil.example',
      'evil.example',
      '',
    ]) {
      test('se ignora un from de "$malo"', () {
        final uri = Uri.parse(
            '/auth/login?from=${Uri.encodeComponent(malo)}');
        expect(destinoGuardado(uri), isNull);
        expect(
          decidirRedireccion(
              uri: uri,
              rutaActual: '/auth/login',
              cargandoSesion: false,
              logueado: true),
          '/dashboard',
        );
      });
    }

    test('un from que vuelve al login o al splash se ignora', () {
      for (final rulo in ['/auth/login', '/auth/register', '/splash']) {
        expect(destinoGuardado(Uri.parse('/splash?from=$rulo')), isNull);
      }
    });
  });

  group('rutaConservandoDestino', () {
    test('sin from deja la ruta como estaba', () {
      expect(rutaConservandoDestino('/auth/register', Uri.parse('/auth/login')),
          '/auth/register');
    });

    test('un destino con query propio viaja entero', () {
      final uri = Uri.parse(
          '/auth/login?from=${Uri.encodeComponent('/receipts/7?tab=items')}');
      expect(destinoGuardado(uri), '/receipts/7?tab=items');
      expect(rutaConservandoDestino('/auth/register', uri),
          '/auth/register?from=%2Freceipts%2F7%3Ftab%3Ditems');
    });
  });
}
