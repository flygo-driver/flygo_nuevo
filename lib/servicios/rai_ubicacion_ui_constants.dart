import 'package:flutter/foundation.dart' show kIsWeb;

/// Textos compartidos cliente + taxista (estilo RAI).
class RaiUbicacionUiConstants {
  RaiUbicacionUiConstants._();

  static const String accionActivarUbicacion = 'Activar ubicación';

  /// Banner rojo / permiso bloqueado: abre ajustes del teléfono (móvil)
  /// o pide de nuevo el permiso del navegador (web).
  static const String accionAbrirAjustesUbicacion = 'Abrir ajustes';

  static const String msgEsperandoCuadroTelefono =
      'Confirma en el cuadro del teléfono: elige «Permitir» o '
      '«Al usar la app». RAI recordará que lo activaste desde la app.';

  static const String msgEsperandoCuadroNavegador =
      'Confirma en el cuadro del navegador: elige «Permitir» ubicación.';

  static const String msgEsperandoUbicacion =
      'RAI necesita tu ubicación. Toca «Activar ubicación» en el aviso '
      '(se abre el cuadro del teléfono sin salir de RAI).';

  static const String msgEsperandoUbicacionWeb =
      'RAI necesita tu ubicación. Toca «Activar ubicación» y elige «Permitir» '
      'en el cuadro del navegador.';

  static const String msgIrAjustesManual =
      'Abre Permisos → Ubicación → «Al usar la app». También en Cuenta → Ubicación.';

  /// Chrome / Edge / Firefox: no hay “ajustes de la app”.
  static const String msgIrAjustesManualWeb =
      'Si no aparece el cuadro: candado junto a la URL → Permisos del sitio → '
      'Ubicación → Permitir. Luego toca «Ya lo permití» o «Activar ubicación».';

  static const String msgDialogoAyudaUbicacionWeb =
      'Chrome ya bloqueó la ubicación para este sitio. '
      'Recargar la página (F5 o Ctrl+Shift+R) NO lo arregla.\n\n'
      '1. Tocá el candado (o ⓘ) a la izquierda de la URL.\n'
      '2. Permisos del sitio → Ubicación → Permitir.\n'
      '3. Volvé acá y tocá «Ya lo permití».\n\n'
      'Si Windows pide permiso de ubicación, aceptalo también.\n'
      'Conductor en laptop: sin ubicación no recibe viajes; usá el teléfono '
      'o permití ubicación en Chrome.';

  static const String tituloConfigUbicacion = 'Ubicación en RAI';

  static const String subtituloConfigUbicacionActiva =
      'RAI puede usar tu ubicación para cotizar, navegar y recibir viajes.';

  static const String accionAjustesManual = 'Abrir permisos en el teléfono';

  static const String accionAjustesManualWeb = 'Pedir permiso del navegador';

  static String get msgEsperandoUbicacionPlataforma =>
      kIsWeb ? msgEsperandoUbicacionWeb : msgEsperandoUbicacion;

  static String get msgIrAjustesManualPlataforma =>
      kIsWeb ? msgIrAjustesManualWeb : msgIrAjustesManual;

  static String get accionAjustesManualPlataforma =>
      kIsWeb ? accionAjustesManualWeb : accionAjustesManual;
}
