import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/pago_data.dart';
import '../../widgets/rai_app_bar.dart';
import '../../servicios/pay_config.dart';

class PagoMetodo extends StatefulWidget {
  /// Modo simple: sin viajeId/clienteId/montoDop -> solo selecciona y devuelve el método.
  /// Modo flujo de viaje: pasa viajeId, clienteId y montoDop para autorizar (mock) si elige Tarjeta.
  final String? viajeId;
  final String? clienteId;
  final double? montoDop;
  final String? emailClienteInicial; // opcional, si ya lo tienes

  const PagoMetodo({
    super.key,
    this.viajeId,
    this.clienteId,
    this.montoDop,
    this.emailClienteInicial,
  });

  @override
  State<PagoMetodo> createState() => _PagoMetodoState();
}

class _PagoMetodoState extends State<PagoMetodo> {
  String _metodo = 'Efectivo';
  bool _procesando = false;
  String? _error;

  bool get _esFlujoConViaje =>
      widget.viajeId != null &&
      widget.clienteId != null &&
      widget.montoDop != null;

  Future<void> _confirmar() async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      // Si es "Tarjeta" y hay datos de viaje, autorizamos (mock) ahora
      if (_metodo == 'Tarjeta' && _esFlujoConViaje) {
        final email = widget.emailClienteInicial ??
            FirebaseAuth.instance.currentUser?.email;
        await PagoData.autorizarPago(
          viajeId: widget.viajeId!,
          clienteId: widget.clienteId!,
          paymentMethodId: 'pm_mock',
          montoDop: widget.montoDop!,
          emailCliente: email,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('💳 Tarjeta autorizada (mock).')),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, _metodo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Método de pago',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RadioListTile<String>(
              value: 'Efectivo',
              groupValue: _metodo,
              onChanged: _procesando
                  ? null
                  : (String? v) => setState(() => _metodo = v!),
              activeColor: Colors.greenAccent,
              tileColor: Colors.grey[900],
              title: const Text(
                'Efectivo',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Pagas al finalizar el viaje. FlyGo registra la comisión al taxista.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'Transferencia',
              groupValue: _metodo,
              onChanged: _procesando
                  ? null
                  : (String? v) => setState(() => _metodo = v!),
              activeColor: Colors.greenAccent,
              tileColor: Colors.grey[900],
              title: const Text(
                'Transferencia',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Subes el comprobante según las instrucciones del viaje.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            if (PayConfig.pagosConTarjetaHabilitados) ...[
              const SizedBox(height: 8),
              RadioListTile<String>(
                value: 'Tarjeta',
                groupValue: _metodo,
                onChanged: _procesando
                    ? null
                    : (String? v) => setState(() => _metodo = v!),
                activeColor: Colors.greenAccent,
                tileColor: Colors.grey[900],
                title: const Text(
                  'Tarjeta',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _esFlujoConViaje
                      ? 'Se autoriza ahora y se captura al completar.'
                      : 'Se autorizará al confirmar tu viaje.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
            const Spacer(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '⚠️ $_error',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ElevatedButton(
              onPressed: _procesando ? null : _confirmar,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green[700],
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Text(_procesando ? 'Procesando...' : 'Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}
