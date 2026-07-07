import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:sms_autofill/sms_autofill.dart';

import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';

/// 6 casillas OTP estilo Uber: autofill del SMS + auto-completar al llegar el código.
class RaiSmsOtpInput extends StatefulWidget {
  const RaiSmsOtpInput({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = true,
  });

  final void Function(String code) onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;

  @override
  State<RaiSmsOtpInput> createState() => _RaiSmsOtpInputState();
}

class _RaiSmsOtpInputState extends State<RaiSmsOtpInput> with CodeAutoFill {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _completado = false;

  @override
  void initState() {
    super.initState();
    _iniciarEscuchaSms();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Future<void> _iniciarEscuchaSms() async {
    try {
      await SmsAutoFill().unregisterListener();
      listenForCode();
    } catch (_) {}
  }

  @override
  void codeUpdated() {
    final recibido = (code ?? '').replaceAll(RegExp(r'\D'), '');
    if (recibido.length < 6 || !widget.enabled || _completado) return;
    _ctrl.text = recibido;
    _entregar(recibido);
  }

  void _entregar(String pin) {
    if (_completado || pin.length != 6) return;
    _completado = true;
    widget.onCompleted(pin);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final texto = c.campoTexto;
    final fondo = c.campoFondo;
    final bordeNormal = c.campoBorde;
    const verde = RaiEntradaColores.raiVerde;

    final base = PinTheme(
      width: 46,
      height: 54,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: texto,
      ),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bordeNormal),
      ),
    );

    return Pinput(
      length: 6,
      controller: _ctrl,
      focusNode: _focus,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofillHints: const [AutofillHints.oneTimeCode],
      defaultPinTheme: base,
      focusedPinTheme: base.copyWith(
        decoration: base.decoration!.copyWith(
          border: Border.all(color: verde, width: 2),
        ),
      ),
      submittedPinTheme: base,
      followingPinTheme: base,
      disabledPinTheme: base.copyWith(
        textStyle: base.textStyle!.copyWith(
          color: texto.withValues(alpha: 0.4),
        ),
      ),
      separatorBuilder: (index) => const SizedBox(width: 8),
      hapticFeedbackType: HapticFeedbackType.lightImpact,
      onCompleted: _entregar,
      onChanged: (v) {
        if (v.length < 6) _completado = false;
        widget.onChanged?.call(v);
      },
    );
  }
}
