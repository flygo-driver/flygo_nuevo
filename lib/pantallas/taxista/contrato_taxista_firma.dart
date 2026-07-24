import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class ContratoTaxistaFirma extends StatefulWidget {
  const ContratoTaxistaFirma({super.key});

  @override
  State<ContratoTaxistaFirma> createState() => _ContratoTaxistaFirmaState();
}

class _ContratoTaxistaFirmaState extends State<ContratoTaxistaFirma> {
  bool _acepta = false;
  bool _guardando = false;

  Future<void> _abrirPdfContrato() async {
    final uri = Uri.parse(kTaxistaContractPdfUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el contrato en la web.')),
      );
    }
  }

  Future<void> _enviarCopiaCorreo() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    if (email.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Copia por correo (opcional)'),
          content: const Text(
            'Tu cuenta no tiene un correo vinculado a Firebase, así que no se puede abrir el '
            'cliente de correo con destinatario automático.\n\n'
            'Eso no impide operar: la aceptación legal del contrato se registra en la plataforma '
            'cuando marques «He leído y acepto…» y pulses «Firmar y continuar».\n\n'
            'Podés usar «Ver contrato» para leer el documento en la web.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject':
            'Copia contrato conductor RAI Driver v$kTaxistaContractVersion',
        'body':
            'Hola,\n\nAdjuntamos referencia del contrato digital firmado en RAI Driver.\n\n'
                'Version: $kTaxistaContractVersion\n'
                'Fecha de firma: se registra en la plataforma.\n'
                'PDF: $kTaxistaContractPdfUrl\n\nGracias.',
      },
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo abrir el correo para enviar la copia.')),
      );
    }
  }

  Future<void> _firmar() async {
    if (_guardando || !_acepta) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set({
        'contratoTaxistaAceptado': true,
        'contratoTaxistaVersion': kTaxistaContractVersion,
        'contratoTaxistaAceptadoEn': FieldValue.serverTimestamp(),
        'contratoTaxistaFirmaTipo': 'check_digital',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contrato firmado digitalmente. Ya puedes operar.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => const TaxistaShell()),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? 'No se pudo firmar el contrato. Verificá que tu cuenta sea de conductor '
              'y que tengas conexión. Si sigue fallando, contactá a RAI.'
          : 'No se pudo firmar el contrato. Intentá de nuevo.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo firmar el contrato. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(title: 'Contrato digital de conductor'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151515),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          kTaxistaContractText,
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ver PDF y enviar copia por correo son opcionales.',
                        style: TextStyle(
                          color: Colors.greenAccent.shade100
                              .withValues(alpha: 0.85),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _abrirPdfContrato,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Ver PDF'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _enviarCopiaCorreo,
                              icon: const Icon(Icons.mail_outline),
                              label: const Text('Enviar copia'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _acepta,
                onChanged: (v) => setState(() => _acepta = v == true),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'He leído y acepto este contrato digital',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: (_acepta && !_guardando) ? _firmar : null,
                  icon: const Icon(Icons.draw, size: 22),
                  label: Text(
                    _guardando ? 'Guardando firma...' : 'Firmar y continuar',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
