import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/auth/cliente_entrada_rapida.dart';
import 'package:flygo_nuevo/servicios/phone_auth_error_es.dart';
import 'package:flygo_nuevo/servicios/rai_phone_login_flow.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';
import 'package:flygo_nuevo/widgets/rai_login_correo_page.dart';
import 'package:flygo_nuevo/widgets/rai_sms_otp_input.dart';

/// Entrada: teléfono en pantalla → SMS en el mismo lugar (sin saltar a otra ruta).
enum RaiEntradaTema { claro, oscuro }

class RaiEntradaSocialPanel extends StatefulWidget {
  const RaiEntradaSocialPanel({
    super.key,
    required this.entradaRol,
    this.tema = RaiEntradaTema.claro,
    this.onError,
    this.subtitulo,
    this.titulo,
    this.mostrarCorreo = true,
    this.ocultarTitulo = false,
    this.postLoginRoute,
    this.googleSolo = false,
    this.modoCorporativo = false,
  });

  final String entradaRol;
  final RaiEntradaTema tema;
  final void Function(String mensaje)? onError;
  final String? subtitulo;
  final String? titulo;
  final bool mostrarCorreo;
  final bool ocultarTitulo;
  final String? postLoginRoute;
  /// Web corporativo: solo botón Google (sin teléfono ni correo).
  final bool googleSolo;
  final bool modoCorporativo;

  @override
  State<RaiEntradaSocialPanel> createState() => _RaiEntradaSocialPanelState();
}

class _RaiEntradaSocialPanelState extends State<RaiEntradaSocialPanel> {
  final _telCtrl = TextEditingController();

  bool _cargandoGoogle = false;
  bool _cargandoTel = false;
  bool _codigoEnviado = false;
  int _otpSession = 0;
  String _codigoParcial = '';
  String? _verificationId;
  String? _telE164;
  String _estadoMsg = '';
  String? _errorMsg;
  bool _errorDestacarGoogle = false;

  static const Color _raiVerdeClaro = Color(0xFF00E676);
  static const Color _googleAzul = Color(0xFF4285F4);
  static const Color _correoAzul = Color(0xFF1565C0);

  String get _rol =>
      widget.entradaRol.trim().toLowerCase() == 'taxista' ? 'taxista' : 'cliente';

  String get _tituloDefault {
    if (_esCorporativo) return 'Entrá como encargado corporativo';
    return _rol == 'taxista'
        ? 'Entrá o registrate como conductor'
        : 'Entrá o registrate';
  }

  bool get _esCorporativo =>
      widget.modoCorporativo ||
      (widget.postLoginRoute ?? '').trim() == '/corporativo';

  bool get _soloGoogle => widget.googleSolo;

  bool get _ocultarTelefono => _soloGoogle || _esCorporativo;

  bool get _ocultarCorreo => _soloGoogle;

  @override
  void dispose() {
    _telCtrl.dispose();
    super.dispose();
  }

  void _error(String msg, {bool destacarGoogle = false}) {
    final mostrarGoogle = destacarGoogle ||
        msg.contains('Google') ||
        msg.contains('reCAPTCHA') ||
        msg.contains('WebView');
    if (mounted) {
      setState(() {
        _errorMsg = msg;
        _errorDestacarGoogle = mostrarGoogle;
      });
    }
    // Siempre notificar: si hay role-mismatch se cierra sesión y el panel
    // se remonta; el padre debe mostrar snack/diálogo con el motivo.
    widget.onError?.call(msg);
  }

  void _limpiarError() {
    if (_errorMsg == null) return;
    setState(() {
      _errorMsg = null;
      _errorDestacarGoogle = false;
    });
  }

  String _digitosTel() => _telCtrl.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _completarAuto(PhoneAuthCredential cred, String tel) async {
    try {
      await RaiPhoneLoginFlow.entrarConCredencial(
        context: context,
        cred: cred,
        telE164: tel,
        entradaRol: _rol,
      );
    } on FirebaseAuthException catch (e) {
      _error(phoneAuthErrorEs(e, entradaRol: _rol));
    } catch (e) {
      _error(phoneAuthErrorEs(e, entradaRol: _rol));
    }
  }

  Future<void> _enviarSms() async {
    final d = _digitosTel();
    if (d.length != 10) {
      _error('Escribe tu número de RD (10 dígitos: 809, 829 o 849).');
      return;
    }
    if (_cargandoTel) return;

    _limpiarError();
    final ok = await RaiPhoneLoginFlow.confirmarVerificacionSeguridad(context);
    if (!ok || !mounted) return;

    final tel = RaiPhoneLoginFlow.normalizarTelRd(d);
    FocusScope.of(context).unfocus();
    setState(() {
      _cargandoTel = true;
      _estadoMsg =
          'Verificando con Google… Si ves pantalla en blanco, tocá Atrás '
          'del teléfono y probá de nuevo o usá Google abajo.';
    });

    try {
      final vId = await RaiPhoneLoginFlow.solicitarCodigoSms(
        telefonoE164: tel,
        onAutoVerificado: (cred) => _completarAuto(cred, tel),
      );
      if (!mounted) return;
      if (vId.isEmpty) return;

      setState(() {
        _verificationId = vId;
        _telE164 = tel;
        _codigoEnviado = true;
        _codigoParcial = '';
        _otpSession++;
        _cargandoTel = false;
        _estadoMsg = 'Código enviado. Se rellena solo o escribí los 6 dígitos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoTel = false;
        _estadoMsg = '';
      });
      final msg = phoneAuthErrorEs(e, entradaRol: _rol);
      _error(msg, destacarGoogle: msg.contains('reCAPTCHA'));
    }
  }

  Future<void> _confirmarCodigo([String? codigoIngresado]) async {
    final vId = _verificationId;
    if (vId == null || vId.isEmpty) {
      _error('Primero pedí el código SMS.');
      return;
    }
    final codigo = (codigoIngresado ?? _codigoParcial)
        .replaceAll(RegExp(r'\D'), '');
    if (codigo.length < 6) {
      _error('Escribí el código de 6 dígitos del SMS.');
      return;
    }
    if (_cargandoTel) return;

    _limpiarError();
    setState(() {
      _cargandoTel = true;
      _estadoMsg = 'Verificando código…';
    });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: codigo,
      );
      await RaiPhoneLoginFlow.entrarConCredencial(
        context: context,
        cred: cred,
        telE164: _telE164 ?? RaiPhoneLoginFlow.normalizarTelRd(_digitosTel()),
        entradaRol: _rol,
      );
    } on FirebaseAuthException catch (e) {
      _error(phoneAuthErrorEs(e, entradaRol: _rol));
    } catch (e) {
      _error(phoneAuthErrorEs(e, entradaRol: _rol));
    } finally {
      if (mounted) setState(() => _cargandoTel = false);
    }
  }

  void _cambiarNumero() {
    _limpiarError();
    setState(() {
      _codigoEnviado = false;
      _verificationId = null;
      _telE164 = null;
      _codigoParcial = '';
      _otpSession++;
      _estadoMsg = '';
    });
  }

  Future<void> _continuarTelefono() async {
    if (_codigoEnviado) {
      await _confirmarCodigo();
    } else {
      await _enviarSms();
    }
  }

  Future<void> _google() async {
    if (_cargandoGoogle) return;
    _limpiarError();
    setState(() => _cargandoGoogle = true);
    try {
      await ClienteEntradaRapida.loginGoogle(
        context,
        entradaRol: _rol,
        onMensaje: _error,
        postLoginRoute: widget.postLoginRoute,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _error(
            'Google no respondió. Si cerraste la ventana, tocá de nuevo '
            '«Entrar con Google».',
          );
        },
      );
    } finally {
      if (mounted) setState(() => _cargandoGoogle = false);
    }
  }

  Future<void> _correo() async {
    await RaiLoginCorreoPage.abrir(
      context,
      entradaRol: _rol,
      postLoginRoute: widget.postLoginRoute,
    );
  }

  Widget _botonLlamativo({
    required VoidCallback? onPressed,
    required Widget icon,
    required String label,
    required Color fondo,
    required Color texto,
    Color? borde,
    double elevacion = 2,
  }) {
    return Material(
      elevation: onPressed == null ? 0 : elevacion,
      shadowColor: fondo.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      color: onPressed == null ? fondo.withValues(alpha: 0.45) : fondo,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: borde != null
                ? Border.all(color: borde, width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              SizedBox(width: 30, child: Center(child: icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: texto,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cajaError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE57373), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFC62828), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMsg ?? '',
                  style: const TextStyle(
                    color: Color(0xFFB71C1C),
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (_errorDestacarGoogle) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: (_cargandoGoogle || _cargandoTel) ? null : _google,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                label: const Text(
                  'Entrar con Google ahora',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _googleAzul,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonContinuarPrincipal({required bool ocupado}) {
    return Material(
      elevation: ocupado ? 0 : 4,
      shadowColor: RaiEntradaColores.raiVerde.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: ocupado
                ? [
                    RaiEntradaColores.raiVerde.withValues(alpha: 0.45),
                    RaiEntradaColores.raiVerde.withValues(alpha: 0.35),
                  ]
                : [_raiVerdeClaro, RaiEntradaColores.raiVerde],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: ocupado ? null : _continuarTelefono,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _cargandoTel
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _codigoEnviado
                        ? (_cargandoTel ? 'Verificando…' : 'Confirmar código')
                        : 'Continuar',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final Color texto = c.textoPrincipal;
    final Color hint = c.textoSecundario;
    final Color borde = c.campoBorde;
    final Color campoBg = c.campoFondo;
    final bool ocupado = _cargandoGoogle || _cargandoTel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_codigoEnviado) ...[
          Text(
            'Confirmá tu número',
            style: TextStyle(
              color: texto,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Te enviamos un código de 6 dígitos. Al confirmarlo entrás o '
            'creás tu cuenta en RAI.',
            style: TextStyle(color: hint, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 8),
        ] else if (!widget.ocultarTitulo) ...[
          Text(
            widget.titulo ?? _tituloDefault,
            style: TextStyle(
              color: texto,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
          if (widget.subtitulo != null && widget.subtitulo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.subtitulo!,
              style: TextStyle(color: hint, fontSize: 14, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
        ] else if (widget.subtitulo != null && widget.subtitulo!.isNotEmpty) ...[
          Text(
            widget.subtitulo!,
            style: TextStyle(
              color: hint,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_estadoMsg.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bannerFondo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.bannerBorde),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_cargandoTel)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RaiEntradaColores.raiVerde,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _estadoMsg,
                    style: TextStyle(
                      color: texto.withValues(alpha: 0.85),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (_soloGoogle) ...[
          Text(
            'En el celular salen todas porque están guardadas en el teléfono.\n'
            'En la laptop Google solo lista las cuentas abiertas en Chrome.\n\n'
            'Para verlas igual que en el cel: en Chrome (arriba a la derecha) '
            'toca tu foto → «Agregar otra cuenta» y añade los mismos Gmail. '
            'Luego «Entrar con Google» y elige con un toque (sin clave).',
            style: TextStyle(color: hint, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 20),
          _botonLlamativo(
            onPressed: ocupado ? null : _google,
            icon: _cargandoGoogle
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const _GoogleLogoColores(invertido: true),
            label: _cargandoGoogle
                ? 'Abriendo Google…'
                : 'Entrar con Google',
            fondo: _googleAzul,
            texto: Colors.white,
            elevacion: 3,
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            _cajaError(),
          ],
        ] else if (!_codigoEnviado) ...[
          if (!_ocultarTelefono) ...[
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: campoBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borde, width: 1.2),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DO',
                          style: TextStyle(
                            color: texto,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '+1',
                          style: TextStyle(
                            color: texto,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: hint, size: 22),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 22, color: borde),
                  Expanded(
                    child: TextField(
                      controller: _telCtrl,
                      enabled: !ocupado,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onSubmitted: (_) => _continuarTelefono(),
                      style: c.estiloCampo,
                      decoration: InputDecoration(
                        hintText: 'Número de teléfono',
                        hintStyle: TextStyle(color: c.campoHint, fontSize: 16),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ] else if (!_ocultarTelefono) ...[
          RaiSmsOtpInput(
            key: ValueKey<int>(_otpSession),
            enabled: !ocupado,
            onChanged: (v) => _codigoParcial = v,
            onCompleted: _confirmarCodigo,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: ocupado ? null : _cambiarNumero,
              child: Text(
                'Cambiar número',
                style: TextStyle(
                  color: c.link,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_cargandoTel)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: RaiEntradaColores.raiVerde,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Entrando…',
                  style: TextStyle(
                    color: hint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            _botonContinuarPrincipal(ocupado: ocupado),
        ],
        if (!_soloGoogle && !_codigoEnviado) ...[
          if (!_ocultarTelefono) ...[
            const SizedBox(height: 16),
            _botonContinuarPrincipal(ocupado: ocupado),
          ],
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            _cajaError(),
          ],
          const SizedBox(height: 20),
          _botonLlamativo(
            onPressed: ocupado ? null : _google,
            icon: _cargandoGoogle
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const _GoogleLogoColores(invertido: true),
            label: _cargandoGoogle
                ? 'Abriendo Google…'
                : 'Continuar con Google',
            fondo: _googleAzul,
            texto: Colors.white,
            elevacion: 3,
          ),
          if (!_ocultarCorreo && widget.mostrarCorreo) ...[
            const SizedBox(height: 12),
            _botonLlamativo(
              onPressed: ocupado ? null : _correo,
              icon: const Icon(Icons.mail_rounded, color: Colors.white, size: 24),
              label: 'Entrar con correo y contraseña',
              fondo: _correoAzul,
              texto: Colors.white,
              elevacion: 3,
            ),
          ],
        ],
        if (_codigoEnviado && _errorMsg != null) ...[
          const SizedBox(height: 12),
          _cajaError(),
        ],
      ],
    );
  }
}

class _GoogleLogoColores extends StatelessWidget {
  const _GoogleLogoColores({this.invertido = false});

  final bool invertido;

  @override
  Widget build(BuildContext context) {
    if (invertido) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const _GoogleLogoColores(),
      );
    }
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      3.14,
      1.57,
      true,
      paint,
    );
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      1.57,
      1.57,
      true,
      paint,
    );
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      0,
      1.57,
      true,
      paint,
    );
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      -1.57,
      1.57,
      true,
      paint,
    );

    paint.color = Colors.white;
    canvas.drawCircle(Offset(w * 0.52, h * 0.52), w * 0.28, paint);
    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.44, w * 0.42, h * 0.16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
