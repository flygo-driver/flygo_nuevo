import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

class HistorialViajesTaxista extends StatefulWidget {
  const HistorialViajesTaxista({super.key});

  @override
  State<HistorialViajesTaxista> createState() => _HistorialViajesTaxistaState();
}

class _HistorialViajesTaxistaState extends State<HistorialViajesTaxista> {
  List<Viaje> historial = <Viaje>[];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  String _fmtFecha(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return "${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}";
  }

  double _calcularGanancia(Viaje v) {
    if (v.gananciaTaxista > 0) return v.gananciaTaxista;
    return PlataformaEconomia.gananciaTaxistaRdDesdeTotal(v.precio);
  }

  Color _getColorForTipo(BuildContext context, String tipo) {
    final b = Theme.of(context).brightness;
    switch (tipo) {
      case 'motor':
        return b == Brightness.dark ? Colors.orange : Colors.orange.shade800;
      case 'turismo':
        return b == Brightness.dark ? Colors.purpleAccent : Colors.deepPurple;
      default:
        return b == Brightness.dark
            ? const Color(0xFF69F0AE)
            : const Color(0xFF00796B);
    }
  }

  IconData _getIconForTipo(String tipo) {
    switch (tipo) {
      case 'motor':
        return Icons.motorcycle;
      case 'turismo':
        return Icons.beach_access;
      default:
        return Icons.directions_car;
    }
  }

  String _getLabelForTipo(String tipo) {
    switch (tipo) {
      case 'motor':
        return 'MOTOR';
      case 'turismo':
        return 'TURISMO';
      default:
        return 'NORMAL';
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() => historial = <Viaje>[]);
        }
        return;
      }

      final List<Viaje> datos = await ViajeData.obtenerHistorialTaxista(user.uid)
          .timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Tiempo de espera al cargar el historial. Revisá la conexión.',
        ),
      );

      if (!mounted) return;
      setState(() => historial = datos);
    } catch (e, st) {
      debugPrint('Error cargando historial: $e\n$st');
      if (mounted) {
        setState(() => historial = <Viaje>[]);
        final ScaffoldMessengerState? ms =
            ScaffoldMessenger.maybeOf(context);
        ms?.showSnackBar(
          SnackBar(
            content: Text('Error al cargar historial: $e'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () {
                setState(() => cargando = true);
                unawaited(_cargarHistorial());
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Historial de Viajes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: cargando
          ? Center(
              child: CircularProgressIndicator(color: cs.primary),
            )
          : historial.isEmpty
              ? RefreshIndicator(
                  onRefresh: _cargarHistorial,
                  color: cs.primary,
                  backgroundColor: cs.surface,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 56,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay viajes completados',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No encontramos viajes con tu cuenta como conductor '
                        '(uidTaxista) y completado. Cuando finalices un viaje, '
                        'aparecerá aquí.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarHistorial,
                  color: cs.primary,
                  backgroundColor: cs.surface,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: historial.length,
                    itemBuilder: (context, index) {
                      final v = historial[index];
                      final Color servicioColor =
                          _getColorForTipo(context, v.tipoServicio);
                      final IconData servicioIcon =
                          _getIconForTipo(v.tipoServicio);
                      final String servicioLabel =
                          _getLabelForTipo(v.tipoServicio);
                      final double ganancia = _calcularGanancia(v);

                      return Card(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: isDark ? 0.55 : 0.65,
                        ),
                        elevation: isDark ? 2 : 1,
                        shadowColor: cs.shadow.withValues(alpha: 0.2),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: servicioColor.withValues(alpha: 0.55),
                            width: 2,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => FacturaViaje.mostrar(
                            context,
                            viajeId: v.id,
                            role: 'taxista',
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          servicioColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      servicioIcon,
                                      color: servicioColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "${v.origen} → ${v.destino}",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          servicioColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: servicioColor),
                                    ),
                                    child: Text(
                                      servicioLabel,
                                      style: TextStyle(
                                        color: servicioColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (v.clienteId.isNotEmpty) ...[
                                Text(
                                  "Cliente: ${v.clienteId}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _fmtFecha(v.fechaHora),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Total",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        FormatosMoneda.rd(v.precio),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "Ganaste",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        FormatosMoneda.rd(ganancia),
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: servicioColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.receipt_long_rounded,
                                    color: servicioColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Ver comprobante del viaje',
                                    style: TextStyle(
                                      color: servicioColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (v.tipoServicio == 'turismo' &&
                                  v.extras != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        servicioColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          servicioColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 14,
                                        color: servicioColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          "Viaje turístico",
                                          style: TextStyle(
                                            color: servicioColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
