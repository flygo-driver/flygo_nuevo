// lib/pantallas/taxista/viaje_en_curso_taxista.dart
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/data/pago_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';

const bool kLog = true;
void logDbg(String msg) { if (kLog) debugPrint('[VIAJE_TX] $msg'); }

class ViajeEnCursoTaxista extends StatefulWidget {
  const ViajeEnCursoTaxista({super.key});
  @override
  State<ViajeEnCursoTaxista> createState() => _ViajeEnCursoTaxistaState();
}

class _ViajeEnCursoTaxistaState extends State<ViajeEnCursoTaxista> {
  GoogleMapController? _map;

  // ===== GPS =====
  StreamSubscription<Position>? _gpsSub;
  String? _gpsParaViajeId;
  bool _gpsActivo = false;
  bool _myLoc = false;

  // ===== Acciones =====
  bool _actionBusy = false;

  // ===== Remoción / cancelación remota =====
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cancelSub;

  // ===== Stream principal =====
  Stream<Viaje?> _stream() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const Stream<Viaje?>.empty();
    return ViajesRepo.streamViajeEnCursoPorTaxista(u.uid);
  }

  // ===== Utilidades =====
  void _mover(LatLng p) => _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 15));

  bool _coordsValid(double lat, double lon) =>
      lat.isFinite && lon.isFinite &&
      !(lat == 0 && lon == 0) &&
      lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;

  String _cleanPhone(String raw) {
    final onlyDigits = raw.replaceAll(RegExp(r'\D+'), '');
    if (onlyDigits.isEmpty) return '';
    if (onlyDigits.startsWith('1')) return onlyDigits; // +1 RD
    if (onlyDigits.length == 10) return '1$onlyDigits';
    return onlyDigits;
  }

  String _uidClienteDe(Viaje v) {
    final a = (v.clienteId).toString().trim();
    if (a.isNotEmpty) return a;
    final b = (v.uidCliente).toString().trim();
    return b;
  }

  // ===== GPS control =====
  Future<void> _startGpsFor(String viajeId) async {
    logDbg('_startGpsFor($viajeId)');
    if (_gpsParaViajeId == viajeId && _gpsSub != null) return;
    await _gpsSub?.cancel();
    _gpsParaViajeId = viajeId;

    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8,
      ),
    ).listen((p) async {
      try {
        await ref.update({
          'latTaxista': p.latitude,
          'lonTaxista': p.longitude,
          'driverLat': p.latitude,
          'driverLon': p.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        logDbg('Error actualizando Firestore: $e');
      }
    });
  }

  void _stopGps({bool fromBuild = false}) {
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActivo = false;
    _gpsParaViajeId = null;
    if (fromBuild) {
      _myLoc = false;
    } else {
      if (mounted) {
        setState(() => _myLoc = false);
      } else {
        _myLoc = false;
      }
    }
  }

  Future<bool> _asegurarGps(String viajeId) async {
    if (_gpsActivo && _gpsParaViajeId == viajeId) {
      if (!_myLoc && mounted) setState(() => _myLoc = true);
      return true;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (!mounted) return false; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación requerido para navegar')),
      );
      return false;
    }

    if (mounted) setState(() => _myLoc = true);
    await _startGpsFor(viajeId);
    _gpsActivo = true;
    return true;
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    _map?.dispose();
    _stopGps();
    super.dispose();
  }

  /* ===================== Navegación externa ===================== */

  Future<bool> _tryLaunch(Uri uri, {bool preferExternalApp = true}) async {
    try {
      final ok1 = await launchUrl(
        uri,
        mode: preferExternalApp ? LaunchMode.externalApplication : LaunchMode.platformDefault,
      );
      if (ok1) return true;

      final ok2 = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (ok2) return true;

      if (uri.scheme.startsWith('http')) {
        final ok3 = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok3) return true;
      }
    } catch (e) {
      logDbg('launch fail: $e');
    }
    return false;
  }

  Future<void> _abrirGoogleMapsDestino(double lat, double lon) async {
    final googleIntent = Uri(
      scheme: 'google.navigation',
      queryParameters: {'q': '$lat,$lon', 'mode': 'd'},
    );
    final geoQuery = Uri.parse('geo:0,0?q=$lat,$lon');
    final googleWeb = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');

    if (await _tryLaunch(googleIntent)) return;
    if (await _tryLaunch(geoQuery)) return;
    await _tryLaunch(googleWeb, preferExternalApp: false);
  }

  Future<void> _abrirGoogleMapsDireccion(String direccion) async {
    final q = Uri.encodeComponent(direccion);
    final geoQuery = Uri.parse('geo:0,0?q=$q');
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');

    if (await _tryLaunch(geoQuery)) return;
    await _tryLaunch(web, preferExternalApp: false);
  }

  Future<void> _abrirWazeDestino(double lat, double lon) async {
    final wazeDeep = Uri.parse('waze://?ll=$lat,$lon&navigate=yes');
    final wazeWeb  = Uri.parse('https://waze.com/ul?ll=$lat,$lon&navigate=yes');

    if (await _tryLaunch(wazeDeep)) return;
    if (await _tryLaunch(wazeWeb, preferExternalApp: false)) return;

    await _abrirGoogleMapsDestino(lat, lon);
  }

  Future<void> _abrirWazeBusqueda(String query) async {
    final q = Uri.encodeComponent(query);
    final wazeDeep = Uri.parse('waze://?q=$q&navigate=yes');
    final wazeWeb  = Uri.parse('https://waze.com/ul?q=%s&navigate=yes'.replaceFirst('%s', q));

    if (await _tryLaunch(wazeDeep)) return;
    if (await _tryLaunch(wazeWeb, preferExternalApp: false)) return;

    await _abrirGoogleMapsDireccion(query);
  }

  /* ===================== Acciones ===================== */

  Future<void> _marcarClienteAbordo(String viajeId) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _actionBusy = false; return; }
    try {
      await ViajesRepo.marcarClienteAbordo(viajeId: viajeId, uidTaxista: uid);
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Cliente a bordo')));
    } catch (e) {
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _iniciarViaje(
    String viajeId, {
    required double lat,
    required double lon,
    String? destinoTexto,
  }) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _actionBusy = false; return; }
    try {
      final okGps = await _asegurarGps(viajeId);
      if (!okGps) { _actionBusy = false; return; }

      await ViajesRepo.iniciarViaje(viajeId: viajeId, uidTaxista: uid);
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('▶ Viaje iniciado')));

      final label = (destinoTexto == null || destinoTexto.trim().isEmpty) ? 'destino' : destinoTexto.trim();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🧭 Navegando a: $label')));

      await _selectorNavegacionDestino(lat, lon);
    } catch (e) {
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _finalizarViaje(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _actionBusy = false; return; }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Finalizar viaje', style: TextStyle(color: Colors.white)),
        content: const Text('¿Confirmas que el viaje terminó correctamente?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No', style: TextStyle(color: Colors.white70))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, finalizar')),
        ],
      ),
    ) ?? false;
    if (!ok) { _actionBusy = false; return; }

    try {
      await ViajesRepo.completarViajePorTaxista(viajeId: v.id, uidTaxista: uid);

      // registrar pago (tolerante)
      try {
        final doc = await FirebaseFirestore.instance.collection('viajes').doc(v.id).get();
        final data = doc.data() ?? {};
        double _toDouble(dynamic x) => x is num ? x.toDouble() : (double.tryParse('$x') ?? 0.0);

        final total = _toDouble(data['precioFinal'] ?? data['precio'] ?? v.precio);
        final comisionCampo = _toDouble(data['comision'] ?? data['comisionFlyGo']);
        final comision = comisionCampo > 0 ? comisionCampo : (total * 0.20);
        final gananciaCampo = _toDouble(data['gananciaTaxista']);
        final ganancia = gananciaCampo > 0 ? gananciaCampo : (total - comision);

        final metodo = (data['metodoPago'] ?? v.metodoPago ?? 'Efectivo').toString().toLowerCase();
        final uidTx = v.uidTaxista.isNotEmpty ? v.uidTaxista : uid;

        if (uidTx.isNotEmpty) {
          if (metodo == 'efectivo') {
            await PagoData.registrarComisionCash(viajeId: v.id, taxistaId: uidTx, comision: comision);
          } else {
            await PagoData.registrarTransferenciaCliente(
              viajeId: v.id, uidTaxista: uidTx, montoFinalDop: total, comision: comision, gananciaTaxista: ganancia,
            );
          }
        }
      } catch (_) {}

      _stopGps();
      if (!mounted) return; // guard de State.context

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🏁 Viaje marcado como completado')));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ViajeDisponible()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _cancelarPorTaxista(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _actionBusy = false; return; }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Cancelar viaje', style: TextStyle(color: Colors.white)),
        content: const Text('Esta acción cancelará tu aceptación y el viaje volverá a estar disponible.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No', style: TextStyle(color: Colors.white70))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    ) ?? false;

    if (!ok) { _actionBusy = false; return; }

    try {
      await ViajesRepo.cancelarPorTaxista(viajeId: v.id, uidTaxista: uid);
      _stopGps();
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚫 Cancelado. El viaje se republicó.')));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ViajeDisponible()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return; // guard de State.context
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _verClienteBottomSheet({required String uidCliente, required String viajeId}) async {
    if (!mounted) return; // guard de State.context
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          builder: (ctx, controller) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(sheetCtx).viewPadding.bottom + 16),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('usuarios').doc(uidCliente).snapshots(),
                builder: (ctx2, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Colors.greenAccent)));
                  }
                  if (snap.hasError || !snap.hasData || !snap.data!.exists) {
                    return const Text('No se pudo cargar el cliente.', style: TextStyle(color: Colors.white70));
                  }

                  final u = snap.data!.data() ?? {};
                  final nombre = (u['nombre'] ?? '—').toString().trim();
                  final telefono = (u['telefono'] ?? '').toString().trim();
                  final telOk = _cleanPhone(telefono).isNotEmpty;

                  return ListView(
                    controller: controller,
                    children: [
                      Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
                      const SizedBox(height: 12),
                      const Text('Tu cliente', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Nombre: $nombre', style: const TextStyle(color: Colors.white70)),
                      Text('Teléfono: ${telefono.isEmpty ? '—' : telefono}', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: !telOk ? null : () async {
                                final tel = _cleanPhone(telefono);
                                final uri = Uri.parse('tel:$tel');
                                await launchUrl(uri, mode: LaunchMode.platformDefault);
                              },
                              icon: const Icon(Icons.call, color: Colors.green),
                              label: const Text('Llamar'),
                              style: _styleBase(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: !telOk ? null : () async {
                                final tel = _cleanPhone(telefono);
                                final msg = Uri.encodeComponent('Hola, soy tu taxista de FlyGo.');
                                final waApp = Uri.parse('whatsapp://send?phone=%2B$tel&text=%20$msg');
                                if (await canLaunchUrl(waApp)) {
                                  await launchUrl(waApp);
                                } else {
                                  final waWeb = Uri.parse('https://wa.me/$tel?text=$msg');
                                  await launchUrl(waWeb, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.chat_bubble_outline, color: Colors.green),
                              label: const Text('WhatsApp'),
                              style: _styleBase(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          if (!sheetCtx.mounted) return; // guard del BuildContext local
                          Navigator.of(sheetCtx).push(MaterialPageRoute(
                            builder: (_) => ChatScreen(otroUid: uidCliente, otroNombre: nombre.isEmpty ? 'Cliente' : nombre, viajeId: viajeId),
                          ));
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('Chat'),
                        style: _styleBase(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectorNavegacionDestino(double lat, double lon) async {
    if (!mounted) return; // guard de State.context
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 8),
              const Text('Abrir navegación', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: () => _abrirWazeDestino(lat, lon), icon: const Icon(Icons.directions_car, color: Colors.green), label: const Text('Waze'), style: _styleBase()),
              ElevatedButton.icon(onPressed: () => _abrirGoogleMapsDestino(lat, lon), icon: const Icon(Icons.map, color: Colors.green), label: const Text('Google Maps'), style: _styleBase()),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectorNavegacionPickup({required String origenTexto, required double latPickup, required double lonPickup}) async {
    if (!mounted) return; // guard de State.context
    final tieneCoords = _coordsValid(latPickup, lonPickup);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 8),
              const Text('Ir a buscar al cliente', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: () => tieneCoords ? _abrirWazeDestino(latPickup, lonPickup) : _abrirWazeBusqueda(origenTexto), icon: const Icon(Icons.directions_car, color: Colors.green), label: const Text('Waze'), style: _styleBase()),
              ElevatedButton.icon(onPressed: () => tieneCoords ? _abrirGoogleMapsDestino(latPickup, lonPickup) : _abrirGoogleMapsDireccion(origenTexto), icon: const Icon(Icons.map, color: Colors.green), label: const Text('Google Maps'), style: _styleBase()),
            ],
          ),
        ),
      ),
    );
  }

  // ===== Tarjeta "tu vehículo (visible al cliente)" =====
  String _s(Object? x) => x?.toString() ?? '';
  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _tarjetaVehiculoVisibleAlCliente(Viaje v) {
    // Lee de viaje y hace fallback al perfil del taxista
    final taxistaId = (v.uidTaxista).toString().trim();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taxistaId.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance.collection('usuarios').doc(taxistaId).snapshots(),
      builder: (context, snap) {
        final tx = (snap.hasData && snap.data!.exists) ? (snap.data!.data() ?? const {}) : const {};

        final tipo   = _s(v.tipoVehiculo).trim().isNotEmpty ? _s(v.tipoVehiculo).trim() : _s(tx['tipoVehiculo']).trim();
        final marca  = _s((v as dynamic).marca).trim().isNotEmpty ? _s((v as dynamic).marca).trim()
                       : _s(tx['marca']).trim().isNotEmpty ? _s(tx['marca']).trim() : _s(tx['vehiculoMarca']).trim();
        final modelo = _s((v as dynamic).modelo).trim().isNotEmpty ? _s((v as dynamic).modelo).trim()
                       : _s(tx['modelo']).trim().isNotEmpty ? _s(tx['modelo']).trim() : _s(tx['vehiculoModelo']).trim();
        final color  = _s((v as dynamic).color).trim().isNotEmpty ? _s((v as dynamic).color).trim()
                       : _s(tx['color']).trim().isNotEmpty ? _s(tx['color']).trim() : _s(tx['vehiculoColor']).trim();
        final placa  = _s((v as dynamic).placa).trim().isNotEmpty ? _s((v as dynamic).placa).trim()
                       : _s(tx['placa']).trim();

        final linea = [
          if (tipo.isNotEmpty) tipo,
          if (marca.isNotEmpty) marca,
          if (modelo.isNotEmpty) modelo,
        ].join(' · ');

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu vehículo (visible al cliente)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(linea.isEmpty ? '—' : linea, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(children: [
                if (color.isNotEmpty) _chip('Color: $color'),
                if (placa.isNotEmpty) _chip('Placa: $placa'),
              ]),
            ],
          ),
        );
      },
    );
  }

  String _labelEstado(String e) {
    final s = EstadosViaje.normalizar(e);
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.enCaminoPickup) return 'Ir a buscar cliente';
    if (s == EstadosViaje.aBordo) return 'Cliente a bordo';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
  }

  // Listener robusto: cancelado, doc borrado o taxista removido ⇒ salir
  void _escucharCancelacionRemota(String viajeId) {
    _cancelSub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    _cancelSub = FirebaseFirestore.instance.collection('viajes').doc(viajeId).snapshots().listen((ds) async {
      if (!ds.exists) {
        _stopGps();
        if (!mounted) return; // guard de State.context
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El viaje ya no está disponible.')));
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const ViajeDisponible()), (route) => false);
        return;
      }

      final d = ds.data();
      if (d == null) return;

      final est = (d['estado'] ?? '').toString();
      final estN = EstadosViaje.normalizar(est);
      final taxistaId = (d['taxistaId'] ?? d['uidTaxista'] ?? '').toString();
      final teRemovieron = uid.isNotEmpty && (taxistaId.isEmpty || taxistaId != uid);

      if (estN == EstadosViaje.cancelado || teRemovieron) {
        _stopGps();
        if (uid.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
              'viajeActivoId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (_) {}
        }
        if (!mounted) return; // guard de State.context
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teRemovieron ? 'Fuiste removido del viaje.' : 'El cliente canceló el viaje.')));
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const ViajeDisponible()), (route) => false);
      }
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const TaxistaDrawer(),
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
        actions: const [SaldoGananciasChip()],
      ),
      body: StreamBuilder<Viaje?>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          }

          if (snap.hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return; // guard del BuildContext del builder
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Volviste a disponibles.')));
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ViajeDisponible()),
                (route) => false,
              );
            });
            return const SizedBox.shrink();
          }

          final v = snap.data;
          if (v == null) {
            _stopGps(fromBuild: true);
            _cancelSub?.cancel();

            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No tienes viaje en curso.', style: TextStyle(color: Colors.white)),
              ),
            );
          }

          _escucharCancelacionRemota(v.id);

          final destino = LatLng(v.latDestino, v.lonDestino);
          final fecha = formato.format(v.fechaHora);
          final total = FormatosMoneda.rd(v.precio);

          final estadoBase = EstadosViaje.normalizar(
            v.estado.isNotEmpty
                ? v.estado
                : (v.completado ? EstadosViaje.completado : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
          );

          if (estadoBase == EstadosViaje.cancelado) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              _stopGps();
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
                    'viajeActivoId': '',
                    'updatedAt': FieldValue.serverTimestamp(),
                    'actualizadoEn': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                } catch (_) {}
              }
              if (!context.mounted) return; // guard del BuildContext del builder
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ViajeDisponible()),
                (route) => false,
              );
            });
            return const SizedBox.shrink();
          }

          final markers = <Marker>{
            if (_coordsValid(v.latDestino, v.lonDestino))
              Marker(
                markerId: const MarkerId('destino'),
                position: destino,
                infoWindow: InfoWindow(title: 'Destino: ${v.destino}'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              ),
          };
          if (_coordsValid(v.latCliente, v.lonCliente)) {
            markers.add(
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(v.latCliente, v.lonCliente),
                infoWindow: InfoWindow(title: 'Recoger: ${v.origen}'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              ),
            );
          }

          final initialTarget =
              (EstadosViaje.esAceptado(estadoBase) || EstadosViaje.esEnCaminoPickup(estadoBase)) && _coordsValid(v.latCliente, v.lonCliente)
                  ? LatLng(v.latCliente, v.lonCliente)
                  : (_coordsValid(v.latDestino, v.lonDestino) ? destino : const LatLng(18.4861, -69.9312));

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
                  onMapCreated: (c) { _map = c; _mover(initialTarget); },
                  markers: markers,
                  myLocationEnabled: _myLoc,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ListView(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('🧭 ${v.origen} → ${v.destino}', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('🕓 Fecha: $fecha', style: const TextStyle(fontSize: 16, color: Colors.white70)),
                            const SizedBox(height: 8),
                            Text('💰 Total: $total', style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
                            const SizedBox(height: 8),
                            Text('📍 Estado: ${_labelEstado(estadoBase)}', style: const TextStyle(fontSize: 16, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _tarjetaVehiculoVisibleAlCliente(v),
                      const SizedBox(height: 16),
                      KeyedSubtree(key: ValueKey('acciones-taxista-${v.id}'), child: _actionBar(v, estadoBase)),
                      const SizedBox(height: 8),
                      _botonRescate(v.id),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Action bar adaptable por estado
  Widget _actionBar(Viaje v, String estadoBase) {
    final acciones = _botonesPorPaso(v, estadoBase);
    return Wrap(spacing: 10, runSpacing: 10, children: acciones);
  }

  /// Botones por paso
  List<Widget> _botonesPorPaso(Viaje v, String estadoBase) {
    final uidCli = _uidClienteDe(v);

    if (EstadosViaje.esAceptado(estadoBase)) {
      return [
        _btnPrimario(icon: const Icon(Icons.person_outline), label: const Text('Ver cliente'),
          onPressed: (uidCli.isEmpty) ? null : () => _verClienteBottomSheet(uidCliente: uidCli, viajeId: v.id)),
        _btnPrimario(icon: const Icon(Icons.route), label: const Text('Buscar cliente'), onPressed: () async {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) { try { await ViajesRepo.marcarEnCaminoPickup(viajeId: v.id, uidTaxista: uid); } catch (_) {} }
          final okGps = await _asegurarGps(v.id);
          if (!okGps) return;
          final label = (v.origen.trim().isEmpty) ? 'punto de recogida' : v.origen.trim();
          if (!mounted) return; // guard de State.context antes de SnackBar
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🧭 Navegando a: $label')));
          await _selectorNavegacionPickup(origenTexto: v.origen, latPickup: v.latCliente, lonPickup: v.lonCliente);
        }),
        _btnSecundario(icon: const Icon(Icons.emoji_people), label: const Text('Cliente a bordo'), onPressed: () => _marcarClienteAbordo(v.id)),
        _btnPeligro(icon: const Icon(Icons.cancel), label: const Text('Cancelar (emergencia)'), onPressed: () => _cancelarPorTaxista(v)),
      ];
    }

    if (EstadosViaje.esAbordo(estadoBase)) {
      return [
        _btnPrimario(icon: const Icon(Icons.play_arrow), label: const Text('Iniciar viaje'),
          onPressed: () => _iniciarViaje(v.id, lat: v.latDestino, lon: v.lonDestino, destinoTexto: v.destino)),
        _btnPeligro(icon: const Icon(Icons.cancel), label: const Text('Cancelar (emergencia)'), onPressed: () => _cancelarPorTaxista(v)),
      ];
    }

    if (EstadosViaje.esEnCurso(estadoBase)) {
      return [
        _btnPrimario(icon: const Icon(Icons.flag), label: Text(v.completado ? 'Viaje completado' : 'Finalizar viaje'),
          onPressed: v.completado ? null : () => _finalizarViaje(v)),
      ];
    }

    if (EstadosViaje.esEnCaminoPickup(estadoBase)) {
      return _botonesPorPaso(v, EstadosViaje.aceptado);
    }

    return const [SizedBox.shrink()];
  }

  Widget _botonRescate(String viajeId) {
    return TextButton.icon(
      onPressed: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        _stopGps();
        if (uid.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
              'viajeActivoId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (_) {}
        }
        if (!mounted) return; // guard de State.context
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ViajeDisponible()),
          (route) => false,
        );
      },
      icon: const Icon(Icons.exit_to_app, color: Colors.white70),
      label: const Text('Salir a disponibles (rescate)', style: TextStyle(color: Colors.white70)),
    );
  }

  // ===== Estilos =====
  ButtonStyle _styleBase() => ElevatedButton.styleFrom(
        backgroundColor: Colors.white, foregroundColor: Colors.black87,
        minimumSize: const Size(1, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle _stylePeligro() => ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
        minimumSize: const Size(1, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _btnPrimario({required Widget icon, required Widget label, required VoidCallback? onPressed}) =>
      ConstrainedBox(constraints: const BoxConstraints(minWidth: 160, maxWidth: 400),
        child: ElevatedButton.icon(onPressed: onPressed, icon: icon, label: label, style: _styleBase()));

  Widget _btnSecundario({required Widget icon, required Widget label, required VoidCallback? onPressed}) =>
      ConstrainedBox(constraints: const BoxConstraints(minWidth: 160, maxWidth: 400),
        child: OutlinedButton.icon(
          onPressed: onPressed, icon: icon, label: label,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white70),
            foregroundColor: Colors.white, minimumSize: const Size(1, 52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ));

  Widget _btnPeligro({required Widget icon, required Widget label, required VoidCallback? onPressed}) =>
      ConstrainedBox(constraints: const BoxConstraints(minWidth: 160, maxWidth: 400),
        child: ElevatedButton.icon(onPressed: onPressed, icon: icon, label: label, style: _stylePeligro()));
}
