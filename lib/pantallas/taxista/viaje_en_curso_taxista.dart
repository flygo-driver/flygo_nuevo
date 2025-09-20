import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';

// === LOGGING LIGERO ===
const bool kLog = true;
void logDbg(String msg) {
  if (kLog) debugPrint('[VIAJE_TX] $msg');
}

class ViajeEnCursoTaxista extends StatefulWidget {
  const ViajeEnCursoTaxista({super.key});
  @override
  State<ViajeEnCursoTaxista> createState() => _ViajeEnCursoTaxistaState();
}

class _ViajeEnCursoTaxistaState extends State<ViajeEnCursoTaxista> {
  GoogleMapController? _map;

  // GPS (tracking a Firestore)
  StreamSubscription<Position>? _gpsSub;
  String? _gpsParaViajeId;
  bool _gpsActivo = false;
  bool _myLoc = false; // controla myLocationEnabled
  bool _actionBusy = false;

  Stream<Viaje?> _stream() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const Stream<Viaje?>.empty();
    // Usa booleano 'activo' para simplificar y evitar índices compuestos
    return ViajesRepo.streamViajeEnCursoPorTaxista(u.uid);
  }

  void _mover(LatLng p) =>
      _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 15));

  bool _coordsValid(double lat, double lon) =>
      !(lat == 0 && lon == 0) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  String _cleanPhone(String raw) {
    final onlyDigits = raw.replaceAll(RegExp(r'\D+'), '');
    if (onlyDigits.isEmpty) return '';
    if (onlyDigits.startsWith('1')) return onlyDigits; // +1 RD
    if (onlyDigits.length == 10) return '1$onlyDigits';
    return onlyDigits;
  }

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
      logDbg('pos -> ${p.latitude},${p.longitude}');
      try {
        await ref.update({
          'latTaxista': p.latitude,
          'lonTaxista': p.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        logDbg('Firestore actualizado con posición actual');
      } catch (e) {
        logDbg('Error actualizando Firestore: $e');
      }
    });
  }

  void _stopGps() {
    logDbg('_stopGps() -> cancel stream, myLoc=false');
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActivo = false;
    _gpsParaViajeId = null;
    if (mounted) {
      setState(() => _myLoc = false);
    } else {
      _myLoc = false;
    }
  }

  Future<bool> _asegurarGps(String viajeId) async {
    logDbg('_asegurarGps() start (viajeId=$viajeId)');
    if (_gpsActivo && _gpsParaViajeId == viajeId) {
      logDbg('GPS ya activo para este viaje');
      return true;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    logDbg('Permiso actual: $perm');
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      logDbg('Permiso solicitado → $perm');
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permiso de ubicación requerido para navegar')),
      );
      return false;
    }

    if (mounted) setState(() => _myLoc = true);
    await _startGpsFor(viajeId);
    _gpsActivo = true;
    logDbg('_asegurarGps() OK → myLocation ON');
    return true;
  }

  Future<void> _afterPermissionUI() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _map?.dispose();
    _stopGps();
    super.dispose();
  }

  /* ===================== Navegación externa ===================== */
  Future<void> _abrirGoogleMapsDestino(double lat, double lon) async {
    logDbg('Abrir GoogleMaps destino: $lat,$lon');
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      final web = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lon');
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _abrirGoogleMapsDireccion(String direccion) async {
    logDbg('Abrir GoogleMaps búsqueda: "$direccion"');
    final q = Uri.encodeComponent(direccion);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _abrirWazeDestino(double lat, double lon) async {
    logDbg('Abrir Waze destino: $lat,$lon');
    final url = Uri.parse('https://waze.com/ul?ll=$lat,$lon&navigate=yes');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      await _abrirGoogleMapsDestino(lat, lon);
    }
  }

  Future<void> _abrirWazeBusqueda(String query) async {
    logDbg('Abrir Waze búsqueda: "$query"');
    final q = Uri.encodeComponent(query);
    final url = Uri.parse('https://waze.com/ul?q=$q&navigate=yes');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  ButtonStyle _btnAccion() => ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 52),
        textStyle:
            const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle _btnRojo() => ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        textStyle:
            const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  /* ===================== Acciones ===================== */
  Future<void> _marcarClienteAbordo(String viajeId) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }
    try {
      logDbg('BTN Cliente a bordo: viajeId=$viajeId');
      await ViajesRepo.marcarClienteAbordo(
          viajeId: viajeId, uidTaxista: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Cliente a bordo')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${errorAuthEs(e)}')),
      );
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
    if (uid == null) {
      _actionBusy = false;
      return;
    }
    try {
      logDbg(
          'BTN Iniciar viaje: viajeId=$viajeId, destino=($lat,$lon)');
      final okGps = await _asegurarGps(viajeId);
      if (!okGps) {
        _actionBusy = false;
        return;
      }
      await ViajesRepo.iniciarViaje(
          viajeId: viajeId, uidTaxista: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('▶ Viaje iniciado')),
      );

      await _afterPermissionUI();
      if (!mounted) return;

      final label = (destinoTexto == null || destinoTexto.trim().isEmpty)
          ? 'destino'
          : destinoTexto.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🧭 Navegando a destino: $label')),
      );

      await _selectorNavegacionDestino(lat, lon);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${errorAuthEs(e)}')),
      );
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _finalizarViaje(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Finalizar viaje',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                '¿Confirmas que el viaje terminó correctamente?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No',
                      style: TextStyle(color: Colors.white70))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sí, finalizar')),
            ],
          ),
        ) ??
        false;

    if (!ok) {
      _actionBusy = false;
      return;
    }

    try {
      logDbg('BTN Finalizar viaje: viajeId=${v.id}');
      await ViajesRepo.completarViajePorTaxista(
          viajeId: v.id, uidTaxista: uid);
      _stopGps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🏁 Viaje marcado como completado')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ViajeDisponible()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${errorAuthEs(e)}')),
      );
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _cancelarPorTaxista(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Cancelar viaje',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Esta acción cancelará tu aceptación y el viaje volverá a estar disponible.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No',
                      style: TextStyle(color: Colors.white70))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sí, cancelar')),
            ],
          ),
        ) ??
        false;

    if (!ok) {
      _actionBusy = false;
      return;
    }

    try {
      logDbg('BTN Cancelar viaje: viajeId=${v.id}');
      await ViajesRepo.cancelarPorTaxista(
          viajeId: v.id, uidTaxista: uid);
      _stopGps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('🚫 Cancelado. El viaje se republicó.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ViajeDisponible()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${errorAuthEs(e)}')),
      );
    } finally {
      _actionBusy = false;
    }
  }

  /* ===================== PERFIL CLIENTE + CONTACTO ===================== */
  Future<void> _verClienteBottomSheet({
    required String uidCliente,
    required String viajeId,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetCtx).viewPadding.bottom + 16,
            ),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uidCliente)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: Colors.greenAccent),
                    ),
                  );
                }
                if (snap.hasError ||
                    !snap.hasData ||
                    !snap.data!.exists) {
                  return const Text(
                    'No se pudo cargar el cliente.',
                    style: TextStyle(color: Colors.white70),
                  );
                }

                final u = snap.data!.data() ?? {};
                final nombre = (u['nombre'] ?? '—').toString().trim();
                final telefono = (u['telefono'] ?? '').toString().trim();
                final telOk = _cleanPhone(telefono).isNotEmpty;

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tu cliente',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Nombre: $nombre',
                          style:
                              const TextStyle(color: Colors.white70)),
                      Text(
                          'Teléfono: ${telefono.isEmpty ? '—' : telefono}',
                          style:
                              const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: !telOk
                                  ? null
                                  : () async {
                                      final tel = _cleanPhone(telefono);
                                      final uri = Uri.parse('tel:$tel');
                                      await launchUrl(uri,
                                          mode: LaunchMode
                                              .platformDefault);
                                    },
                              icon: const Icon(Icons.call,
                                  color: Colors.green),
                              label: const Text('Llamar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                minimumSize:
                                    const Size(double.infinity, 48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: !telOk
                                  ? null
                                  : () async {
                                      final tel = _cleanPhone(telefono);
                                      final msg = Uri.encodeComponent(
                                          'Hola, soy tu taxista de FlyGo.');
                                      final waApp = Uri.parse(
                                          'whatsapp://send?phone=$tel&text=$msg');
                                      if (await canLaunchUrl(waApp)) {
                                        await launchUrl(waApp);
                                      } else {
                                        final waWeb = Uri.parse(
                                            'https://wa.me/$tel?text=$msg');
                                        await launchUrl(waWeb,
                                            mode: LaunchMode
                                                .externalApplication);
                                      }
                                    },
                              icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  color: Colors.green),
                              label: const Text('WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                minimumSize:
                                    const Size(double.infinity, 48),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          if (!mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otroUid: uidCliente,
                                otroNombre:
                                    nombre.isEmpty ? 'Cliente' : nombre,
                                viajeId: viajeId,
                              ),
                            ),
                          );
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
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /* ===================== UI ===================== */
  Future<void> _selectorNavegacionDestino(double lat, double lon) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Abrir navegación',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _abrirWazeDestino(lat, lon),
                icon: const Icon(Icons.directions_car, color: Colors.green),
                label: const Text('Waze'),
                style: _btnAccion(),
              ),
              ElevatedButton.icon(
                onPressed: () => _abrirGoogleMapsDestino(lat, lon),
                icon: const Icon(Icons.map, color: Colors.green),
                label: const Text('Google Maps'),
                style: _btnAccion(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectorNavegacionPickup({
    required String origenTexto,
    required double latPickup,
    required double lonPickup,
  }) async {
    if (!mounted) return;
    final tieneCoords = _coordsValid(latPickup, lonPickup);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Ir a recoger al cliente',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => tieneCoords
                    ? _abrirWazeDestino(latPickup, lonPickup)
                    : _abrirWazeBusqueda(origenTexto),
                icon: const Icon(Icons.directions_car, color: Colors.green),
                label: const Text('Waze'),
                style: _btnAccion(),
              ),
              ElevatedButton.icon(
                onPressed: () => tieneCoords
                    ? _abrirGoogleMapsDestino(latPickup, lonPickup)
                    : _abrirGoogleMapsDireccion(origenTexto),
                icon: const Icon(Icons.map, color: Colors.green),
                label: const Text('Google Maps'),
                style: _btnAccion(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelEstado(String e) {
    final s = e.toLowerCase();
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.aBordo) return 'Cliente a bordo';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
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
        title: const Text('Mi viaje en curso',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [SaldoGananciasChip()],
      ),
      body: StreamBuilder<Viaje?>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(
                    color: Colors.greenAccent));
          }
          if (snap.hasError) {
            return Center(
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: Colors.white70)));
          }

          final v = snap.data;
          logDbg('Stream viaje en curso: ${v?.id ?? "NULL"}');

          if (v == null) {
            _stopGps();
            return const Center(
                child: Text('No tienes viaje en curso.',
                    style: TextStyle(color: Colors.white)));
          }

          final destino = LatLng(v.latDestino, v.lonDestino);
          final fecha = formato.format(v.fechaHora);
          final total = FormatosMoneda.rd(v.precio);

          final estadoBase = EstadosViaje.normalizar(
            v.estado.isNotEmpty
                ? v.estado
                : (v.completado
                    ? EstadosViaje.completado
                    : (v.aceptado
                        ? EstadosViaje.aceptado
                        : EstadosViaje.pendiente)),
          );

          final markers = <Marker>{
            Marker(
              markerId: const MarkerId('destino'),
              position: destino,
              infoWindow: InfoWindow(title: 'Destino: ${v.destino}'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
            ),
          };
          if (_coordsValid(v.latCliente, v.lonCliente)) {
            markers.add(
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(v.latCliente, v.lonCliente),
                infoWindow: InfoWindow(title: 'Recoger: ${v.origen}'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
              ),
            );
          }

          final initialTarget =
              EstadosViaje.esAceptado(estadoBase) &&
                      _coordsValid(v.latCliente, v.lonCliente)
                  ? LatLng(v.latCliente, v.lonCliente)
                  : destino;

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: initialTarget, zoom: 14),
                  onMapCreated: (c) {
                    _map = c;
                    _mover(initialTarget);
                  },
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
                            Text('🧭 ${v.origen} → ${v.destino}',
                                style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('🕓 Fecha: $fecha',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white70)),
                            const SizedBox(height: 8),
                            Text('💰 Total: $total',
                                style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.greenAccent)),
                            const SizedBox(height: 8),
                            Text('📍 Estado: ${_labelEstado(estadoBase)}',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._botonesPorPaso(v, estadoBase),
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

  List<Widget> _botonesPorPaso(Viaje v, String estadoBase) {
    if (EstadosViaje.esAceptado(estadoBase)) {
      return [
        ElevatedButton.icon(
          onPressed: (v.clienteId.isEmpty)
              ? null
              : () => _verClienteBottomSheet(
                    uidCliente: v.clienteId,
                    viajeId: v.id,
                  ),
          icon: const Icon(Icons.person_outline, color: Colors.green),
          label: const Text('Ver cliente'),
          style: _btnAccion(),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () async {
            logDbg(
                'BTN Buscar cliente: viajeId=${v.id}, origen="${v.origen}", lat=${v.latCliente}, lon=${v.lonCliente}');
            final okGps = await _asegurarGps(v.id);
            if (!okGps) return;

            await _afterPermissionUI();
            if (!mounted) return;

            final label = (v.origen.trim().isEmpty)
                ? 'punto de recogida'
                : v.origen.trim();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🧭 Navegando a: $label')),
            );

            await _selectorNavegacionPickup(
              origenTexto: v.origen,
              latPickup: v.latCliente,
              lonPickup: v.lonCliente,
            );
          },
          icon: const Icon(Icons.route, color: Colors.green),
          label: const Text('Buscar cliente'),
          style: _btnAccion(),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => _marcarClienteAbordo(v.id),
          icon: const Icon(Icons.emoji_people, color: Colors.green),
          label: const Text('Cliente a bordo'),
          style: _btnAccion(),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => _cancelarPorTaxista(v),
          icon: const Icon(Icons.cancel),
          label: const Text('Cancelar (emergencia)'),
          style: _btnRojo(),
        ),
      ];
    }

    if (EstadosViaje.esAbordo(estadoBase)) {
      return [
        ElevatedButton.icon(
          onPressed: () => _iniciarViaje(
            v.id,
            lat: v.latDestino,
            lon: v.lonDestino,
            destinoTexto: v.destino,
          ),
          icon: const Icon(Icons.play_arrow, color: Colors.green),
          label: const Text('Iniciar viaje'),
          style: _btnAccion(),
        ),
      ];
    }

    if (EstadosViaje.esEnCurso(estadoBase)) {
      return [
        ElevatedButton.icon(
          onPressed: v.completado ? null : () => _finalizarViaje(v),
          icon: const Icon(Icons.flag, color: Colors.green),
          label:
              Text(v.completado ? 'Viaje completado' : 'Finalizar viaje'),
          style: _btnAccion(),
        ),
      ];
    }

    return [const SizedBox.shrink()];
  }
}
