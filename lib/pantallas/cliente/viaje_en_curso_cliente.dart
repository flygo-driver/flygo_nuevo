// lib/pantallas/cliente/viaje_en_curso_cliente.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import '../../utils/mensajes.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';

class ViajeEnCursoCliente extends StatefulWidget {
  const ViajeEnCursoCliente({super.key});

  @override
  State<ViajeEnCursoCliente> createState() => _ViajeEnCursoClienteState();
}

class _ViajeEnCursoClienteState extends State<ViajeEnCursoCliente> {
  bool _cancelUiBusy = false; // evita doble tap/diálogo apilado

  Stream<Viaje?> _stream() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const Stream<Viaje?>.empty();
    return ViajesRepo.streamEstadoViajePorCliente(u.uid);
  }

  bool _coordsValid(double lat, double lon) {
    if (lat == 0 && lon == 0) return false;
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  // ------------------ Helpers Tel/WhatsApp ------------------
  String _cleanPhone(String raw) {
    final onlyDigits = raw.replaceAll(RegExp(r'\D+'), '');
    if (onlyDigits.isEmpty) return '';
    if (onlyDigits.startsWith('1')) return onlyDigits; // +1 RD
    if (onlyDigits.length == 10) return '1$onlyDigits';
    return onlyDigits;
  }

  // ----------------------- Ver taxista (EN TIEMPO REAL) -----------------------
  Future<void> _verTaxistaBottomSheet(String uidTaxista, {String? viajeId}) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uidTaxista)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: Colors.greenAccent),
                    ),
                  );
                }
                if (snap.hasError || !snap.hasData || !snap.data!.exists) {
                  return const Text(
                    'No se pudo cargar el taxista.',
                    style: TextStyle(color: Colors.white70),
                  );
                }

                final u = snap.data!.data() ?? {};
                final nombre   = (u['nombre'] ?? '—').toString().trim();
                final telefono = (u['telefono'] ?? '').toString().trim();
                final telLimpio = _cleanPhone(telefono);

                // Soporta ambas convenciones de campos
                final placa  = (u['placa'] ?? u['vehiculo']?['placa'] ?? '—').toString().trim();
                final marca  = (u['marca'] ?? u['vehiculoMarca'] ?? u['vehiculo']?['marca'] ?? '—').toString().trim();
                final modelo = (u['modelo'] ?? u['vehiculoModelo'] ?? u['vehiculo']?['modelo'] ?? '—').toString().trim();
                final color  = (u['color'] ?? u['vehiculoColor'] ?? u['vehiculo']?['color'] ?? '—').toString().trim();

                // Importante: usar SIEMPRE el mismo BuildContext (bc) tras awaits.
                final bc = context;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46, height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tu taxista',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Nombre: $nombre',   style: const TextStyle(color: Colors.white70)),
                    Text('Teléfono: ${telLimpio.isEmpty ? "—" : telefono}',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    const Text(
                      'Vehículo',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        _chipInfo('Placa', placa),
                        _chipInfo('Marca', marca),
                        _chipInfo('Modelo', modelo),
                        _chipInfo('Color', color),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (telLimpio.isEmpty)
                                ? null
                                : () async {
                                    try {
                                      final uri = Uri.parse('tel:$telLimpio');
                                      await launchUrl(uri, mode: LaunchMode.platformDefault);
                                    } catch (_) {
                                      if (!bc.mounted) return;
                                      MensajeUtils.mostrarError(bc, 'No se pudo abrir Teléfono.');
                                    }
                                  },
                            icon: const Icon(Icons.call, color: Colors.green),
                            label: const Text('Llamar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (telLimpio.isEmpty)
                                ? null
                                : () async {
                                    try {
                                      final msg = Uri.encodeComponent('Hola, soy tu pasajero de FlyGo.');
                                      final waApp = Uri.parse('whatsapp://send?phone=$telLimpio&text=$msg');
                                      if (await canLaunchUrl(waApp)) {
                                        await launchUrl(waApp, mode: LaunchMode.externalApplication);
                                      } else {
                                        final waWeb = Uri.parse('https://wa.me/$telLimpio?text=$msg');
                                        await launchUrl(waWeb, mode: LaunchMode.externalApplication);
                                      }
                                    } catch (_) {
                                      if (!bc.mounted) return;
                                      MensajeUtils.mostrarError(bc, 'No se pudo abrir WhatsApp.');
                                    }
                                  },
                            icon: const Icon(Icons.chat_bubble_outline, color: Colors.green),
                            label: const Text('WhatsApp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(bc).push(MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            otroUid: uidTaxista,
                            otroNombre: nombre.isEmpty ? 'Taxista' : nombre,
                            viajeId: viajeId,
                          ),
                        ));
                      },
                      icon: const Icon(Icons.chat),
                      label: const Text('Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _chipInfo(String titulo, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$titulo: ', style: const TextStyle(color: Colors.white54)),
          Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ----------------------- Cancelar/Rechazar -----------------------
  Future<void> _cancelarPorCliente(Viaje v) async {
    if (_cancelUiBusy) return;
    _cancelUiBusy = true;

    final uidCliente = FirebaseAuth.instance.currentUser?.uid;
    if (uidCliente == null) {
      _cancelUiBusy = false;
      return;
    }

    // limpia snackbars abiertos (evita dependientes colgados)
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    final motivoCtrl = TextEditingController(text: 'Vehículo no coincide');

    bool ok = false;
    try {
      ok = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.black,
              title: const Text('Cancelar viaje', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Cuéntanos el motivo (opcional):\n\n'
                    '• Solo puedes cancelar dentro de los primeros 10 minutos\n'
                    '• Y antes de que el viaje esté en curso',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: motivoCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Ej: Vehículo no coincide',
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.greenAccent, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                  ),
                  child: const Text('Sí, cancelar'),
                ),
              ],
            ),
          ) ?? false;
    } finally {
      // El controller se elimina *después* de cerrar el diálogo
      motivoCtrl.dispose();
    }

    if (!ok) {
      _cancelUiBusy = false;
      return;
    }

    try {
      await ViajesRepo.cancelarPorCliente(
        viajeId: v.id,
        uidCliente: uidCliente,
        motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      MensajeUtils.mostrarExito(context, 'Viaje cancelado.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      MensajeUtils.mostrarError(context, MensajeUtils.traducirErrorCancelacion(e));
    } finally {
      _cancelUiBusy = false;
    }
  }

  // ----------------------- Navegación a destino -----------------------
  Future<void> _abrirGoogleMapsDestino(double lat, double lon) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _abrirWazeDestino(double lat, double lon) async {
    final url = Uri.parse('https://waze.com/ul?ll=$lat,$lon&navigate=yes');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      await _abrirGoogleMapsDestino(lat, lon);
    }
  }

  Future<void> _selectorVerDestino(double lat, double lon) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(
                child: Container(
                  width: 44, height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Abrir destino en',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _abrirWazeDestino(lat, lon),
                icon: const Icon(Icons.directions_car),
                label: const Text('Waze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _abrirGoogleMapsDestino(lat, lon),
                icon: const Icon(Icons.map),
                label: const Text('Google Maps'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: const Text('Mi viaje en curso', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<Viaje?>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text('Error: ${snap.error}', style: const TextStyle(color: Colors.white70)),
            );
          }

          final v = snap.data;
          if (v == null) {
            return const Center(
              child: Text('No tienes viaje en curso.', style: TextStyle(color: Colors.white)),
            );
          }

          final fecha = formato.format(v.fechaHora);
          final total = FormatosMoneda.rd(v.precio);
          final estadoBase = EstadosViaje.normalizar(
            v.estado.isNotEmpty
                ? v.estado
                : (v.completado
                    ? EstadosViaje.completado
                    : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
          );

          final puedeCancelar =
              !EstadosViaje.esCompletado(estadoBase) && !EstadosViaje.esCancelado(estadoBase);

          final coordsOk = _coordsValid(v.latDestino, v.lonDestino);

          return RefreshIndicator(
            color: Colors.greenAccent,
            backgroundColor: Colors.black,
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🧭 ${v.origen} → ${v.destino}',
                          style: const TextStyle(
                              fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('🕓 Fecha: $fecha',
                          style: const TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Text('💰 Total: $total',
                          style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
                      const SizedBox(height: 8),
                      Text('📍 Estado: ${EstadosViaje.descripcion(estadoBase)}',
                          style: const TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Text(
                        '👤 Taxista: ${v.nombreTaxista.isNotEmpty ? v.nombreTaxista : 'Asignando...'}',
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: (v.uidTaxista.isEmpty)
                      ? null
                      : () => _verTaxistaBottomSheet(v.uidTaxista, viajeId: v.id),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Ver taxista'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),

                const SizedBox(height: 10),

                ElevatedButton.icon(
                  onPressed:
                      coordsOk ? () => _selectorVerDestino(v.latDestino, v.lonDestino) : null,
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Ver destino'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),

                const SizedBox(height: 10),

                if (puedeCancelar)
                  ElevatedButton.icon(
                    onPressed: _cancelUiBusy ? null : () => _cancelarPorCliente(v),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancelar / Rechazar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Este viaje ya no se puede cancelar.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
