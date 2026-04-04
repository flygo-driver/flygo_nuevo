import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
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
        const SnackBar(content: Text('No se pudo abrir el PDF del contrato.')),
      );
    }
  }

  Future<void> _enviarCopiaCorreo() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu cuenta no tiene correo disponible.')),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Copia contrato conductor RAI Driver v$kTaxistaContractVersion',
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
        const SnackBar(content: Text('No se pudo abrir el correo para enviar la copia.')),
      );
    }
  }

  Future<void> _firmar() async {
    if (_guardando || !_acepta) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ViajeDisponible()),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error (${e.code}): ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo firmar: $e')),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    kTaxistaContractText,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _acepta,
              onChanged: (v) => setState(() => _acepta = v == true),
              title: const Text(
                'He leído y acepto este contrato digital',
                style: TextStyle(color: Colors.white),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_acepta && !_guardando) ? _firmar : null,
                icon: const Icon(Icons.draw),
                label: Text(_guardando ? 'Guardando firma...' : 'Firmar y continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
