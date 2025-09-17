// lib/pantallas/seguridad/phone_verify_sheet.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../servicios/phone_auth_service.dart';

class PhoneVerifySheet extends StatefulWidget {
  final String rol;           // 'cliente' | 'taxista' (solo para guardar contexto)
  final bool forceReauth;     // true = reauth; false = link si no tiene
  const PhoneVerifySheet({super.key, required this.rol, this.forceReauth = false});

  @override
  State<PhoneVerifySheet> createState() => _PhoneVerifySheetState();
}

class _PhoneVerifySheetState extends State<PhoneVerifySheet> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _phoneCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();

  String? _verificationId;
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    // ⚠️ Capturamos el messenger ANTES del await
    final messenger = ScaffoldMessenger.of(context);

    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Número inválido. Use formato +1829XXXXXXX')),
      );
      return;
    }

    if (mounted) setState(() => _sending = true);
    try {
      final vId = await PhoneAuthService.sendCode(
        phoneNumber: phone,
        onInstantVerification: (cred) async {
          // Verificación instantánea en algunos dispositivos
          final user = _auth.currentUser!;
          if (widget.forceReauth) {
            await user.reauthenticateWithCredential(cred);
          } else {
            await user.linkWithCredential(cred);
          }
          await _saveOk(phone);
          if (!mounted) return;
          Navigator.pop(context, true);
        },
      );

      if (!mounted) return;
      setState(() => _verificationId = vId);
    } catch (e) {
      // Usamos el messenger ya capturado (no reusamos context tras await)
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmCode() async {
    // ⚠️ Capturamos el messenger ANTES del await
    final messenger = ScaffoldMessenger.of(context);

    if (_verificationId == null) return;
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Código incompleto')),
      );
      return;
    }

    if (mounted) setState(() => _verifying = true);
    try {
      if (widget.forceReauth) {
        await PhoneAuthService.reauthWithSms(
          verificationId: _verificationId!, smsCode: code,
        );
      } else {
        await PhoneAuthService.linkWithSms(
          verificationId: _verificationId!, smsCode: code,
        );
      }

      await _saveOk(_phoneCtrl.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // Usamos el messenger ya capturado
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo verificar: $e')),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _saveOk(String phone) async {
    final user = _auth.currentUser!;
    final ref = _db.collection('usuarios').doc(user.uid);
    await ref.set({
      'telefono': phone,
      'phoneVerified': true,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'lastPhoneReauthAt': FieldValue.serverTimestamp(),
      // Conserva rol existente; si no existe, usa el que vino
      'rol': widget.rol,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final isStep2 = _verificationId != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, bottom: 16,
        top: 12 + MediaQuery.of(context).viewInsets.top,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isStep2 ? 'Ingresa el código' : 'Verifica tu teléfono',
            style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (!isStep2)
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Teléfono (E.164, ej. +1829XXXXXXX)',
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

          if (isStep2)
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Código de 6 dígitos',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.sms, color: Colors.greenAccent),
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

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_sending || _verifying)
                  ? null
                  : (isStep2 ? _confirmCode : _sendCode),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: (_sending || _verifying)
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isStep2 ? 'Confirmar código' : 'Enviar código'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
