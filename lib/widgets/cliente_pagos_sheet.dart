import 'package:flutter/material.dart';

/// Misma experiencia que el ítem «Pagos» del drawer del cliente.
void showClienteMetodosPago(BuildContext context) {
  showModalBottomSheet(
    context: context,
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
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final dcs = Theme.of(ctx).colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        builder: (_, controller) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
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
                  'Transferencia Bancaria',
                  style: TextStyle(
                    color: dcs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: dcs.primaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: dcs.primary.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info, color: dcs.primary, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Cuando selecciones "Transferencia" como método de pago al programar un viaje, podrás ver los datos bancarios del conductor asignado para realizar el pago directamente.',
                        style: TextStyle(color: dcs.onPrimaryContainer),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: dcs.surfaceContainerHighest.withValues(
                      alpha: Theme.of(ctx).brightness == Brightness.dark
                          ? 0.55
                          : 0.75,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dcs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DATOS DEL CONDUCTOR (ejemplo)',
                        style: TextStyle(
                          color: dcs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(ctx, 'Banco:', 'Banco de Reservas'),
                      _buildInfoRow(ctx, 'Cuenta:', '960-123456-7'),
                      _buildInfoRow(ctx, 'Titular:', 'Carlos Rodríguez'),
                      _buildInfoRow(ctx, 'Cédula:', '001-2345678-9'),
                    ],
                  ),
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
          );
        },
      );
    },
  );
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

Widget _buildInfoRow(BuildContext context, String label, String value) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}
