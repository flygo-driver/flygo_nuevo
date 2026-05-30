import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Datos bancarios del conductor: snapshot en `viajes` (al finalizar) o perfil `usuarios`.
class DatosTransferenciaConductor {
  const DatosTransferenciaConductor({
    required this.banco,
    required this.cuenta,
    required this.tipoCuenta,
    required this.titular,
    required this.cedula,
  });

  final String banco;
  final String cuenta;
  final String tipoCuenta;
  final String titular;
  final String cedula;

  bool get completo =>
      banco.trim().isNotEmpty &&
      cuenta.trim().isNotEmpty &&
      titular.trim().isNotEmpty;

  static DatosTransferenciaConductor? desdeViaje(Map<String, dynamic> d) {
    final banco = (d['bancoTaxista'] ?? d['bancoTaxistaSnapshot'] ?? '')
        .toString()
        .trim();
    final cuenta = (d['numeroCuentaTaxista'] ?? d['numeroCuentaTaxistaSnapshot'] ?? '')
        .toString()
        .trim();
    final tipo = (d['tipoCuentaTaxista'] ?? d['tipoCuentaTaxistaSnapshot'] ?? '')
        .toString()
        .trim();
    final titular = (d['titularCuentaTaxista'] ?? d['titularCuentaTaxistaSnapshot'] ?? '')
        .toString()
        .trim();
    final ci = (d['ciTaxista'] ?? d['cedulaTaxista'] ?? '').toString().trim();
    if (banco.isEmpty && cuenta.isEmpty && titular.isEmpty) return null;
    return DatosTransferenciaConductor(
      banco: banco,
      cuenta: cuenta,
      tipoCuenta: tipo,
      titular: titular,
      cedula: ci,
    );
  }

  static DatosTransferenciaConductor desdeUsuario(Map<String, dynamic> u) {
    return DatosTransferenciaConductor(
      banco: (u['banco'] ?? '').toString().trim(),
      cuenta: (u['numeroCuenta'] ?? '').toString().trim(),
      tipoCuenta: (u['tipoCuenta'] ?? '').toString().trim(),
      titular: (u['titularCuenta'] ?? u['titular'] ?? '').toString().trim(),
      cedula: (u['ciTaxista'] ?? u['cedula'] ?? u['cedulaTaxista'] ?? '')
          .toString()
          .trim(),
    );
  }
}

/// Misma información que ve el taxista en la factura: banco, cuenta, titular, etc.
class DatosTransferenciaConductorPanel extends StatelessWidget {
  const DatosTransferenciaConductorPanel({
    super.key,
    required this.viajeData,
    required this.uidTaxista,
    required this.montoRd,
    this.titulo = 'DATOS PARA TRANSFERENCIA AL CONDUCTOR',
    this.fondoOscuro = false,
    this.footer,
  });

  final Map<String, dynamic> viajeData;
  final String uidTaxista;
  final double montoRd;
  final String titulo;
  final bool fondoOscuro;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final snap = DatosTransferenciaConductor.desdeViaje(viajeData);
    if (snap != null && snap.completo) {
      return _card(context, snap);
    }

    final uid = uidTaxista.trim();
    if (uid.isEmpty) {
      return _aviso(
        context,
        'Aún no hay conductor asignado en este viaje.',
        Colors.orange,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting && !s.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final datos = DatosTransferenciaConductor.desdeUsuario(s.data?.data() ?? {});
        if (datos.completo) {
          return _card(context, datos);
        }
        return _aviso(
          context,
          'El conductor no tiene datos bancarios completos en RAI (banco, cuenta y titular). '
          'Coordiná el pago por chat o soporte.',
          Colors.orange,
        );
      },
    );
  }

  Widget _aviso(BuildContext context, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fondoOscuro ? Colors.white70 : Theme.of(context).colorScheme.onSurface,
          height: 1.4,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, DatosTransferenciaConductor d) {
    final cs = Theme.of(context).colorScheme;
    final bg = fondoOscuro ? const Color(0xFF1A1A1A) : cs.surfaceContainerHighest;
    final border = fondoOscuro ? Colors.white12 : cs.outlineVariant;
    final titleColor = fondoOscuro ? Colors.greenAccent : cs.primary;
    final labelColor = fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final valueColor = fondoOscuro ? Colors.white : cs.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.4,
            ),
          ),
          if (montoRd > 0) ...[
            const SizedBox(height: 12),
            Text('Monto a transferir',
                style: TextStyle(color: labelColor, fontSize: 12)),
            Text(
              FormatosMoneda.rd(montoRd),
              style: TextStyle(
                color: valueColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _fila(context, 'Banco', d.banco, labelColor, valueColor),
          _fila(context, 'Cuenta', d.cuenta, labelColor, valueColor, copiar: true),
          if (d.tipoCuenta.isNotEmpty)
            _fila(context, 'Tipo de cuenta', d.tipoCuenta, labelColor, valueColor),
          _fila(context, 'Titular', d.titular, labelColor, valueColor),
          if (d.cedula.isNotEmpty)
            _fila(context, 'Cédula', d.cedula, labelColor, valueColor),
          const SizedBox(height: 8),
          Text(
            'Transferí a esta cuenta del conductor. Conservá el comprobante.',
            style: TextStyle(color: labelColor, fontSize: 12, height: 1.35),
          ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _fila(
    BuildContext context,
    String label,
    String value,
    Color labelColor,
    Color valueColor, {
    bool copiar = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copiar && value.trim().isNotEmpty)
            IconButton(
              tooltip: 'Copiar número de cuenta',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy, size: 20, color: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value.trim()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Número de cuenta copiado')),
                );
              },
            ),
        ],
      ),
    );
  }
}
