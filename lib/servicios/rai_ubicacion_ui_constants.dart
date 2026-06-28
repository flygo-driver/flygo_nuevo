/// Textos compartidos cliente + taxista (estilo Uber / inDriver).
class RaiUbicacionUiConstants {
  RaiUbicacionUiConstants._();

  static const String accionActivarUbicacion = 'Activar ubicación';

  /// Banner rojo / permiso bloqueado: abre ajustes del teléfono.
  static const String accionAbrirAjustesUbicacion = 'Abrir ajustes';

  static const String msgEsperandoCuadroTelefono =
      'Confirma en el cuadro del teléfono: elige «Permitir» o '
      '«Al usar la app». RAI recordará que lo activaste desde la app.';

  static const String msgEsperandoUbicacion =
      'RAI necesita tu ubicación. Toca «Activar ubicación» en el aviso '
      '(se abre el cuadro del teléfono sin salir de RAI).';

  static const String msgIrAjustesManual =
      'Abre Permisos → Ubicación → «Al usar la app». También en Cuenta → Ubicación.';

  static const String tituloConfigUbicacion = 'Ubicación en RAI';

  static const String subtituloConfigUbicacionActiva =
      'RAI puede usar tu ubicación para cotizar, navegar y recibir viajes.';

  static const String accionAjustesManual = 'Abrir permisos en el teléfono';
}
