part of 'viaje_en_curso_cliente.dart';

/// Widgets de PIN / codigo de verificacion (extraido del monolito).
mixin _ViajeEnCursoClientePinWidgets on State<ViajeEnCursoCliente> {
  _ViajeEnCursoClienteState get _pinHost => this as _ViajeEnCursoClienteState;

  Widget _buildBotonTocaActualizarViaje({
    required String viajeId,
    bool compacto = false,
    bool enEsperaAbordo = false,
  }) {
    return Material(
      color: const Color(0xFF1A237E).withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pinHost._refrescandoViajeManual
            ? null
            : () => unawaited(_pinHost._refrescarEstadoViajeManual(viajeId)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? 12 : 14,
            vertical: compacto ? 10 : 12,
          ),
          child: Row(
            children: [
              if (_pinHost._refrescandoViajeManual)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.touch_app_rounded,
                  color: Color(0xFF80D8FF),
                  size: 24,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pinHost._refrescandoViajeManual
                          ? 'Actualizando…'
                          : 'TOCA AQUÍ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (!compacto && !_pinHost._refrescandoViajeManual) ...[
                      const SizedBox(height: 2),
                      Text(
                        enEsperaAbordo
                            ? '¿El conductor ya te marcó a bordo? Toca para ver tu PIN al instante.'
                            : '¿No ves tu PIN arriba? Toca para actualizar y mostrarlo.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!_pinHost._refrescandoViajeManual)
                const Icon(Icons.refresh_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  /// Botón flotante sobre el mapa cuando el PIN aún no apareció en pantalla.
  Widget _buildBotonTocaActualizarViajeFlotante({
    required String viajeId,
    required bool enEsperaAbordo,
  }) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black54,
      child: _buildBotonTocaActualizarViaje(
        viajeId: viajeId,
        compacto: true,
        enEsperaAbordo: enEsperaAbordo,
      ),
    );
  }

  Widget _buildPinFlotanteEnMapa({
    required String viajeId,
    required String codigoVerificacion,
    required bool mostrar,
    required bool cargando,
    required bool esMotor,
  }) {
    if (!mostrar) return const SizedBox.shrink();
    final Color accent =
        esMotor ? const Color(0xFFFF5A00) : Colors.purpleAccent;
    final String pin = codigoVerificacion.replaceAll(RegExp(r'\D'), '');
    final bool tienePin = pin.length == 6;

    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 52,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(16),
        color: esMotor ? const Color(0xFF3A1E0C) : const Color(0xFF2A1338),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent, width: 1.6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.verified_user_rounded, color: accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Tu código de verificación',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cargando || !tienePin ? 'Generando código…' : pin,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: cargando || !tienePin ? 14 : 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: cargando || !tienePin ? 0 : 6,
                      ),
                    ),
                  ],
                ),
              ),
              if (tienePin && !cargando)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Actualizar PIN',
                      onPressed: _pinHost._refrescandoViajeManual
                          ? null
                          : () => unawaited(
                                _pinHost._refrescarEstadoViajeManual(viajeId),
                              ),
                      icon: _pinHost._refrescandoViajeManual
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white70,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Copiar código',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: pin));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado.')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodigoVerificacionClienteSection({
    required String codigoVerificacion,
    required bool codigoVerificado,
    required String estadoBase,
    required bool mostrarCodigo,
    required bool esMotor,
    String? viajeIdParaActualizar,
    bool integradoEnPanelConductor = false,
  }) {
    final EdgeInsets sectionMargin = integradoEnPanelConductor
        ? EdgeInsets.zero
        : const EdgeInsets.only(bottom: 16);
    final double sectionPadding = integradoEnPanelConductor ? 12 : 16;
    final Color accentColor =
        esMotor ? const Color(0xFFFF5A00) : Colors.purpleAccent;
    final List<Color> gradientColors = esMotor
        ? const [Color(0xFF3A1E0C), Color(0xFF251408)]
        : const [Color(0xFF2A1338), Color(0xFF1B0F2E)];

    if (mostrarCodigo) {
      final String pin = codigoVerificacion.replaceAll(RegExp(r'\D'), '');
      if (pin.length != 6 && _pinHost._pinEnsureEnCurso) {
        return Container(
          margin: sectionMargin,
          padding: EdgeInsets.all(sectionPadding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor, width: 1.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu código de verificación',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'El conductor te marcó a bordo. Generando tu código…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.35,
                ),
              ),
              if (viajeIdParaActualizar != null &&
                  viajeIdParaActualizar.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildBotonTocaActualizarViaje(
                  viajeId: viajeIdParaActualizar,
                  compacto: true,
                ),
              ],
            ],
          ),
        );
      }
      return Container(
        margin: sectionMargin,
        padding: EdgeInsets.all(sectionPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor, width: 1.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_rounded, color: accentColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tu código de verificación',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              estadoBase == EstadosViaje.aBordo
                  ? 'Compártelo con tu conductor para iniciar el viaje.'
                  : 'Tenlo listo: tu conductor lo pedirá al subir al vehículo.',
              style: const TextStyle(color: Colors.white70, height: 1.3),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor),
              ),
              child: Text(
                pin.length == 6 ? pin : codigoVerificacion,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: pin.length == 6 ? 30 : 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: pin.length == 6 ? 8 : 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (viajeIdParaActualizar != null &&
                    viajeIdParaActualizar.trim().isNotEmpty &&
                    estadoBase == EstadosViaje.aBordo &&
                    !codigoVerificado)
                  TextButton.icon(
                    onPressed: _pinHost._refrescandoViajeManual
                        ? null
                        : () => unawaited(
                              _pinHost._refrescarEstadoViajeManual(
                                viajeIdParaActualizar,
                              ),
                            ),
                    icon: _pinHost._refrescandoViajeManual
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _pinHost._refrescandoViajeManual
                          ? 'Actualizando…'
                          : 'Actualizar',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                onPressed: () {
                  final String copiar =
                      pin.length == 6 ? pin : codigoVerificacion;
                  Clipboard.setData(ClipboardData(text: copiar));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text(
                  'Copiar código',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ],
            ),
          ],
        ),
      );
    }

    if (estadoBase == EstadosViaje.aBordo &&
        !codigoVerificado &&
        codigoVerificacion.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: const Text(
          'Estás a bordo, pero este viaje no muestra un código de verificación en la app. '
          'Si el conductor lo necesita, contacta soporte.',
          style: TextStyle(color: Colors.white70, height: 1.35),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (codigoVerificado &&
        (estadoBase == EstadosViaje.aBordo ||
            estadoBase == EstadosViaje.enCurso)) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.55),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Código validado. Tu viaje está en marcha; sigue el avance en el mapa.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.28,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
