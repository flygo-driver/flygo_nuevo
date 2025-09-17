import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Destinos finales por rol
import 'package:flygo_nuevo/widgets/admin_gate.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';

class PhoneReauthGate extends StatefulWidget {
  final String rol; // 'cliente' | 'taxista' | 'admin'
  final int dias;   // vigencia de reauth en días (ej: 7 o 30)
  const PhoneReauthGate({super.key, required this.rol, this.dias = 30});

  @override
  State<PhoneReauthGate> createState() => _PhoneReauthGateState();
}

class _PhoneReauthGateState extends State<PhoneReauthGate> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String? _verificationId;
  int? _resendToken;
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown([int secs = 60]) {
    _timer?.cancel();
    setState(() => _secondsLeft = secs);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  String _normalizePhone(String raw) {
    var p = raw.trim();
    if (!p.startsWith('+')) {
      // DR normalmente +1 (809/829/849). Ajusta si usas multi-país.
      p = '+1$p';
    }
    return p.replaceAll(' ', '');
  }

  Future<void> _sendCode({bool resend = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No has iniciado sesión.');
      return;
    }
    final phone = _normalizePhone(_phoneCtrl.text);
    if (phone.length < 10) {
      setState(() => _error = 'Escribe un número válido (incluye +código).');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            // Reautentica y también asegura que el teléfono quede como principal.
            await user.reauthenticateWithCredential(credential);
            try {
              await user.updatePhoneNumber(credential); // 🔒 asegura phoneNumber en Auth
            } catch (_) {}
            await _onVerifiedSuccess(phone);
          } catch (e) {
            // si falla el auto-verify, el usuario puede introducir el código manualmente
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _error = e.message ?? 'Fallo al enviar código.');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _startCooldown(60);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Código enviado por SMS')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() => _verificationId = verificationId);
        },
      );
    } catch (e) {
      setState(() => _error = 'Error al enviar código: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No has iniciado sesión.');
      return;
    }
    if (_verificationId == null) {
      setState(() => _error = 'Primero envía el código a tu teléfono.');
      return;
    }
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Código inválido. Debe tener 6 dígitos.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );

      // Reautenticar con la credencial del SMS
      await user.reauthenticateWithCredential(cred);

      // Asegurar que el número queda asociado como phoneNumber principal:
      try {
        await user.updatePhoneNumber(cred); // 🔒
      } catch (_) {}

      // (Opcional) Link si no estaba linkeado (ignora si ya lo está)
      try {
        await user.linkWithCredential(cred);
      } catch (_) {}

      final phone = _normalizePhone(_phoneCtrl.text);
      await _onVerifiedSuccess(phone);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'No se pudo verificar el código.');
    } catch (e) {
      setState(() => _error = 'No se pudo verificar: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _onVerifiedSuccess(String phone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Actualiza perfil del usuario (tu app ya usa este doc)
    final usuariosRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
    await usuariosRef.set({
      'telefono': phone,
      'phoneVerified': true,
      'lastPhoneReauthAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 🔐 Además guarda sello de reauth y vigencia en /seguridad/{uid} (para el gate por caducidad)
    final segRef = FirebaseFirestore.instance.collection('seguridad').doc(user.uid);
    await segRef.set({
      'telefono': phone,
      'ultimoReauth': FieldValue.serverTimestamp(),
      'expiraCadaDias': widget.dias,
    }, SetOptions(merge: true));

    if (!mounted) return;

    // Redirige por rol
    Widget destino;
    switch (widget.rol) {
      case 'admin':
        destino = const AdminGate();
        break;
      case 'taxista':
        destino = const TaxistaEntry();
        break;
      default:
        destino = const ClienteHome();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destino),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Verificación por SMS', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Por seguridad, verifica tu número de teléfono. Vigencia: ${widget.dias} días.',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),

          // Teléfono
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Teléfono (incluye +código país, ej: +1 829...)',
              labelStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.phone, color: Colors.greenAccent),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.greenAccent),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Enviar código
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_sending || _secondsLeft > 0) ? null : () => _sendCode(),
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sms_outlined),
              label: Text(_secondsLeft > 0 ? 'Reenviar en ${_secondsLeft}s' : 'Enviar código por SMS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Código
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              labelText: 'Código de 6 dígitos',
              labelStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.verified, color: Colors.greenAccent),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.greenAccent),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Verificar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _verifying ? null : _verifyCode,
              icon: _verifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open),
              label: Text(_verifying ? 'Verificando...' : 'Verificar y continuar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}
