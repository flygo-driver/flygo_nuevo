// lib/servicios/viajes_repo.dart
import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

class ViajesRepo {
  /// Minutos antes de la hora de recogida en que el viaje entra al pool (programados).
  static const int poolLeadMinutesProgramado = 180;

  static const bool _diagTripFlow =
      bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
  static void _diag(String msg) {
    if (_diagTripFlow) dev.log('[TRIP_FLOW][repo] $msg');
  }

  /// `pickup` y `now` deben ser comparables (misma referencia UTC recomendada).
  static DateTime poolOpensAtForScheduledPickup(DateTime pickup, DateTime now) {
    final DateTime t = pickup.subtract(
      const Duration(minutes: poolLeadMinutesProgramado),
    );
    return t.isBefore(now) ? now : t;
  }

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('viajes');
  static CollectionReference<Map<String, dynamic>> get _pagosCol => _db.collection('pagos');
  static const int _cancelWindowAfterAcceptMinutes = 3;

  static int _toCents(num v) => (v * 100).round();
  static double _fromCents(int c) => c / 100.0;
  static int _comision20Cents(int precioCents) => ((precioCents * 20) + 50) ~/ 100;

  static DateTime _dateFromAny(dynamic raw, {required DateTime fallback}) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? fallback;
    return fallback;
  }

  static bool _cancelDentroDeVentana(Map<String, dynamic> d, {required DateTime now}) {
    final String estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin') {
      return true;
    }
    if (!(estado == EstadosViaje.aceptado || estado == EstadosViaje.enCaminoPickup)) {
      return false;
    }
    final DateTime acceptedAt = _dateFromAny(
      d['aceptadoEn'] ?? d['updatedAt'] ?? d['actualizadoEn'] ?? d['createdAt'] ?? d['creadoEn'],
      fallback: now,
    );
    return now.difference(acceptedAt).inMinutes <= _cancelWindowAfterAcceptMinutes;
  }

  static Map<String, int> _partidasCents(Map<String, dynamic> data) {
    final dynamic pC = data['precio_cents'];
    final dynamic cC = data['comision_cents'];
    final dynamic gC = data['ganancia_cents'];
    if (pC is num && cC is num && gC is num && pC > 0) {
      return <String, int>{
        'precio_cents': pC.toInt(),
        'comision_cents': cC.toInt(),
        'ganancia_cents': gC.toInt(),
      };
    }
    final dynamic precioRaw = data['precioFinal'] ?? data['precio'] ?? data['total'];
    final int precioCents = _toCents((precioRaw is num) ? precioRaw : 0);
    final int comisionCents = _comision20Cents(precioCents);
    final int gananciaCents = precioCents - comisionCents;
    return <String, int>{
      'precio_cents': precioCents,
      'comision_cents': comisionCents,
      'ganancia_cents': gananciaCents,
    };
  }

  // ==============================================================
  //                           CREATE
  // ==============================================================
  static Future<String> crearViajePendiente({
    required String uidCliente,
    required String origen,
    required String destino,
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required DateTime fechaHora,
    required double precio,
    required String metodoPago,
    required String tipoVehiculo,
    required bool idaYVuelta,
    String? categoria,
    List<Map<String, dynamic>>? waypoints,
    Map<String, dynamic>? extras,
    double? distanciaKm,
    String? tipoServicio,
    String? subtipoTurismo,
    String? catalogoTurismoId,
    String? canalAsignacion,
    DateTime? publishAt,
    DateTime? acceptAfter,
    bool turismoIntentarAsignacionAutomatica = true,
  }) async {
    bool _outOfRange(double lat, double lon) =>
        !(lat.isFinite && lon.isFinite) ||
        lat < -90 || lat > 90 ||
        lon < -180 || lon > 180;

    if (_outOfRange(latOrigen, lonOrigen) || _outOfRange(latDestino, lonDestino)) {
      throw ArgumentError('Coordenadas fuera de rango');
    }
    if (!precio.isFinite || precio <= 0) {
      throw ArgumentError('Precio inválido');
    }

    final int precioCents = (precio * 100).round();
    final int comisionCents = (precioCents * 20) ~/ 100;
    final int gananciaCents = precioCents - comisionCents;

    final DateTime now = DateTime.now();
    final bool esAhora = fechaHora.isBefore(now.add(const Duration(minutes: 15)));

    // Viajes AHORA: pool y aceptación inmediatos.
    // Programados: pool y aceptación desde ~3h antes de la recogida (o ya si falta menos).
    final DateTime publishAtDT = publishAt ??
        (esAhora ? now : poolOpensAtForScheduledPickup(fechaHora, now));
    final DateTime acceptAfterDT =
        acceptAfter ?? (esAhora ? now : publishAtDT);
    final DateTime startWindowDT = esAhora ? now : fechaHora.subtract(const Duration(minutes: 45));

    List<Map<String, dynamic>>? _sanitize(List<Map<String, dynamic>>? wps) {
      if (wps == null) return null;
      final out = <Map<String, dynamic>>[];
      for (final w in wps) {
        final double? lat = (w['lat'] is num) ? (w['lat'] as num).toDouble() : null;
        final double? lon = (w['lon'] is num) ? (w['lon'] as num).toDouble() : null;
        if (lat == null || lon == null) continue;
        if (_outOfRange(lat, lon)) continue;
        out.add({'lat': lat, 'lon': lon, 'label': (w['label'] ?? '').toString()});
      }
      return out.isEmpty ? null : out;
    }

    final doc = _col.doc();
    final String codigoVerificacion = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    
    String tipoVehiculoFormateado = tipoVehiculo;
    if (tipoServicio == 'motor') {
      tipoVehiculoFormateado = '🛵 MOTOR 🛵';
    } else if (tipoServicio == 'turismo') {
      tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
    } else if (tipoServicio == 'normal') {
      tipoVehiculoFormateado = '🚗 NORMAL';
    }
    
    String estadoInicial;
    if (tipoServicio == 'turismo') {
      estadoInicial = 'pendiente_admin';
    } else {
      estadoInicial = (metodoPago.toLowerCase().trim() == 'tarjeta')
          ? EstadosViaje.pendientePago
          : EstadosViaje.pendiente;
    }
    
    final data = <String, dynamic>{
      'id': doc.id,
      'clienteId': uidCliente,
      'uidCliente': uidCliente,
      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'placa': '',
      'tipoVehiculo': tipoVehiculoFormateado,
      'tipoVehiculoOriginal': tipoVehiculo,
      'marca': '',
      'modelo': '',
      'color': '',
      'origen': origen,
      'destino': destino,
      'latCliente': latOrigen,
      'lonCliente': lonOrigen,
      'latOrigen': latOrigen,
      'lonOrigen': lonOrigen,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'sentido': idaYVuelta ? 'ida_y_vuelta' : 'solo_ida',
      'idaYVuelta': idaYVuelta,
      'fechaHora': Timestamp.fromDate(fechaHora),
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'publishAt': Timestamp.fromDate(publishAtDT),
      'startWindowAt': Timestamp.fromDate(startWindowDT),
      'programado': !esAhora,
      'esAhora': esAhora,
      if (!esAhora) 'poolOpeningPushSent': false,
      'metodoPago': metodoPago,
      'transferenciaConfirmada': false,
      'pagoATaxistaPendiente': false,
      'estado': estadoInicial,
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'codigoVerificacion': codigoVerificacion,
      'codigoVerificado': false,
      'activo': esAhora,
      'ignoradosPor': <String>[],
      'reservadoPor': '',
      'reservadoHasta': null,
      'precio': precioCents / 100.0,
      'comision': comisionCents / 100.0,
      'gananciaTaxista': gananciaCents / 100.0,
      'precio_cents': precioCents,
      'comision_cents': comisionCents,
      'ganancia_cents': gananciaCents,
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,
      if (tipoServicio != null && tipoServicio.isNotEmpty) 'tipoServicio': tipoServicio,
      if (subtipoTurismo != null && subtipoTurismo.isNotEmpty) 'subtipoTurismo': subtipoTurismo,
      if (catalogoTurismoId != null && catalogoTurismoId.isNotEmpty) 'catalogoTurismoId': catalogoTurismoId,
      if (canalAsignacion != null && canalAsignacion.isNotEmpty) 'canalAsignacion': canalAsignacion,
      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (distanciaKm != null && distanciaKm.isFinite && distanciaKm > 0) 'distanciaKm': distanciaKm,
      'creadoEn': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    final wps = _sanitize(waypoints);
    if (wps != null) {
      data['waypoints'] = wps;
      (extras ??= <String, dynamic>{})['paradas_count'] = wps.length;
    }
    if (extras != null && extras.isNotEmpty) data['extras'] = extras;

    await doc.set(data);

    await _db.collection('usuarios').doc(uidCliente).set({
      'viajeActivoId': doc.id,
      'siguienteViajeId': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (tipoServicio == 'turismo' && turismoIntentarAsignacionAutomatica) {
      try {
        final String? uidChofer =
            await AsignacionTurismoRepo.intentarAsignacionAutomatica(viajeId: doc.id);
        if (uidChofer != null && uidChofer.isNotEmpty) {
          await _limpiarOtrosActivosDelTaxista(uidChofer, exceptoId: doc.id);
          await _db.collection('usuarios').doc(uidChofer).set(
            {
              'siguienteViajeId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          await _ensureChatForTrip(doc.id);
        }
      } catch (e, st) {
        // Sin bloquear la creación del viaje; ADM puede asignar después.
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'crearViajePendiente(turismo auto-asignación)',
        );
      }
    }

    return doc.id;
  }

  /// Después de `claimTripWithReason` en un viaje del pool turístico, alinea `choferes_turismo` como en asignación ADM.
  static Future<void> sincronizarChoferTurismoTrasAceptarDesdePool({
    required String uidChofer,
    required String viajeId,
  }) async {
    await _db.collection('choferes_turismo').doc(uidChofer).set(
      {
        'disponible': false,
        'viajeActualId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> ensureTaxistaLibre(String uidTaxista) async {
    print('🟡 ensureTaxistaLibre - uid: $uidTaxista');
    try {
      final userDoc = await _db.collection('usuarios').doc(uidTaxista).get();
      final String viajeActivoId = (userDoc.data()?['viajeActivoId'] ?? '').toString();
      print('📄 ensureTaxistaLibre - viajeActivoId: $viajeActivoId');

      final hasActive = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('activo', isEqualTo: true)
          .limit(1)
          .get()
          .then((q) => q.docs.isNotEmpty);
      print('📄 ensureTaxistaLibre - hasActiveQuery: $hasActive');

      if (!hasActive) {
        await _db.collection('usuarios').doc(uidTaxista).set({
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      print('✅ ensureTaxistaLibre - OK');
    } catch (e) {
      print('❌ ensureTaxistaLibre error: $e');
      rethrow;
    }
  }

  static Future<void> ensureSiguienteCoherente(String uidTaxista) async {
    print('🟡 ensureSiguienteCoherente - uid: $uidTaxista');
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    try {
      final u = await uRef.get();
      final m = u.data() ?? {};
      final String nextId = (m['siguienteViajeId'] ?? '').toString();
      print('📄 ensureSiguienteCoherente - siguienteViajeId: $nextId');
      if (nextId.isEmpty) {
        print('✅ ensureSiguienteCoherente - OK (sin siguiente)');
        return;
      }

      final vRef = _col.doc(nextId);
      final v = await vRef.get();
      if (!v.exists) {
        await uRef.set({'siguienteViajeId': ''}, SetOptions(merge: true));
        print('✅ ensureSiguienteCoherente - limpiado (viaje no existe)');
        return;
      }
      final d = v.data()!;
      final String estado = (d['estado'] ?? '').toString();
      final String uidAsig = (d['uidTaxista'] ?? '').toString();
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = d['reservadoHasta'];
      final bool reservaVencida = reservadoHasta != null && reservadoHasta.compareTo(Timestamp.now()) <= 0;

      final ok = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin')
          && uidAsig.isEmpty && reservadoPor == uidTaxista && !reservaVencida;
      print('📄 ensureSiguienteCoherente - estado=$estado uidAsig=$uidAsig reservadoPor=$reservadoPor ok=$ok');

      if (!ok) {
        await _db.runTransaction((tx) async {
          tx.update(vRef, {
            'reservadoPor': '',
            'reservadoHasta': null,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp()
          });
          tx.set(uRef, {
            'siguienteViajeId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        });
      }
      print('✅ ensureSiguienteCoherente - OK');
    } catch (e) {
      print('❌ ensureSiguienteCoherente error: $e');
      rethrow;
    }
  }

  static Future<void> _ensureChatForTrip(String viajeId) async {
    final v = await _col.doc(viajeId).get();
    if (!v.exists) return;
    final d = v.data()!;
    final String uidCli = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();
    final String uidTx = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
    if (uidCli.isEmpty || uidTx.isEmpty) return;

    final cRef = _db.collection('chats').doc(viajeId);
    final c = await cRef.get();
    final payload = {
      'participantes': [uidCli, uidTx],
      'viajeId': viajeId,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
      'creadoAt': FieldValue.serverTimestamp(),
    };
    if (!c.exists) {
      await cRef.set(payload);
    }
  }

  /// Asegura `chats/{viajeId}` (participantes cliente/taxista). Usado por la pantalla de chat en viaje.
  static Future<void> ensureChatDocForViaje(String viajeId) =>
      _ensureChatForTrip(viajeId.trim());

  static Future<bool> claimTrip({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    final bool ok = await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final data = snap.data()!;

      final String estado = (data['estado'] ?? '').toString();
      final bool yaAsignado =
          ((data['uidTaxista'] ?? '') as String).isNotEmpty ||
          ((data['taxistaId'] ?? '') as String).isNotEmpty;
      final bool estadoPermitido =
          (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin');
      if (!estadoPermitido || yaAsignado) return false;

      final String reservadoPor = (data['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = data['reservadoHasta'];
      final bool reservaVigente =
          reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.compareTo(Timestamp.now()) > 0);
      if (reservaVigente && reservadoPor != uidTaxista) return false;

      final tsAcceptAfter = data['acceptAfter'];
      if (tsAcceptAfter is Timestamp) {
        final DateTime acceptAfter = tsAcceptAfter.toDate();
        if (DateTime.now().isBefore(acceptAfter)) return false;
      }

      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final bool bloqueadoPago = (uData['tienePagoPendiente'] == true);
      if (bloqueadoPago) return false;
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
      if (viajeActivoId.isNotEmpty) return false;

      final String _tel   = (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? '')).toString();
      final String _plac  = (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
      final String _tipo  = (tipoVehiculo.isNotEmpty ? tipoVehiculo : (uData['tipoVehiculo'] ?? '')).toString();
      final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      final String tipoServicio = data['tipoServicio'] ?? 'normal';
      String tipoVehiculoFormateado = _tipo;
      if (tipoServicio == 'motor') {
        tipoVehiculoFormateado = '🛵 MOTOR 🛵';
      } else if (tipoServicio == 'turismo') {
        tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
      } else if (tipoServicio == 'normal') {
        tipoVehiculoFormateado = '🚗 NORMAL';
      }

      tx.update(ref, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': tipoVehiculoFormateado,
        'tipoVehiculoOriginal': _tipo,
        'marca': _marca,
        'modelo': _modelo,
        'color': _color,
        'latTaxista': 0.0,
        'lonTaxista': 0.0,
        'driverLat': 0.0,
        'driverLon': 0.0,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ignoradosPor': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });

      tx.set(uRef, {
        'viajeActivoId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });

    if (ok) {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _db.collection('usuarios').doc(uidTaxista).set(
        {'siguienteViajeId': '', 'updatedAt': FieldValue.serverTimestamp(), 'actualizadoEn': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await _ensureChatForTrip(viajeId);
    }
    return ok;
  }

  static Future<String> claimTripWithReason({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    print('🟡 INICIO claimTripWithReason - viajeId: $viajeId, taxista: $uidTaxista');
    final vRef = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    try {
      await _db.runTransaction((tx) async {
        print('🟡 TX START claimTripWithReason');
        final vSnap = await tx.get(vRef);
        if (!vSnap.exists) {
          print('❌ Viaje no existe');
          throw 'no-existe';
        }
        final d = vSnap.data()!;
        print('📄 Data actual: estado=${d['estado']}, uidTaxista=${d['uidTaxista']}, taxistaId=${d['taxistaId']}');

        final String estado = (d['estado'] ?? '').toString();
        final bool estadoPermitido = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin');
        if (!estadoPermitido) {
          print('❌ Estado incorrecto: $estado');
          throw 'estado-no-pendiente';
        }

        final bool yaAsignado =
            ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
            ((d['taxistaId'] ?? '') as String).isNotEmpty;
        if (yaAsignado) {
          print('❌ Ya tiene taxista: uidTaxista=${d['uidTaxista']}, taxistaId=${d['taxistaId']}');
          throw 'ya-asignado';
        }

        final now = DateTime.now();
        final tsAA = d['acceptAfter'];
        if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) {
          print('❌ acceptAfter-futuro: ${tsAA.toDate().toIso8601String()} > ${now.toIso8601String()}');
          throw 'acceptAfter-futuro';
        }
        final tsPub = d['publishAt'];
        if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) {
          print('❌ publish-futuro: ${tsPub.toDate().toIso8601String()} > ${now.toIso8601String()}');
          throw 'publish-futuro';
        }

        final reservadoPor = (d['reservadoPor'] ?? '').toString();
        DateTime? reservadoHasta;
        final rh = d['reservadoHasta'];
        if (rh is Timestamp) reservadoHasta = rh.toDate();
        final reservaVigente = reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.isAfter(now));
        if (reservaVigente && reservadoPor != uidTaxista) {
          print('❌ Reservado por otro: reservadoPor=$reservadoPor, reservadoHasta=$reservadoHasta');
          throw 'reservado-otro';
        }

        final uSnap = await tx.get(uRef);
        final uData = uSnap.data() ?? const <String, dynamic>{};
        final bool bloqueadoPago = (uData['tienePagoPendiente'] == true);
        if (bloqueadoPago) {
          print('❌ Taxista bloqueado por pago semanal');
          throw 'bloqueado-pago-semanal';
        }
        final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
        if (viajeActivoId.isNotEmpty) {
          print('❌ Taxista ocupado con viajeActivoId=$viajeActivoId');
          throw 'taxista-ocupado';
        }

        final String _tel   = (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? '')).toString();
        final String _plac  = (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
        final String _tipo  = (tipoVehiculo.isNotEmpty ? tipoVehiculo : (uData['tipoVehiculo'] ?? '')).toString();
        final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
        final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
        final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

        final String tipoServicio = d['tipoServicio'] ?? 'normal';
        String tipoVehiculoFormateado = _tipo;
        if (tipoServicio == 'motor') {
          tipoVehiculoFormateado = '🛵 MOTOR 🛵';
        } else if (tipoServicio == 'turismo') {
          tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
        } else if (tipoServicio == 'normal') {
          tipoVehiculoFormateado = '🚗 NORMAL';
        }

        print('🟢 Intentando actualizar viaje...');
        tx.update(vRef, {
          'uidTaxista': uidTaxista,
          'taxistaId': uidTaxista,
          'nombreTaxista': nombreTaxista,
          'telefono': _tel,
          'placa': _plac,
          'tipoVehiculo': tipoVehiculoFormateado,
          'tipoVehiculoOriginal': _tipo,
          'marca': _marca,
          'modelo': _modelo,
          'color': _color,
          'latTaxista': 0.0,
          'lonTaxista': 0.0,
          'driverLat': 0.0,
          'driverLon': 0.0,
          'estado': EstadosViaje.aceptado,
          'aceptado': true,
          'rechazado': false,
          'activo': true,
          'aceptadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
          'reservadoPor': '',
          'reservadoHasta': null,
          'ignoradosPor': FieldValue.delete(),
        });

        tx.set(uRef, {
          'viajeActivoId': vRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print('✅ TX preparada correctamente (update viaje + set usuario)');
      });

      print('✅ Transacción completada');
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _db.collection('usuarios').doc(uidTaxista).set(
        {'siguienteViajeId': '', 'updatedAt': FieldValue.serverTimestamp(), 'actualizadoEn': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await _ensureChatForTrip(viajeId);
      print('✅ Post-proceso completado');

      return 'ok';
    } on FirebaseException catch (e) {
      print('❌ FirebaseException en claimTripWithReason: code=${e.code}, message=${e.message}');
      if (e.code == 'permission-denied') {
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('aceptarViajeSeguro');
          final idemKey =
              'accept_${viajeId}_${uidTaxista}_${DateTime.now().millisecondsSinceEpoch}';
          final resp = await callable.call(<String, dynamic>{
            'viajeId': viajeId,
            'nombreTaxista': nombreTaxista,
            'telefono': telefono,
            'placa': placa,
            'tipoVehiculo': tipoVehiculo,
            'idempotencyKey': idemKey,
          });
          final data = (resp.data is Map) ? Map<String, dynamic>.from(resp.data as Map) : <String, dynamic>{};
          final ok = data['ok'] == true;
          if (ok) {
            print('✅ aceptarViajeSeguro fallback OK');
            return 'ok';
          }
        } catch (cfErr) {
          print('❌ aceptarViajeSeguro fallback error: $cfErr');
        }
      }
      return 'permiso:${e.code}';
    } catch (e) {
      print('❌ ERROR GENERAL en claimTripWithReason: $e');
      return e.toString();
    }
  }

  static Future<void> reservarComoSiguiente({
    required String viajeId,
    required String uidTaxista,
    int ttlMin = 10,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;

      final String estado = (d['estado'] ?? '').toString();
      final String uidAsignado = (d['uidTaxista'] ?? '').toString();
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = d['reservadoHasta'];
      final bool reservaVigente =
          reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.compareTo(Timestamp.now()) > 0);

      final bool viajeLibre = uidAsignado.isEmpty;
      final bool estadoPermitido = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin');
      if (!estadoPermitido || !viajeLibre || (reservaVigente && reservadoPor != uidTaxista)) {
        throw StateError('El viaje no está disponible para reservar.');
      }

      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final bool bloqueadoPago = (uData['tienePagoPendiente'] == true);
      if (bloqueadoPago) {
        throw StateError('Debes saldar tu pago semanal para reservar viajes.');
      }
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
      if (viajeActivoId.isEmpty) {
        throw StateError('Primero debes tener un viaje activo para reservar el siguiente.');
      }

      final String siguienteViajeId = (uData['siguienteViajeId'] ?? '').toString();
      if (siguienteViajeId.isNotEmpty && siguienteViajeId != viajeId) {
        throw StateError('Ya tienes un viaje reservado en cola.');
      }

      final vence = Timestamp.fromDate(DateTime.now().add(Duration(minutes: ttlMin)));

      tx.update(ref, {
        'reservadoPor': uidTaxista,
        'reservadoHasta': vence,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      tx.set(uRef, {
        'siguienteViajeId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<void> liberarReserva({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      if (reservadoPor != uidTaxista) {
        throw StateError('No puedes liberar una reserva que no es tuya.');
      }

      tx.update(ref, {
        'reservadoPor': '',
        'reservadoHasta': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(uRef, {
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<String?> promoverReservaAlCompletar({
    required String uidTaxista,
  }) async {
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    return await _db.runTransaction((tx) async {
      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final bool bloqueadoPago = (uData['tienePagoPendiente'] == true);
      if (bloqueadoPago) return null;
      final String siguienteViajeId = (uData['siguienteViajeId'] ?? '').toString();
      if (siguienteViajeId.isEmpty) return null;

      final vRef = _col.doc(siguienteViajeId);
      final vSnap = await tx.get(vRef);
      if (!vSnap.exists) {
        tx.set(uRef, {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return null;
      }

      final v = vSnap.data()!;
      final String estado = (v['estado'] ?? '').toString();
      final String uidAsignado = (v['uidTaxista'] ?? '').toString();
      final String reservadoPor = (v['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = v['reservadoHasta'];
      final bool reservaVencida = reservadoHasta != null && reservadoHasta.compareTo(Timestamp.now()) <= 0;

      final tsAcceptAfter = v['acceptAfter'];
      if (tsAcceptAfter is Timestamp && DateTime.now().isBefore(tsAcceptAfter.toDate())) {
        return null;
      }

      final bool valido =
          (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago || estado == 'pendiente_admin') &&
          uidAsignado.isEmpty &&
          reservadoPor == uidTaxista &&
          !reservaVencida;

      if (!valido) {
        tx.update(vRef, {
          'reservadoPor': '',
          'reservadoHasta': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        tx.set(uRef, {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return null;
      }

      final String nombreTaxista = (uData['nombre'] ?? uData['displayName'] ?? '').toString();
      final String _tel   = (uData['telefono'] ?? '').toString();
      final String _plac  = (uData['placa'] ?? '').toString();
      final String _tipo  = (uData['tipoVehiculo'] ?? '').toString();
      final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      final String uidCliente = (v['uidCliente'] ?? v['clienteId'] ?? '').toString();

      final String tipoServicio = v['tipoServicio'] ?? 'normal';
      String tipoVehiculoFormateado = _tipo;
      if (tipoServicio == 'motor') {
        tipoVehiculoFormateado = '🛵 MOTOR 🛵';
      } else if (tipoServicio == 'turismo') {
        tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
      } else if (tipoServicio == 'normal') {
        tipoVehiculoFormateado = '🚗 NORMAL';
      }

      tx.update(vRef, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': tipoVehiculoFormateado,
        'tipoVehiculoOriginal': _tipo,
        'marca': _marca,
        'modelo': _modelo,
        'color': _color,
        'latTaxista': 0.0,
        'lonTaxista': 0.0,
        'driverLat': 0.0,
        'driverLon': 0.0,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
        'ignoradosPor': FieldValue.delete(),
      });

      if (uidCliente.isNotEmpty) {
        tx.set(_db.collection('usuarios').doc(uidCliente), {
          'viajeActivoId': siguienteViajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      tx.set(uRef, {
        'siguienteViajeId': '',
        'viajeActivoId': siguienteViajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return siguienteViajeId;
    });
  }

  /// Tras finalizar el viaje en curso: primero [siguienteViajeId] (reserva formal),
  /// si no aplica, intenta legado [viajeEncoladoId] con la misma asignación al taxista.
  static Future<String?> promoverColaTrasFinalizarTaxista({
    required String uidTaxista,
  }) async {
    final porReserva = await promoverReservaAlCompletar(uidTaxista: uidTaxista);
    if (porReserva != null) return porReserva;
    return _promoverViajeEncoladoLegacy(uidTaxista: uidTaxista);
  }

  static Future<String?> _promoverViajeEncoladoLegacy({
    required String uidTaxista,
  }) async {
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    return _db.runTransaction((tx) async {
      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final bool bloqueadoPago = (uData['tienePagoPendiente'] == true);
      if (bloqueadoPago) return null;
      final String encolado = (uData['viajeEncoladoId'] ?? '').toString();
      if (encolado.isEmpty) return null;

      final vRef = _col.doc(encolado);
      final vSnap = await tx.get(vRef);
      if (!vSnap.exists) {
        tx.set(
          uRef,
          {
            'viajeEncoladoId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return null;
      }

      final v = vSnap.data()!;
      final String estado = (v['estado'] ?? '').toString();
      final String uidAsignado = (v['uidTaxista'] ?? '').toString();
      final String reservadoPor = (v['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = v['reservadoHasta'];
      final bool reservaVencida =
          reservadoHasta != null && reservadoHasta.compareTo(Timestamp.now()) <= 0;

      final tsAcceptAfter = v['acceptAfter'];
      if (tsAcceptAfter is Timestamp && DateTime.now().isBefore(tsAcceptAfter.toDate())) {
        return null;
      }

      final bool cupoLibreOPropio =
          reservadoPor.isEmpty || reservadoPor == uidTaxista;

      final bool valido =
          (estado == EstadosViaje.pendiente ||
              estado == EstadosViaje.pendientePago ||
              estado == 'pendiente_admin') &&
          uidAsignado.isEmpty &&
          cupoLibreOPropio &&
          !reservaVencida;

      if (!valido) {
        tx.set(
          uRef,
          {
            'viajeEncoladoId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (reservadoPor == uidTaxista) {
          tx.update(vRef, {
            'reservadoPor': '',
            'reservadoHasta': null,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }
        return null;
      }

      final String nombreTaxista =
          (uData['nombre'] ?? uData['displayName'] ?? '').toString();
      final String tel = (uData['telefono'] ?? '').toString();
      final String plac = (uData['placa'] ?? '').toString();
      final String tipo = (uData['tipoVehiculo'] ?? '').toString();
      final String marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String modelo = (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      final String uidCliente = (v['uidCliente'] ?? v['clienteId'] ?? '').toString();

      final String tipoServicio = v['tipoServicio'] ?? 'normal';
      String tipoVehiculoFormateado = tipo;
      if (tipoServicio == 'motor') {
        tipoVehiculoFormateado = '🛵 MOTOR 🛵';
      } else if (tipoServicio == 'turismo') {
        tipoVehiculoFormateado = '🏝️ TURISMO 🏝️';
      } else if (tipoServicio == 'normal') {
        tipoVehiculoFormateado = '🚗 NORMAL';
      }

      tx.update(vRef, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': tel,
        'placa': plac,
        'tipoVehiculo': tipoVehiculoFormateado,
        'tipoVehiculoOriginal': tipo,
        'marca': marca,
        'modelo': modelo,
        'color': color,
        'latTaxista': 0.0,
        'lonTaxista': 0.0,
        'driverLat': 0.0,
        'driverLon': 0.0,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
        'ignoradosPor': FieldValue.delete(),
      });

      if (uidCliente.isNotEmpty) {
        tx.set(
          _db.collection('usuarios').doc(uidCliente),
          {
            'viajeActivoId': encolado,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      tx.set(
        uRef,
        {
          'viajeEncoladoId': FieldValue.delete(),
          'siguienteViajeId': '',
          'viajeActivoId': encolado,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return encolado;
    });
  }

  static Future<void> marcarEnCaminoPickup({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.enCaminoPickup)) {
        throw Exception('Estado inválido para en_camino_pickup');
      }
      tx.update(ref, {
        'estado': EstadosViaje.enCaminoPickup,
        'activo': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> marcarClienteAbordo({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.aBordo)) {
        throw Exception('Estado inválido para a_bordo');
      }
      final partidas = _partidasCents(d);
      tx.update(ref, {
        'estado': EstadosViaje.aBordo,
        'activo': true,
        'precio_cents': partidas['precio_cents'],
        'comision_cents': partidas['comision_cents'],
        'ganancia_cents': partidas['ganancia_cents'],
        'precio': _fromCents(partidas['precio_cents']!),
        'comision': _fromCents(partidas['comision_cents']!),
        'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
        'comisionCalculada': true,
        'comisionCalculadaEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
  }

  static Future<void> iniciarViaje({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.enCurso)) {
        throw Exception('Primero marca "Cliente a bordo".');
      }
      final bool esAhora = (d['esAhora'] == true);
      final tsStart = d['startWindowAt'];
      if (!esAhora && tsStart is Timestamp) {
        if (DateTime.now().isBefore(tsStart.toDate())) {
          throw Exception('Aún no está en ventana de inicio.');
        }
      }
      tx.update(ref, {
        'estado': EstadosViaje.enCurso,
        'activo': true,
        'inicioEnRutaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
  }

  static Future<void> completarViajePorTaxista({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    final billeRef = _db.collection('billeteras_taxista').doc(uidTaxista);
    final pagoViajeRef = _pagosCol.doc('viaje_${viajeId}_asiento');

    final String tipoServicioPre =
        ((await ref.get()).data()?['tipoServicio'] ?? '').toString();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      final n = EstadosViaje.normalizar(estado);
      if (n != EstadosViaje.enCurso) {
        throw Exception(
          'Solo puedes finalizar cuando el viaje está en curso. Verifica el código con el cliente para iniciar.',
        );
      }
      final partidas = _partidasCents(d);
      final int precioCents = partidas['precio_cents']!;
      final int comisionCents = partidas['comision_cents']!;
      final int gananciaCents = partidas['ganancia_cents']!;
      final String metodoRaw = (d['metodoPago'] ?? '').toString().toLowerCase().trim();
      final bool pagoRegistrado = (d['pagoRegistrado'] == true);

      final String uidCliente = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();

      if (!pagoRegistrado) {
        final bool esEfectivo = metodoRaw.contains('efectivo');
        final String metodoAsiento = esEfectivo ? 'efectivo' : (metodoRaw.contains('transfer') ? 'transferencia' : 'tarjeta');

        tx.update(ref, {
          'metodoPago': esEfectivo
              ? 'Efectivo'
              : (metodoRaw.contains('transfer') ? 'Transferencia' : 'Tarjeta'),
          'payment.status': esEfectivo ? 'cash_collected' : 'bank_transfer_received',
          'payment.provider': esEfectivo ? 'cash' : 'transfer',
          'payment.updatedAt': FieldValue.serverTimestamp(),
          'precio_cents': precioCents,
          'comision_cents': comisionCents,
          'ganancia_cents': gananciaCents,
          'precio': _fromCents(precioCents),
          'total': _fromCents(precioCents),
          'comision': _fromCents(comisionCents),
          'comisionFlygo': _fromCents(comisionCents),
          'gananciaTaxista': _fromCents(gananciaCents),
          'pagoRegistrado': true,
          'transferenciaConfirmada': esEfectivo ? true : false,
          'pagoATaxistaPendiente': false,
          'liquidado': false,
          'pagoDetalle': {
            'taxistaId': uidTaxista,
            'metodo': metodoAsiento,
            'total_cents': precioCents,
            'comision_cents': comisionCents,
            'ganancia_cents': gananciaCents,
            'createdAt': FieldValue.serverTimestamp(),
          },
          'settlement.commission': _fromCents(comisionCents),
          'settlement.driverAmount': _fromCents(gananciaCents),
          'settlement.status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        tx.set(
          billeRef,
          {
            if (esEfectivo)
              'comisionPendiente': FieldValue.increment(_fromCents(comisionCents)),
            'ultimoViajeId': viajeId,
            'ultimaComisionCents': comisionCents,
            'ultimaGananciaCents': gananciaCents,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (!(await tx.get(pagoViajeRef)).exists) {
          tx.set(pagoViajeRef, {
            'tipo': 'taxista',
            'viajeId': viajeId,
            'uidTaxista': uidTaxista,
            'monto': esEfectivo ? -_fromCents(comisionCents) : _fromCents(gananciaCents),
            'metodo': metodoAsiento,
            'estado': esEfectivo ? 'comision_pendiente' : 'por_liquidar',
            'fecha': DateTime.now().toIso8601String(),
            'provider': esEfectivo ? 'cash' : 'transfer',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(ref, {
        'estado': EstadosViaje.completado,
        'completado': true,
        'activo': false,
        'precio_cents': precioCents,
        'comision_cents': comisionCents,
        'ganancia_cents': gananciaCents,
        'precio': _fromCents(precioCents),
        'comision': _fromCents(comisionCents),
        'gananciaTaxista': _fromCents(gananciaCents),
        'comisionCalculada': true,
        'comisionCalculadaEn': FieldValue.serverTimestamp(),
        'finalizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(uRef, {
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (uidCliente.isNotEmpty) {
        tx.set(_db.collection('usuarios').doc(uidCliente), {
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista);

    if (tipoServicioPre == 'turismo') {
      try {
        await AsignacionTurismoRepo.liberarChofer(uidTaxista);
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'liberarChofer(turismo) tras completar',
        );
      }
    }
  }

  // ==============================================================
  //            ADMIN: TRANSFERENCIA CLIENTE -> RAI CONFIRMADA
  // ==============================================================
  static Future<void> confirmarTransferenciaCliente({
    required String viajeId,
  }) async {
    await _col.doc(viajeId).set({
      'transferenciaConfirmada': true,
      'pagoATaxistaPendiente': false,
      'pagoTaxistaPendiente': false,
      'estado': 'transferencia_validada',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> marcarTransferenciaReportadaCliente({
    required String viajeId,
    required String comprobanteUrl,
  }) async {
    await _col.doc(viajeId).set({
      'estado': 'pendiente_confirmacion',
      'comprobanteTransferenciaUrl': comprobanteUrl,
      'transferenciaConfirmada': false,
      'pagoATaxistaPendiente': false,
      'pagoTaxistaPendiente': false,
      'transferenciaReportadaEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> rechazarTransferenciaCliente({
    required String viajeId,
    required String motivo,
  }) async {
    await _col.doc(viajeId).set({
      'estado': 'transferencia_rechazada',
      'transferenciaConfirmada': false,
      'pagoATaxistaPendiente': false,
      'pagoTaxistaPendiente': false,
      'motivoRechazoTransferencia': motivo.trim(),
      'transferenciaRechazadaEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================================================
  //              ADMIN: RAI -> TAXISTA (PAGO EJECUTADO)
  // ==============================================================
  static Future<void> marcarPagoATaxistaRealizado({
    required String viajeId,
  }) async {
    await _col.doc(viajeId).set({
      'pagoATaxistaPendiente': false,
      'pagoTaxistaPendiente': false,
      'liquidado': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> cancelarPorTaxista({
    required String viajeId,
    required String uidTaxista,
    bool forzar = false,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    final String tipoServicioPre =
        ((await ref.get()).data()?['tipoServicio'] ?? '').toString();

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('El viaje no existe');

        final d = snap.data()!;
        final String uidTxDoc = ((d['uidTaxista'] ?? '').toString().trim().isNotEmpty)
            ? (d['uidTaxista'] ?? '').toString().trim()
            : (d['taxistaId'] ?? '').toString().trim();
        if (uidTxDoc != uidTaxista) throw Exception('No autorizado');
        final String estado = (d['estado'] ?? '').toString();
        final estNorm = EstadosViaje.normalizar(estado);
        if (!forzar) {
          if (!(estNorm == EstadosViaje.aceptado || estNorm == EstadosViaje.enCaminoPickup)) {
            throw Exception('No se puede cancelar en este estado.');
          }
        }

        DateTime fh;
        final ts = d['fechaHora'];
        if (ts is Timestamp) {
          fh = ts.toDate();
        } else if (ts is DateTime) {
          fh = ts;
        } else if (ts is String) {
          fh = DateTime.tryParse(ts) ?? DateTime.now();
        } else {
          fh = DateTime.now();
        }
        final bool esAhora = !fh.isAfter(DateTime.now().add(const Duration(minutes: 10)));

        tx.update(ref, {
          'estado': forzar ? EstadosViaje.cancelado : EstadosViaje.pendiente,
          'aceptado': false,
          'rechazado': false,
          'activo': false,
          'uidTaxista': '',
          'taxistaId': '',
          'nombreTaxista': '',
          'telefono': '',
          'placa': '',
          'marca': '',
          'modelo': '',
          'color': '',
          'republicado': !forzar,
          'canceladoPor': forzar ? 'taxista_forzado' : 'taxista',
          'canceladoTaxistaEn': FieldValue.serverTimestamp(),
          'esAhora': esAhora,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
          'pickupConfirmadoEn': FieldValue.delete(),
          'inicioEnRutaEn': FieldValue.delete(),
          'finalizadoEn': FieldValue.delete(),
          'ignoradosPor': FieldValue.arrayUnion([uidTaxista]),
          'reservadoPor': '',
          'reservadoHasta': null,
        });

        tx.set(uRef, {
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('cancelarViajeTaxistaSeguro');
        final idemKey =
            'cancel_${viajeId}_${uidTaxista}_${DateTime.now().millisecondsSinceEpoch}';
        await callable.call(<String, dynamic>{
          'viajeId': viajeId,
          'idempotencyKey': idemKey,
        });
      } else {
        rethrow;
      }
    }

    await _limpiarOtrosActivosDelTaxista(uidTaxista);

    if (tipoServicioPre == 'turismo') {
      try {
        await AsignacionTurismoRepo.liberarChofer(uidTaxista);
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'liberarChofer(turismo) tras cancelar (taxista)',
        );
      }
    }
  }

  static Future<void> cancelarPorCliente({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final ref = _col.doc(viajeId);
    String uidTaxistaAfter = '';
    String tipoServicioPre = '';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String cliente = (d['uidCliente'] ?? d['clienteId']).toString();
      if (cliente != uidCliente) throw Exception('No autorizado');

      final String estado = (d['estado'] ?? '').toString();
      final n = EstadosViaje.normalizar(estado);
      if (n == EstadosViaje.completado || n == EstadosViaje.cancelado) {
        throw Exception('El viaje ya está cerrado.');
      }
      // Cliente: permitir cancelación en cualquier estado no terminal para evitar
      // viajes atascados cuando el flujo operativo no avanza.
      final bool cancelablePorCliente =
          n == EstadosViaje.pendiente ||
          n == EstadosViaje.pendientePago ||
          n == 'pendiente_admin' ||
          n == EstadosViaje.aceptado ||
          n == EstadosViaje.enCaminoPickup ||
          n == EstadosViaje.aBordo ||
          n == EstadosViaje.enCurso;
      if (!cancelablePorCliente) {
        throw Exception('No se puede cancelar en este estado.');
      }

      uidTaxistaAfter = (d['uidTaxista'] ?? '').toString();
      tipoServicioPre = (d['tipoServicio'] ?? '').toString();

      tx.update(ref, {
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'canceladoPor': 'cliente',
        'motivoCancelacion': (motivo ?? '').trim(),
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(_db.collection('usuarios').doc(uidCliente), {
        'viajeActivoId': '',
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (uidTaxistaAfter.isNotEmpty) {
      try {
        await _db.collection('usuarios').doc(uidTaxistaAfter).set({
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'cancelarPorCliente: limpiar viajeActivoId del taxista',
        );
      }

      // Misma limpieza defensiva que cancelarPorTaxista:
      // evitamos inconsistencias si existieran múltiples `activo:true` legacy.
      await _limpiarOtrosActivosDelTaxista(uidTaxistaAfter);
    }

    if (tipoServicioPre == 'turismo' && uidTaxistaAfter.isNotEmpty) {
      try {
        await AsignacionTurismoRepo.liberarChofer(uidTaxistaAfter);
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'liberarChofer(turismo) tras cancelar (cliente)',
        );
      }
    }
  }

  static Future<void> pingGps({
    required String viajeId,
    required String uidTaxista,
    double? lat,
    double? lon,
    double? driverLat,
    double? driverLon,
  }) async {
    final ref = _col.doc(viajeId);
    final payload = <String, dynamic>{
      if (lat != null && lon != null) 'latTaxista': lat,
      if (lat != null && lon != null) 'lonTaxista': lon,
      if (driverLat != null && driverLon != null) 'driverLat': driverLat,
      if (driverLat != null && driverLon != null) 'driverLon': driverLon,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    await _db.runTransaction((tx) async {
      final s = await tx.get(ref);
      if (!s.exists) throw Exception('No existe el viaje');
      final m = s.data()!;
      if ((m['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      tx.update(ref, payload);
    });
  }

  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    final userRef = _db.collection('usuarios').doc(uidCliente);
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? viajeDocSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? viajeQuerySub;

    String? lastViajeId;
    bool usingDoc = false;

    Future<void> cancelAll() async {
      await viajeDocSub?.cancel();
      await viajeQuerySub?.cancel();
      viajeDocSub = null;
      viajeQuerySub = null;
      usingDoc = false;
    }

    late final StreamController<Viaje?> controller;
    controller = StreamController<Viaje?>.broadcast(
      onCancel: () async {
        await userSub?.cancel();
        await cancelAll();
        await controller.close();
      },
    );
    // Emisión inicial para evitar estados de "loading" infinito en la UI.
    controller.add(null);

    Future<void> setFromViajeActivoId(String? viajeActivoId) async {
      final id = (viajeActivoId ?? '').toString().trim();
      _diag('cliente stream setFromViajeActivoId id="$id"');
      if (id.isEmpty) {
        await cancelAll();
        lastViajeId = null;
        viajeQuerySub = _col
            .where('uidCliente', isEqualTo: uidCliente)
            .where('estado', whereIn: [
              EstadosViaje.pendiente,
              'buscando',
              EstadosViaje.pendientePago,
              'pendiente_admin',
              'asignado',
              EstadosViaje.aceptado,
              'en_camino',
              EstadosViaje.enCaminoPickup,
              'en_camino_pickup',
              EstadosViaje.aBordo,
              EstadosViaje.enCurso,
            ])
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .snapshots()
            .listen(
          (q) {
            if (q.docs.isEmpty) {
              controller.add(null);
              return;
            }
            controller.add(Viaje.fromMap(q.docs.first.id, q.docs.first.data()));
          },
          onError: controller.addError,
        );
        return;
      }

      if (usingDoc && lastViajeId == id) return;
      await cancelAll();
      lastViajeId = id;
      usingDoc = true;

      viajeDocSub = _db.collection('viajes').doc(id).snapshots().listen(
        (vSnap) {
          if (!vSnap.exists) {
            controller.add(null);
            return;
          }
          final data = vSnap.data();
          if (data == null) {
            controller.add(null);
            return;
          }
          final String uidCliDoc = (data['uidCliente'] ?? data['clienteId'] ?? '').toString();
          final String estado = EstadosViaje.normalizar((data['estado'] ?? '').toString());
          final bool visible = estado == EstadosViaje.pendiente ||
              estado == EstadosViaje.pendientePago ||
              estado == 'pendiente_admin' ||
              estado == EstadosViaje.aceptado ||
              estado == EstadosViaje.enCaminoPickup ||
              estado == EstadosViaje.aBordo ||
              estado == EstadosViaje.enCurso;
          if (uidCliDoc != uidCliente || !visible) {
            _diag('cliente stream hide doc=$id uidDoc=$uidCliDoc visible=$visible');
            controller.add(null);
            return;
          }
          _diag('cliente stream emit doc=$id');
          controller.add(Viaje.fromMap(vSnap.id, data));
        },
        onError: controller.addError,
      );
    }

    userSub = userRef.snapshots().listen(
      (uSnap) async {
        final u = uSnap.data() ?? <String, dynamic>{};
        await setFromViajeActivoId(u['viajeActivoId']);
      },
      onError: (_, __) {
        // Error transitorio de red/índice: degradar a "sin viaje" para UX estable.
        controller.add(null);
      },
    );

    return controller.stream;
  }

  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    // Fuente de verdad:
    // - En flows "correctos" el taxista guarda el viaje actual en `usuarios/{uid}.viajeActivoId`.
    // - Evita el problema de ambigüedad de `where(uidTaxista)+where(activo:true)+limit(1)`
    //   cuando existan 2 viajes activos por carreras/legacy.
    //
    // Fallback:
    // - Si `viajeActivoId` está vacío, conservamos el comportamiento legacy con la query ambigua,
    //   para no romper usuarios/instancias antiguas.
    final userRef = _db.collection('usuarios').doc(uidTaxista);

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? viajeDocSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? viajeQuerySub;

    String? lastViajeId;
    bool usingDoc = false;

    Future<void> cancelAll() async {
      await viajeDocSub?.cancel();
      await viajeQuerySub?.cancel();
      viajeDocSub = null;
      viajeQuerySub = null;
      usingDoc = false;
    }

    late final StreamController<Viaje?> controller;
    controller = StreamController<Viaje?>.broadcast(
      onCancel: () async {
        await userSub?.cancel();
        await cancelAll();
        await controller.close();
      },
    );
    // Emisión inicial para evitar estados de "loading" infinito en la UI.
    controller.add(null);

    Future<void> setFromViajeActivoId(String? viajeActivoId) async {
      final id = (viajeActivoId ?? '').toString().trim();
      _diag('taxista stream setFromViajeActivoId id="$id"');
      if (id.isEmpty) {
        // Fallback legacy
        await cancelAll();
        lastViajeId = null;
        viajeQuerySub = _col
            .where('uidTaxista', isEqualTo: uidTaxista)
            .where('activo', isEqualTo: true)
            .limit(1)
            .snapshots()
            .listen(
          (q) {
            if (q.docs.isEmpty) {
              controller.add(null);
              return;
            }
            final doc = q.docs.first;
            final v = Viaje.fromMap(doc.id, doc.data());
            controller.add(v);
          },
          onError: controller.addError,
        );
        return;
      }

      if (usingDoc && lastViajeId == id) return;
      await cancelAll();
      lastViajeId = id;
      usingDoc = true;

      viajeDocSub = _db.collection('viajes').doc(id).snapshots().listen(
        (vSnap) {
          if (!vSnap.exists) {
            controller.add(null);
            return;
          }
          final data = vSnap.data();
          if (data == null) {
            controller.add(null);
            return;
          }
          final String uidTxDoc =
              (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
          final String estado = EstadosViaje.normalizar((data['estado'] ?? '').toString());
          final bool activo = data['activo'] == true;
          final bool estadoActivo = estado == EstadosViaje.aceptado ||
              estado == EstadosViaje.enCaminoPickup ||
              estado == EstadosViaje.aBordo ||
              estado == EstadosViaje.enCurso;
          if (uidTxDoc != uidTaxista || !activo || !estadoActivo) {
            _diag('taxista stream hide doc=$id uidDoc=$uidTxDoc activo=$activo estadoActivo=$estadoActivo');
            controller.add(null);
            return;
          }
          _diag('taxista stream emit doc=$id');
          controller.add(Viaje.fromMap(vSnap.id, data));
        },
        onError: controller.addError,
      );
    }

    userSub = userRef.snapshots().listen(
      (uSnap) async {
        final u = uSnap.data() ?? <String, dynamic>{};
        await setFromViajeActivoId(u['viajeActivoId']);
      },
      onError: (_, __) {
        // Error transitorio de red/índice: degradar a "sin viaje" para UX estable.
        controller.add(null);
      },
    );

    return controller.stream;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolAhora() {
    return _col
        .where('estado', whereIn: [EstadosViaje.pendiente, 'buscando', EstadosViaje.pendientePago])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: true)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolProgramados() {
    return _col
        .where('estado', whereIn: [EstadosViaje.pendiente, 'buscando', EstadosViaje.pendientePago])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: false)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamProgramadosAceptadosTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', isEqualTo: EstadosViaje.aceptado)
        .where('fechaHora', isGreaterThan: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamActivosTaxistaRaw(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots();
  }

  /// Limpieza defensiva de consistencia de activos del taxista:
  /// - Si hay varios activos para un taxista, conserva solo uno.
  /// - No depende de lectura del perfil del cliente (evita falsos negativos por permisos).
  /// - Alinea `usuarios/{uidTaxista}.viajeActivoId` al viaje válido (o vacío).
  static Future<void> reconciliarActivosTaxista(String uidTaxista) async {
    final qs = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .get();

    if (qs.docs.isEmpty) {
      await _db.collection('usuarios').doc(uidTaxista).set({
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final docs = [...qs.docs];
    docs.sort((a, b) {
      final ta = a.data()['updatedAt'];
      final tb = b.data()['updatedAt'];
      final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    String? keepId;
    final batch = _db.batch();
    for (final d in docs) {
      final m = d.data();
      final String estado = EstadosViaje.normalizar((m['estado'] ?? '').toString());
      final bool estadoActivo = estado == EstadosViaje.aceptado ||
          estado == EstadosViaje.enCaminoPickup ||
          estado == EstadosViaje.aBordo ||
          estado == EstadosViaje.enCurso;
      final String uidTx = (m['uidTaxista'] ?? m['taxistaId'] ?? '').toString();
      final bool isValid = estadoActivo && uidTx == uidTaxista;
      if (isValid && keepId == null) {
        keepId = d.id;
        continue;
      }

      batch.update(d.reference, {
        'activo': false,
        'aceptado': false,
        'rechazado': true,
        'estado': EstadosViaje.cancelado,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'canceladoPor': 'sistema_inconsistencia',
        'motivoCancelacion': 'desfase_cliente_taxista',
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });
    }

    batch.set(
      _db.collection('usuarios').doc(uidTaxista),
      {
        'viajeActivoId': keepId ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  static Future<void> _limpiarOtrosActivosDelTaxista(
    String uidTaxista, {
    String? exceptoId,
  }) async {
    final qs = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .get();
    if (qs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in qs.docs) {
      if (exceptoId != null && d.id == exceptoId) continue;
      batch.update(d.reference, {
        'estado': EstadosViaje.pendiente,
        'aceptado': false,
        'rechazado': false,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'republicado': true,
        'canceladoPor': 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });
    }
    await batch.commit();
  }
}