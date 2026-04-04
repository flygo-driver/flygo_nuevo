// lib/pantallas/shared/detalle_viaje.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../modelo/viaje.dart';
import '../../utils/formatos_moneda.dart';
import '../../utils/telefono_viaje.dart';
import '../../utils/calculos/estados.dart';
import '../chat/chat_screen.dart';
import 'boarding_pin_sheet.dart';

class DetalleViaje extends StatefulWidget {
  final String viajeId;
  const DetalleViaje({super.key, required this.viajeId});

  @override
  State<DetalleViaje> createState() => _DetalleViajeState();
}

class _DetalleViajeState extends State<DetalleViaje> {
  final DateFormat _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _launchPhone(String phone) async {
    final String tel = telefonoNormalizarDigitos(phone);
    if (tel.isEmpty) return;
    await telefonoLaunchUri(telefonoUriLlamada(tel));
  }

  Future<void> _launchWhatsApp(String phone) async {
    final String tel = telefonoNormalizarDigitos(phone);
    if (tel.isEmpty) return;
    const String mensaje = 'Hola, soy de RAI, respecto al viaje.';
    if (await telefonoLaunchUri(telefonoUriWhatsAppApp(tel, mensaje))) {
      return;
    }
    await telefonoLaunchUri(telefonoUriWhatsAppWeb(tel, mensaje));
  }

  Widget _infoRow(String label, String value, {Color valueColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color color = Colors.greenAccent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _buildUsuarioInfo(String uid, String rol) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
          );
        }
        final data = snap.data?.data() ?? {};
        final nombre = (data['nombre'] ?? '—').toString();
        final telefono = (data['telefono'] ?? '—').toString();
        final email = (data['email'] ?? '—').toString();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rol, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _infoRow('Nombre:', nombre),
              _infoRow('Teléfono:', telefono),
              _infoRow('Email:', email),
              if (telefono != '—')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.call, color: Colors.greenAccent),
                        onPressed: () => _launchPhone(telefono),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.chat, color: Colors.green),
                        onPressed: () => _launchWhatsApp(telefono),
                      ),
                      if (uid != FirebaseAuth.instance.currentUser?.uid)
                        IconButton(
                          icon: const Icon(Icons.message, color: Colors.blueAccent),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  otroUid: uid,
                                  otroNombre: nombre,
                                  viajeId: widget.viajeId,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaypoints(Viaje v) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍 Paradas intermedias', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...v.waypoints!.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final w = entry.value;
            final label = w['label'] ?? 'Parada $idx';
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.flag_circle, size: 16, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$idx. $label', style: const TextStyle(color: Colors.white70))),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildExtras(Viaje v) {
    if (v.extras == null || v.extras!.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (v.extras!['pasajeros'] != null) {
      chips.add(_chip('👥 ${v.extras!['pasajeros']} pasajero${v.extras!['pasajeros'] != 1 ? 's' : ''}'));
    }
    if (v.extras!['peaje'] != null) {
      chips.add(_chip('💰 Peaje: ${FormatosMoneda.rd(v.extras!['peaje'])}'));
    }
    // También podemos mostrar distancia si está en extras
    if (v.extras!['distanciaKm'] != null) {
      chips.add(_chip('📏 ${v.extras!['distanciaKm'].toStringAsFixed(2)} km'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(children: chips);
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('viajes').doc(widget.viajeId);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Detalle de viaje', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          }
          if (snap.hasError || !snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text('No se encontró el viaje', style: TextStyle(color: Colors.white70)),
            );
          }
          final v = Viaje.fromMap(snap.data!.id, snap.data!.data()!);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título con origen → destino
                Text(
                  '${v.origen} → ${v.destino}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${v.id.substring(0, 8)}...',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 16),

                // Estado y badge de tipo de servicio
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getEstadoColor(v.estado).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getEstadoColor(v.estado)),
                        ),
                        child: Text(
                          'Estado: ${_getEstadoLabel(v.estado)}',
                          style: TextStyle(color: _getEstadoColor(v.estado), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildServicioBadge(v),
                  ],
                ),
                const SizedBox(height: 16),

                // Información general
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _infoRow('Fecha:', _formatoFecha.format(v.fechaHora)),
                      _infoRow('Origen:', v.origen),
                      _infoRow('Destino:', v.destino),
                      // La distancia la obtenemos de extras si existe
                      if (v.extras != null && v.extras!['distanciaKm'] != null)
                        _infoRow('Distancia:', '${v.extras!['distanciaKm'].toStringAsFixed(2)} km'),
                      _infoRow('Precio:', FormatosMoneda.rd(v.precio), valueColor: Colors.greenAccent),
                      if (v.precioFinal > 0 && v.precioFinal != v.precio)
                        _infoRow('Precio final:', FormatosMoneda.rd(v.precioFinal), valueColor: Colors.greenAccent),
                      _infoRow('Comisión:', FormatosMoneda.rd(v.comision), valueColor: Colors.orangeAccent),
                      _infoRow('Ganancia taxista:', FormatosMoneda.rd(v.gananciaTaxista), valueColor: Colors.greenAccent),
                      _infoRow('Método de pago:', v.metodoPago),
                      _infoRow('Vehículo:', v.tipoVehiculo),
                      if (v.marca.isNotEmpty || v.modelo.isNotEmpty)
                        _infoRow('Marca/Modelo:', '${v.marca} ${v.modelo}'.trim()),
                      if (v.placa.isNotEmpty) _infoRow('Placa:', v.placa),
                      if (v.color.isNotEmpty) _infoRow('Color:', v.color),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Waypoints y extras
                if (v.waypoints != null && v.waypoints!.isNotEmpty) ...[
                  _buildWaypoints(v),
                  const SizedBox(height: 16),
                ],
                if (v.extras != null && v.extras!.isNotEmpty) ...[
                  const Text('Extras', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildExtras(v),
                  const SizedBox(height: 16),
                ],

                // Código de verificación
                if (v.codigoVerificacion != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          v.codigoVerificado ? Icons.verified : Icons.qr_code,
                          color: v.codigoVerificado ? Colors.greenAccent : Colors.purple,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Código de verificación',
                                style: TextStyle(
                                  color: v.codigoVerificado ? Colors.greenAccent : Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                v.codigoVerificado ? 'Verificado' : v.codigoVerificacion!,
                                style: TextStyle(
                                  color: v.codigoVerificado ? Colors.greenAccent : Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Cliente
                if (v.uidCliente.isNotEmpty) ...[
                  const Text('Cliente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  _buildUsuarioInfo(v.uidCliente, 'Cliente'),
                  const SizedBox(height: 16),
                ],

                // Taxista
                if (v.uidTaxista.isNotEmpty) ...[
                  const Text('Taxista', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  _buildUsuarioInfo(v.uidTaxista, 'Taxista'),
                  const SizedBox(height: 16),
                ],

                // Botón de PIN/Abordaje (si aplica)
                if (v.uidTaxista.isNotEmpty && v.estado == EstadosViaje.aBordo && !v.codigoVerificado)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => BoardingPinSheet(tripId: v.id),
                      ),
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Verificar código de abordaje'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    final e = EstadosViaje.normalizar(estado);
    if (e == EstadosViaje.completado) return Colors.green;
    if (e == EstadosViaje.cancelado) return Colors.red;
    if (e == EstadosViaje.enCurso) return Colors.blue;
    if (e == EstadosViaje.aceptado) return Colors.orange;
    if (e == EstadosViaje.pendiente) return Colors.yellow;
    return Colors.white70;
  }

  String _getEstadoLabel(String estado) {
    return EstadosViaje.normalizar(estado).toUpperCase();
  }

  Widget _buildServicioBadge(Viaje v) {
    Color color;
    IconData icon;
    String label;

    switch (v.tipoServicio) {
      case 'motor':
        color = Colors.orange;
        icon = Icons.motorcycle;
        label = 'MOTOR';
        break;
      case 'turismo':
        color = Colors.purple;
        icon = Icons.beach_access;
        label = 'TURISMO';
        break;
      default:
        color = Colors.greenAccent;
        icon = Icons.directions_car;
        label = 'NORMAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}