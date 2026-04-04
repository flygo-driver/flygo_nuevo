import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:image_picker/image_picker.dart';

class TransferenciaInfo extends StatefulWidget {
  final String viajeId;
  final double monto;

  const TransferenciaInfo({
    super.key,
    required this.viajeId,
    required this.monto,
  });

  @override
  State<TransferenciaInfo> createState() => _TransferenciaInfoState();
}

class _TransferenciaInfoState extends State<TransferenciaInfo> {
  bool _loading = false;
  bool _subiendoComprobante = false;
  String? _comprobanteUrl;

  String get _referencia => 'VIAJE-${widget.viajeId.substring(0, 6).toUpperCase()}';

  Future<void> _seleccionarComprobante() async {
    if (_subiendoComprobante) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;

    setState(() => _subiendoComprobante = true);
    try {
      final bytes = await file.readAsBytes();
      final path =
          'comprobantes/${user.uid}/${widget.viajeId}/transfer_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _comprobanteUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comprobante subido correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error Storage (${e.code}): ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo comprobante: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendoComprobante = false);
    }
  }

  Future<void> _yaTransferi() async {
    if (_loading) return;
    if ((_comprobanteUrl ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes subir el comprobante antes de continuar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ViajesRepo.marcarTransferenciaReportadaCliente(
        viajeId: widget.viajeId,
        comprobanteUrl: _comprobanteUrl!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transferencia reportada. Queda pendiente de confirmacion por Admin.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error Firestore (${e.code}): ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferencia bancaria')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Datos bancarios de RAI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('Banco: Banco Popular'),
            const Text('Cuenta: 001-123456-7'),
            const Text('Nombre: RAI APP SRL'),
            const Text('Cedula/RNC: 1-01-12345-6'),
            Text('Monto: ${FormatosMoneda.rd(widget.monto)}'),
            Text('Referencia: $_referencia'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _subiendoComprobante ? null : _seleccionarComprobante,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _subiendoComprobante
                      ? 'Subiendo comprobante...'
                      : (_comprobanteUrl == null
                          ? 'Subir comprobante'
                          : 'Comprobante cargado'),
                ),
              ),
            ),
            if (_comprobanteUrl != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Comprobante listo para revision de Admin',
                  style: TextStyle(color: Colors.green),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _yaTransferi,
                child: Text(_loading ? 'Procesando...' : 'Ya transferi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
