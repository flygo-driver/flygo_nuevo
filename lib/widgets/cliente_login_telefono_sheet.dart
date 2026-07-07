import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/servicios/phone_auth_error_es.dart';
import 'package:flygo_nuevo/servicios/rai_phone_login_flow.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';
import 'package:flygo_nuevo/widgets/rai_sms_otp_input.dart';

/// Pantalla dedicada SMS (conductor u otros accesos). Mismo flujo que bienvenida.
class ClienteLoginTelefonoPage extends StatefulWidget {
  const ClienteLoginTelefonoPage({
    super.key,
    this.entradaRol = 'cliente',
    this.telefonoInicial,
  });

  final String entradaRol;
  final String? telefonoInicial;

  static Future<void> abrir(
    BuildContext context, {
    String entradaRol = 'cliente',
    String? telefonoInicial,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ClienteLoginTelefonoPage(
          entradaRol: entradaRol,
          telefonoInicial: telefonoInicial,
        ),
      ),
    );
  }

  @override
  State<ClienteLoginTelefonoPage> createState() =>
      _ClienteLoginTelefonoPageState();
}

class _ClienteLoginTelefonoPageState extends State<ClienteLoginTelefonoPage> {
  final _telCtrl = TextEditingController();
  String? _verificationId;
  bool _codigoEnviado = false;
  bool _cargando = false;
  int _otpSession = 0;
  String _codigoParcial = '';
  String? _telE164Guardado;
  String _estadoMsg = '';

  @override
  void initState() {
    super.initState();
    final ini = widget.telefonoInicial;
    if (ini != null && ini.trim().isNotEmpty) {
      _telCtrl.text = ini.replaceAll(RegExp(r'\D'), '');
    }
  }

  @override
  void dispose() {
    _telCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _completarAuto(PhoneAuthCredential cred, String tel) async {
    try {
      await RaiPhoneLoginFlow.entrarConCredencial(
        context: context,
        cred: cred,
        telE164: tel,
        entradaRol: widget.entradaRol,
      );
    } on FirebaseAuthException catch (e) {
      _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
    } catch (e) {
      _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
    }
  }

  Future<void> _enviarCodigo() async {
    final tel = RaiPhoneLoginFlow.normalizarTelRd(_telCtrl.text.trim());
    if (tel.length < 12) {
      _snack('Escribe un número de RD (10 dígitos).');
      return;
    }
    if (_cargando) return;

    final ok = await RaiPhoneLoginFlow.confirmarVerificacionSeguridad(context);
    if (!ok || !mounted) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _estadoMsg =
          'Verificando con Google… Si ves pantalla en blanco, tocá Atrás '
          'del teléfono y probá de nuevo.';
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
        _telE164Guardado = tel;
        _codigoEnviado = true;
        _codigoParcial = '';
        _otpSession++;
        _cargando = false;
        _estadoMsg = 'Código enviado. Se rellena solo o escribí los 6 dígitos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _estadoMsg = '';
      });
      _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
    }
  }

  Future<void> _confirmarCodigo([String? codigoIngresado]) async {
    final vId = _verificationId;
    if (vId == null || vId.isEmpty) {
      _snack('Primero solicita el código.');
      return;
    }
    final codigo = (codigoIngresado ?? _codigoParcial)
        .replaceAll(RegExp(r'\D'), '')
        .trim();
    if (codigo.length < 6) {
      _snack('Escribe el código de 6 dígitos del SMS.');
      return;
    }
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: codigo,
      );
      await RaiPhoneLoginFlow.entrarConCredencial(
        context: context,
        cred: cred,
        telE164: _telE164Guardado ??
            RaiPhoneLoginFlow.normalizarTelRd(_telCtrl.text.trim()),
        entradaRol: widget.entradaRol,
      );
    } on FirebaseAuthException catch (e) {
      _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
    } catch (e) {
      _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return RaiEntradaScaffold(
      mostrarAtras: !_cargando,
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RaiEntradaHero(
              compacto: true,
              mostrarEslogan: false,
            ),
            const SizedBox(height: 12),
            Text(
              _codigoEnviado
                  ? 'Código de verificación'
                  : 'Entrar con teléfono',
              style: c.estiloTitulo,
            ),
            const SizedBox(height: 8),
            Text(
              _codigoEnviado
                  ? 'Te enviamos un código de 6 dígitos por SMS.'
                  : '809, 829 o 849. Te mandamos un código para entrar.',
              style: c.estiloSubtitulo,
            ),
            if (_estadoMsg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bannerFondo,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.bannerBorde),
                ),
                child: Text(
                  _estadoMsg,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textoPrincipal,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!_codigoEnviado)
              TextField(
                controller: _telCtrl,
                enabled: !_cargando,
                keyboardType: TextInputType.phone,
                style: c.estiloCampo,
                cursorColor: RaiEntradaColores.raiVerde,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: raiCampoEntradaDecoration(
                  context,
                  label: 'Teléfono',
                  hint: '8095551234',
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                ).copyWith(prefixText: '+1 '),
              )
            else
              RaiSmsOtpInput(
                key: ValueKey<int>(_otpSession),
                enabled: !_cargando,
                onChanged: (v) => _codigoParcial = v,
                onCompleted: _confirmarCodigo,
              ),
            const SizedBox(height: 20),
            if (!_codigoEnviado || !_cargando)
              raiBotonContinuar(
                onPressed: _cargando
                    ? null
                    : (_codigoEnviado ? () => _confirmarCodigo() : _enviarCodigo),
                label: _cargando
                    ? 'Espera...'
                    : (_codigoEnviado ? 'Entrar' : 'Enviar código SMS'),
                cargando: _cargando && !_codigoEnviado,
              ),
          ],
        ),
      ),
    );
  }
}

class ClienteLoginTelefonoSheet extends StatelessWidget {
  const ClienteLoginTelefonoSheet({super.key, this.entradaRol = 'cliente'});

  final String entradaRol;

  static Future<void> mostrar(
    BuildContext context, {
    String entradaRol = 'cliente',
  }) {
    return ClienteLoginTelefonoPage.abrir(context, entradaRol: entradaRol);
  }

  @override
  Widget build(BuildContext context) {
    return ClienteLoginTelefonoPage(entradaRol: entradaRol);
  }
}
