import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Misma experiencia que el ítem «Pagos» del drawer del cliente.
void showClienteMetodosPago(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final dcs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dcs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Métodos de Pago',
                style: TextStyle(
                  color: dcs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildPaymentOption(
                ctx,
                icon: Icons.money,
                title: 'Efectivo',
                subtitle: 'Paga en efectivo al conductor',
                isEnabled: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarHistorialPagos(context);
                },
              ),
              Divider(color: dcs.outlineVariant, height: 1),
              _buildPaymentOption(
                ctx,
                icon: Icons.credit_card,
                title: 'Tarjeta',
                subtitle: 'No disponible',
                isEnabled: false,
                onTap: null,
              ),
              Divider(color: dcs.outlineVariant, height: 1),
              _buildPaymentOption(
                ctx,
                icon: Icons.account_balance,
                title: 'Transferencia',
                subtitle: 'Paga por transferencia bancaria',
                isEnabled: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarInfoTransferencia(context);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: dcs.primary,
                    foregroundColor: dcs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _mostrarInfoTransferencia(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _TransferenciaBancariaSheet(),
  );
}

/// Datos bancarios del conductor (snapshot en viaje o perfil `usuarios`).
class _DatosBancariosConductor {
  const _DatosBancariosConductor({
    required this.banco,
    required this.cuenta,
    required this.titular,
    required this.tipoCuenta,
    required this.cedula,
  });

  final String banco;
  final String cuenta;
  final String titular;
  final String tipoCuenta;
  final String cedula;

  bool get completo =>
      banco.trim().isNotEmpty &&
      cuenta.trim().isNotEmpty &&
      titular.trim().isNotEmpty;
}

_DatosBancariosConductor? _bancariosDesdeViaje(Map<String, dynamic> v) {
  final banco = (v['bancoTaxista'] ?? v['bancoTaxistaSnapshot'] ?? '')
      .toString()
      .trim();
  final cuenta = (v['numeroCuentaTaxista'] ?? v['numeroCuentaTaxistaSnapshot'] ?? '')
      .toString()
      .trim();
  final tipo = (v['tipoCuentaTaxista'] ?? v['tipoCuentaTaxistaSnapshot'] ?? '')
      .toString()
      .trim();
  final titular = (v['titularCuentaTaxista'] ?? v['titularCuentaTaxistaSnapshot'] ?? '')
      .toString()
      .trim();
  final ci = (v['ciTaxista'] ?? v['cedulaTaxista'] ?? '').toString().trim();
  if (banco.isEmpty && cuenta.isEmpty && titular.isEmpty) return null;
  return _DatosBancariosConductor(
    banco: banco,
    cuenta: cuenta,
    titular: titular,
    tipoCuenta: tipo,
    cedula: ci,
  );
}

_DatosBancariosConductor _bancariosDesdeUsuario(Map<String, dynamic> u) {
  return _DatosBancariosConductor(
    banco: (u['banco'] ?? '').toString().trim(),
    cuenta: (u['numeroCuenta'] ?? '').toString().trim(),
    titular: (u['titularCuenta'] ?? u['titular'] ?? '').toString().trim(),
    tipoCuenta: (u['tipoCuenta'] ?? '').toString().trim(),
    cedula: (u['ciTaxista'] ?? u['cedula'] ?? u['cedulaTaxista'] ?? '')
        .toString()
        .trim(),
  );
}

class _TransferenciaBancariaSheet extends StatelessWidget {
  const _TransferenciaBancariaSheet();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final dcs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        if (uid.isEmpty) {
          return _scrollBody(
            scrollController: scrollController,
            dcs: dcs,
            children: [
              _handle(dcs),
              _titulo(dcs),
              _bannerInfo(
                dcs,
                icon: Icons.login,
                text: 'Iniciá sesión para ver los datos de transferencia de tu viaje.',
              ),
              _botonCerrar(context, dcs),
            ],
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .snapshots(),
          builder: (context, userSnap) {
            final viajeId =
                (userSnap.data?.data()?['viajeActivoId'] ?? '').toString().trim();

            if (viajeId.isEmpty) {
              return _scrollBody(
                scrollController: scrollController,
                dcs: dcs,
                children: [
                  _handle(dcs),
                  _titulo(dcs),
                  _bannerInfo(
                    dcs,
                    icon: Icons.info_outline,
                    text:
                        'Cuando programes un viaje y elijas «Transferencia», aquí verás la cuenta bancaria del conductor asignado para pagarle directamente.',
                  ),
                  const SizedBox(height: 8),
                  _bannerInfo(
                    dcs,
                    icon: Icons.lightbulb_outline,
                    color: dcs.tertiary,
                    text:
                        'Tip: durante el viaje también podés ver estos datos en la pantalla del trayecto y subir el comprobante desde ahí.',
                  ),
                  _botonCerrar(context, dcs),
                ],
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('viajes')
                  .doc(viajeId)
                  .snapshots(),
              builder: (context, viajeSnap) {
                if (viajeSnap.connectionState == ConnectionState.waiting &&
                    !viajeSnap.hasData) {
                  return _scrollBody(
                    scrollController: scrollController,
                    dcs: dcs,
                    children: [
                      _handle(dcs),
                      _titulo(dcs),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  );
                }

                final v = viajeSnap.data?.data() ?? {};
                final metodo = (v['metodoPago'] ?? '').toString();
                final esTransfer = MetodoPagoViaje.esTransferencia(metodo);
                final taxistaId = (v['uidTaxista'] ?? v['taxistaId'] ?? '')
                    .toString()
                    .trim();
                final precio = (v['precio'] is num)
                    ? (v['precio'] as num).toDouble()
                    : double.tryParse('${v['precio']}') ?? 0.0;
                final snapBanco = _bancariosDesdeViaje(v);

                if (!esTransfer) {
                  return _scrollBody(
                    scrollController: scrollController,
                    dcs: dcs,
                    children: [
                      _handle(dcs),
                      _titulo(dcs),
                      _bannerInfo(
                        dcs,
                        icon: Icons.payments_outlined,
                        text:
                            'Tu viaje activo está registrado como «${MetodoPagoViaje.etiquetaDocumento(metodo)}». '
                            'Los datos bancarios del conductor solo aplican cuando el método de pago es Transferencia.',
                      ),
                      _botonCerrar(context, dcs),
                    ],
                  );
                }

                if (snapBanco != null) {
                  return _scrollBody(
                    scrollController: scrollController,
                    dcs: dcs,
                    children: _contenidoConDatos(
                      context: context,
                      dcs: dcs,
                      datos: snapBanco,
                      montoRd: precio,
                      subtituloConductor:
                          'Conductor asignado a tu viaje en curso',
                    ),
                  );
                }

                if (taxistaId.isEmpty) {
                  return _scrollBody(
                    scrollController: scrollController,
                    dcs: dcs,
                    children: [
                      _handle(dcs),
                      _titulo(dcs),
                      _bannerInfo(
                        dcs,
                        icon: Icons.hourglass_empty,
                        color: Colors.orange,
                        text:
                            'Aún no hay conductor asignado. Cuando acepte el viaje, volvé a abrir esta pantalla para ver su cuenta.',
                      ),
                      _botonCerrar(context, dcs),
                    ],
                  );
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('usuarios')
                      .doc(taxistaId)
                      .snapshots(),
                  builder: (context, taxSnap) {
                    final datos = _bancariosDesdeUsuario(
                      taxSnap.data?.data() ?? {},
                    );
                    final nombreTaxista =
                        (taxSnap.data?.data()?['nombre'] ??
                                taxSnap.data?.data()?['displayName'] ??
                                'Conductor')
                            .toString()
                            .trim();

                    return _scrollBody(
                      scrollController: scrollController,
                      dcs: dcs,
                      children: datos.completo
                          ? _contenidoConDatos(
                              context: context,
                              dcs: dcs,
                              datos: datos,
                              montoRd: precio,
                              subtituloConductor: nombreTaxista.isNotEmpty
                                  ? 'Conductor: $nombreTaxista'
                                  : 'Conductor asignado',
                            )
                          : [
                              _handle(dcs),
                              _titulo(dcs),
                              _bannerInfo(
                                dcs,
                                icon: Icons.warning_amber_rounded,
                                color: Colors.orange,
                                text:
                                    'El conductor aún no completó banco, cuenta y titular en RAI. '
                                    'Coordiná el pago por chat o soporte hasta que cargue sus datos.',
                              ),
                              if (precio > 0) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Monto del viaje: ${FormatosMoneda.rd(precio)}',
                                  style: TextStyle(
                                    color: dcs.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                              _botonCerrar(context, dcs),
                            ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _scrollBody({
    required ScrollController scrollController,
    required ColorScheme dcs,
    required List<Widget> children,
  }) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: children,
    );
  }

  Widget _handle(ColorScheme dcs) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: dcs.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _titulo(ColorScheme dcs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        'Transferencia Bancaria',
        style: TextStyle(
          color: dcs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _bannerInfo(
    ColorScheme dcs, {
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final c = color ?? dcs.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: dcs.onSurface, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contenidoConDatos({
    required BuildContext context,
    required ColorScheme dcs,
    required _DatosBancariosConductor datos,
    required double montoRd,
    required String subtituloConductor,
  }) {
    return [
      _handle(dcs),
      _titulo(dcs),
      _bannerInfo(
        dcs,
        icon: Icons.info_outline,
        text:
            'Transferí el monto a la cuenta del conductor. Después subí el comprobante desde la pantalla del viaje en curso.',
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dcs.surfaceContainerHighest.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.8,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dcs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DATOS DEL CONDUCTOR',
              style: TextStyle(
                color: dcs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtituloConductor,
              style: TextStyle(color: dcs.onSurfaceVariant, fontSize: 13),
            ),
            if (montoRd > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Monto a transferir',
                style: TextStyle(color: dcs.onSurfaceVariant, fontSize: 12),
              ),
              Text(
                FormatosMoneda.rd(montoRd),
                style: TextStyle(
                  color: dcs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _buildInfoRow(context, dcs, 'Banco:', datos.banco),
            _buildInfoRow(
              context,
              dcs,
              'Cuenta:',
              datos.cuenta,
              copiable: true,
            ),
            if (datos.tipoCuenta.isNotEmpty)
              _buildInfoRow(context, dcs, 'Tipo:', datos.tipoCuenta),
            _buildInfoRow(context, dcs, 'Titular:', datos.titular),
            if (datos.cedula.isNotEmpty)
              _buildInfoRow(context, dcs, 'Cédula:', datos.cedula),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _botonCerrar(context, dcs),
    ];
  }

  Widget _botonCerrar(BuildContext context, ColorScheme dcs) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(
          backgroundColor: dcs.primary,
          foregroundColor: dcs.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: const Text('Cerrar'),
      ),
    );
  }
}

void _mostrarHistorialPagos(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) {
      final dcs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        backgroundColor: dcs.surfaceContainerHigh,
        title: Text(
          'Historial de Pagos',
          style: TextStyle(color: dcs.onSurface),
        ),
        content: Text(
          'Aquí podrás ver tu historial de pagos en efectivo.',
          style: TextStyle(color: dcs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cerrar', style: TextStyle(color: dcs.primary)),
          ),
        ],
      );
    },
  );
}

Widget _buildPaymentOption(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required bool isEnabled,
  required VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return ListTile(
    leading: Icon(
      icon,
      color:
          isEnabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.45),
    ),
    title: Text(
      title,
      style: TextStyle(
        color: isEnabled
            ? cs.onSurface
            : cs.onSurfaceVariant.withValues(alpha: 0.45),
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        color: isEnabled
            ? cs.onSurfaceVariant
            : cs.onSurfaceVariant.withValues(alpha: 0.45),
        fontSize: 12,
      ),
    ),
    trailing: isEnabled
        ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
        : Icon(Icons.block, color: cs.error, size: 16),
    onTap: isEnabled ? onTap : null,
  );
}

Widget _buildInfoRow(
  BuildContext context,
  ColorScheme cs,
  String label,
  String value, {
  bool copiable = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (copiable && value.trim().isNotEmpty)
          IconButton(
            tooltip: 'Copiar número de cuenta',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy, size: 20, color: cs.primary),
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
