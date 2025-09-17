// lib/pantallas/shared/boarding_pin_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../servicios/trips_service.dart';

class BoardingPinSheet extends StatefulWidget {
  final String tripId;
  const BoardingPinSheet({super.key, required this.tripId});

  @override
  State<BoardingPinSheet> createState() => _BoardingPinSheetState();
}

class _BoardingPinSheetState extends State<BoardingPinSheet> {
  final _pinCtrl = TextEditingController();
  bool _generando = false;
  bool _confirmando = false;

  String? _pinActual;
  DateTime? _pinExpira;

  @override
  void initState() {
    super.initState();
    _cargarPinActual();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPinActual() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.tripId)
          .get();
      if (!mounted || !doc.exists) return;

      final d = doc.data()!;
      final pin = (d['boardingPin'] ?? '').toString();

      DateTime? exp;
      final expTs = d['boardingPinExpiresAt'];
      if (expTs is Timestamp) exp = expTs.toDate();

      setState(() {
        _pinActual = pin.isEmpty ? null : pin;
        _pinExpira = exp;
      });
    } catch (_) {}
  }

  Future<void> _emitirPin() async {
    if (_generando) return;
    setState(() => _generando = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      final res = await TripsService.emitirPin(widget.tripId, ttlMinutes: 240);
      if (!mounted) return;
      setState(() {
        _pinActual = res.pin;
        _pinExpira = res.expiresAt;
      });
      msg.showSnackBar(const SnackBar(content: Text('🔐 PIN generado')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('No se pudo generar PIN: $e')));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _confirmarAbordaje() async {
    if (_confirmando) return;
    final pin = _pinCtrl.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa los 6 dígitos del PIN.')),
      );
      return;
    }
    setState(() => _confirmando = true);
    final msg = ScaffoldMessenger.of(context);

    try {
      await TripsService.confirmarAbordaje(widget.tripId, pin);
      if (!mounted) return;
      Navigator.pop(context, true);
      msg.showSnackBar(const SnackBar(content: Text('✅ Cliente a bordo')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('PIN inválido o expirado: $e')));
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Wrap(
          runSpacing: 12,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Abordaje por PIN',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),

            // PIN vigente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.06),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PIN vigente', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pinActual ?? '— — — — — —',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _generando ? null : _emitirPin,
                        icon: _generando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _generando
                              ? 'Generando...'
                              : (_pinActual == null ? 'Generar PIN' : 'Regenerar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_pinExpira != null)
                    Text(
                      'Vence: ${fmt.format(_pinExpira!)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Text('Confirmar abordaje (6 dígitos del cliente)',
                style: TextStyle(color: Colors.white70)),
            TextField(
              controller: _pinCtrl,
              maxLength: 6,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              // SIN 'const' en la lista: evita el error non_constant_list_element
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmando ? null : _confirmarAbordaje,
                icon: _confirmando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar y marcar A BORDO'),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Solo el taxista asignado puede generar/validar PIN.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
