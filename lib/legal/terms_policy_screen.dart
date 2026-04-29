import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';

class TermsPolicyScreen extends StatefulWidget {
  const TermsPolicyScreen({
    super.key,
    this.requireAcceptance = false,
    this.onAccepted,
  });

  final bool requireAcceptance;
  final VoidCallback? onAccepted;

  @override
  State<TermsPolicyScreen> createState() => _TermsPolicyScreenState();
}

class _TermsPolicyScreenState extends State<TermsPolicyScreen> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _acceptAndContinue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    setState(() => _saving = true);
    try {
      // Si ya hay sesión, guardamos aceptación en backend.
      // Si aún no hay sesión (login), solo confirmamos localmente vía callback.
      if (uid != null) {
        await LegalAcceptanceService.saveAcceptance(uid: uid);
      }
      if (!mounted) return;
      if (widget.onAccepted != null) {
        widget.onAccepted!.call();
      } else {
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo completar la aceptación en este momento. Inténtalo de nuevo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Terminos y Politica de Privacidad'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        automaticallyImplyLeading: !widget.requireAcceptance,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: cs.surfaceContainerHighest,
              child: Text(
                'Version $kTermsVersion  ·  Ultima actualizacion: $kTermsLastUpdate',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  kTermsFullText,
                  style: TextStyle(color: cs.onSurface, height: 1.5),
                ),
              ),
            ),
            if (widget.requireAcceptance)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
                  ),
                  color: cs.surface,
                ),
                child: Column(
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: cs.primary,
                      checkColor: cs.onSurface,
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      title: Text(
                        'Acepto los Terminos y Condiciones y la Politica de Privacidad de RAI DRIVER, operado por Open ASK Service SRL (RNC: 1320-11767).',
                        style: TextStyle(color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (_accepted && !_saving) ? _acceptAndContinue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                            _saving ? 'Guardando...' : 'Aceptar y continuar'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
