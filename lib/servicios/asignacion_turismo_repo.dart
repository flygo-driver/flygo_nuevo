// lib/servicios/asignacion_turismo_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Datos para [ViajesRepo.claimTripWithReason] tras validar pool turístico.
class DatosClaimPoolTurismo {
  final String placa;
  final String subtipoTurismo;
  final String nombreChofer;
  final String telefonoChofer;

  const DatosClaimPoolTurismo({
    required this.placa,
    required this.subtipoTurismo,
    required this.nombreChofer,
    required this.telefonoChofer,
  });
}

class ResultadoPrepClaimPoolTurismo {
  final DatosClaimPoolTurismo? datos;

  const ResultadoPrepClaimPoolTurismo._({this.datos});

  factory ResultadoPrepClaimPoolTurismo.ok(DatosClaimPoolTurismo d) {
    return ResultadoPrepClaimPoolTurismo._(datos: d);
  }

  factory ResultadoPrepClaimPoolTurismo.error() {
    return const ResultadoPrepClaimPoolTurismo._(datos: null);
  }

  bool get ok => datos != null;
}

class AsignacionTurismoRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Alinea `subtipoTurismo` / `tipoVehiculo` del documento con `vehiculos[].tipo` en `choferes_turismo`.
  static String normalizarCodigoTipoTurismo(String? subtipo, String? tipoVehiculoDoc) {
    String from(String raw) {
      final t = raw.trim().toLowerCase();
      if (t.isEmpty) return '';
      if (t.contains('jeepeta')) return 'jeepeta';
      if (t.contains('minivan') || t.contains('minib')) return 'minivan';
      if (t.contains('bus') ||
          t.contains('guagua') ||
          t.contains('autobús') ||
          t.contains('autobus')) {
        return 'bus';
      }
      if (t.contains('carro')) return 'carro';
      if (t == 'carro' || t == 'jeepeta' || t == 'minivan' || t == 'bus') return t;
      if (t == 'viaje_multi' || t == 'ciudad' || t == 'interior') return 'carro';
      return '';
    }

    final String a = from(subtipo ?? '');
    if (a.isNotEmpty) return a;
    final String b = from(tipoVehiculoDoc ?? '');
    if (b.isNotEmpty) return b;
    return 'carro';
  }

  // ==============================================================
  //                   ASIGNAR CHOFER A VIAJE
  // ==============================================================
  static Future<String> asignarChofer({
    required String viajeId,
    required String uidChofer,
    required String nombreChofer,
    required String telefonoChofer,
    required String placa,
    required String subtipoTurismoCodigo,
    String? notaAdmin,
    String marca = '',
    String modelo = '',
    String color = '',
  }) async {
    final vRef = _db.collection('viajes').doc(viajeId);
    final cRef = _db.collection('choferes_turismo').doc(uidChofer);

    try {
      await _db.runTransaction((tx) async {
        final vSnap = await tx.get(vRef);
        if (!vSnap.exists) throw 'viaje-no-existe';

        final vData = vSnap.data()!;
        final String estadoRaw = vData['estado']?.toString() ?? '';
        final String estadoNorm = EstadosViaje.normalizar(estadoRaw);
        final bool estadoOk = estadoRaw == 'pendiente_admin' ||
            estadoNorm == EstadosViaje.pendiente ||
            estadoNorm == EstadosViaje.pendientePago;
        if (!estadoOk) {
          throw 'estado-invalido';
        }

        if ((vData['uidTaxista'] ?? '').toString().isNotEmpty) {
          throw 'ya-asignado';
        }

        final cSnap = await tx.get(cRef);
        if (!cSnap.exists) throw 'chofer-no-existe';

        final cData = cSnap.data()!;
        if (cData['estado'] != 'aprobado') throw 'chofer-no-aprobado';
        if (cData['disponible'] != true) throw 'chofer-no-disponible';

        final Map<String, dynamic> updViaje = {
          'uidTaxista': uidChofer,
          'taxistaId': uidChofer,
          'nombreTaxista': nombreChofer,
          'telefono': telefonoChofer,
          'telefonoTaxista': telefonoChofer,
          'placa': placa,
          'tipoVehiculo': '🏝️ TURISMO 🏝️',
          'tipoVehiculoOriginal': subtipoTurismoCodigo,
          'estado': EstadosViaje.aceptado,
          'aceptado': true,
          'rechazado': false,
          'activo': true,
          'aceptadoEn': FieldValue.serverTimestamp(),
          'asignadoPor': FirebaseAuth.instance.currentUser?.uid,
          'asignadoEn': FieldValue.serverTimestamp(),
          if (notaAdmin != null && notaAdmin.isNotEmpty) 'notaAdminAsignacion': notaAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        };
        if (marca.isNotEmpty) updViaje['marca'] = marca;
        if (modelo.isNotEmpty) updViaje['modelo'] = modelo;
        if (color.isNotEmpty) updViaje['color'] = color;

        tx.update(vRef, updViaje);

        // Marcar chofer como no disponible
        tx.update(cRef, {
          'disponible': false,
          'viajeActualId': viajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });

        // Actualizar usuario del chofer
        final uRef = _db.collection('usuarios').doc(uidChofer);
        tx.set(uRef, {
          'viajeActivoId': viajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Actualizar usuario del cliente
        final uidCliente = vData['uidCliente'] ?? vData['clienteId'];
        if (uidCliente != null && uidCliente.toString().isNotEmpty) {
          final clienteRef = _db.collection('usuarios').doc(uidCliente.toString());
          tx.set(clienteRef, {
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      return 'ok';
    } on FirebaseException catch (e) {
      return 'firebase:${e.code}';
    } catch (e) {
      return e.toString();
    }
  }

  // ==============================================================
  //                   LIBERAR CHOFER AL COMPLETAR
  // ==============================================================
  static Future<void> liberarChofer(String uidChofer) async {
    await _db.collection('choferes_turismo').doc(uidChofer).update({
      'disponible': true,
      'viajeActualId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==============================================================
  //                   OBTENER CHOFERES COMPATIBLES
  // ==============================================================
  static Stream<List<Map<String, dynamic>>> streamChoferesCompatibles({
    required String tipoVehiculo,
    double? latOrigen,
    double? lonOrigen,
    double radioKm = 30,
  }) {
    return _db
        .collection('choferes_turismo')
        .where('estado', isEqualTo: 'aprobado')
        .where('disponible', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final List<Map<String, dynamic>> choferes = [];

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final vehiculos = (data['vehiculos'] as List?) ?? [];
            
            // Verificar si tiene el tipo de vehículo requerido
            final bool tieneVehiculo = vehiculos.any((v) {
              if (v is Map) {
                return v['tipo'] == tipoVehiculo;
              }
              return false;
            });

            if (!tieneVehiculo) continue;

            double? distancia;
            if (latOrigen != null && lonOrigen != null && data['ultimaUbicacion'] != null) {
              final ubicacion = data['ultimaUbicacion'] as GeoPoint;
              distancia = Geolocator.distanceBetween(
                    latOrigen,
                    lonOrigen,
                    ubicacion.latitude,
                    ubicacion.longitude,
                  ) / 1000;
              
              if (distancia > radioKm) continue;
            }

            choferes.add({
              'uid': doc.id,
              ...data,
              'distanciaKm': distancia,
            });
          }

          // Ordenar por distancia
          choferes.sort((a, b) {
            if (a['distanciaKm'] == null) return 1;
            if (b['distanciaKm'] == null) return -1;
            return (a['distanciaKm'] as double).compareTo(b['distanciaKm'] as double);
          });

          return choferes;
        });
  }

  // ==============================================================
  //                   VERIFICAR SI CHOFER ESTA ASIGNADO
  // ==============================================================
  static Future<bool> choferTieneViajeActivo(String uidChofer) async {
    final query = await _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidChofer)
        .where('activo', isEqualTo: true)
        .limit(1)
        .get();
    
    return query.docs.isNotEmpty;
  }

  /// Valor de `canalAsignacion` cuando administración libera el viaje al pool turístico (choferes aprobados).
  static const String canalTurismoPool = 'turismo_pool';

  static int pasajerosRequeridosDesdeViaje(Map<String, dynamic> vData) =>
      _pasajerosRequeridos(vData);

  /// Vehículo del chofer que cumple subtipo y capacidad para un viaje turístico.
  static Map<String, dynamic>? vehiculoTurismoCompatibleEnChofer({
    required Map<String, dynamic> choferData,
    required String subtipoTurismo,
    required int pasajerosRequeridos,
  }) {
    final String st = subtipoTurismo.trim().isEmpty ? 'carro' : subtipoTurismo;
    final Map<String, dynamic>? v =
        _vehiculoQueCoincide(choferData['vehiculos'] as List<dynamic>?, st);
    if (v == null) return null;
    if (_capacidadDesdeVehiculoMap(v, st) < pasajerosRequeridos) return null;
    return v;
  }

  /// Si el chofer no cumple aprobación o vehículo/capacidad para un viaje del pool turístico.
  static const String mensajeNoAutorizadoPoolTurismo =
      'No está autorizado como chofer de turismo. Solo los choferes aprobados para este servicio pueden aceptar este viaje.';

  static Future<ResultadoPrepClaimPoolTurismo> prepararClaimPoolTurismo({
    required String uidChofer,
    required String viajeId,
    required Map<String, dynamic> rawViaje,
  }) async {
    final choferSnap =
        await _db.collection('choferes_turismo').doc(uidChofer).get();
    final choferData = choferSnap.data();
    if (!choferSnap.exists ||
        choferData == null ||
        choferData['estado']?.toString() != 'aprobado') {
      return ResultadoPrepClaimPoolTurismo.error();
    }

    final v = Viaje.fromMap(viajeId, Map<String, dynamic>.from(rawViaje));
    final String subtipo =
        v.subtipoTurismo.trim().isEmpty ? 'carro' : v.subtipoTurismo.trim();
    final int pax = pasajerosRequeridosDesdeViaje(rawViaje);
    final Map<String, dynamic>? veh = vehiculoTurismoCompatibleEnChofer(
      choferData: choferData,
      subtipoTurismo: subtipo,
      pasajerosRequeridos: pax,
    );
    if (veh == null) {
      return ResultadoPrepClaimPoolTurismo.error();
    }

    final uSnap = await _db.collection('usuarios').doc(uidChofer).get();
    final Map<String, dynamic> uData = uSnap.data() ?? <String, dynamic>{};
    final String nombreDoc = (uData['nombre'] ?? '').toString().trim();
    final User? authUser = FirebaseAuth.instance.currentUser;
    final String nombre = nombreDoc.isNotEmpty
        ? nombreDoc
        : (authUser?.displayName ?? authUser?.email ?? 'taxista').toString();
    final String telefono = (uData['telefono'] ?? '').toString();
    final String placa = (veh['placa'] ?? '').toString();

    return ResultadoPrepClaimPoolTurismo.ok(DatosClaimPoolTurismo(
      placa: placa,
      subtipoTurismo: subtipo,
      nombreChofer: nombre,
      telefonoChofer: telefono,
    ));
  }

  // ==============================================================
  //     ASIGNACIÓN AUTOMÁTICA (chofer aprobado + disponible)
  // ==============================================================

  static int _capacidadPorTipoVehiculo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'jeepeta':
        return 6;
      case 'minivan':
        return 8;
      case 'bus':
        return 25;
      case 'carro':
      default:
        return 4;
    }
  }

  static int _capacidadDesdeVehiculoMap(Map<String, dynamic> v, String tipoFallback) {
    final dynamic c = v['capacidad'] ?? v['capacidadPasajeros'];
    if (c is num) return c.round().clamp(1, 60);
    if (c != null) {
      final int? p = int.tryParse(c.toString());
      if (p != null) return p.clamp(1, 60);
    }
    final String t = (v['tipo'] ?? tipoFallback).toString();
    return _capacidadPorTipoVehiculo(t);
  }

  static int _pasajerosRequeridos(Map<String, dynamic> vData) {
    final dynamic ex = vData['extras'];
    if (ex is Map) {
      final dynamic p = ex['pasajeros'] ?? ex['numPasajeros'];
      if (p != null) {
        final int? n = int.tryParse(p.toString());
        if (n != null && n > 0) return n.clamp(1, 60);
      }
    }
    return 1;
  }

  static Map<String, dynamic>? _vehiculoQueCoincide(List<dynamic>? vehiculos, String tipoReq) {
    final String t = tipoReq.toLowerCase();
    if (vehiculos == null) return null;
    for (final dynamic v in vehiculos) {
      if (v is Map) {
        final String vt = v['tipo']?.toString().toLowerCase() ?? '';
        if (vt == t) return Map<String, dynamic>.from(v);
      }
    }
    return null;
  }

  static double? _distanciaKmHastaOrigen(Map<String, dynamic> chofer, double latO, double lonO) {
    double? lat;
    double? lon;
    final dynamic u = chofer['ultimaUbicacion'];
    if (u is GeoPoint) {
      lat = u.latitude;
      lon = u.longitude;
    } else {
      final Map<String, dynamic>? ubic = chofer['ubicacion'] as Map<String, dynamic>?;
      if (ubic != null) {
        lat = (ubic['lat'] as num?)?.toDouble();
        lon = (ubic['lon'] as num?)?.toDouble();
      }
    }
    if (lat == null || lon == null) return null;
    return Geolocator.distanceBetween(latO, lonO, lat, lon) / 1000;
  }

  /// Tras crear un viaje turístico en `pendiente_admin`, intenta asignar el chofer
  /// aprobado más cercano con vehículo compatible y capacidad suficiente.
  /// No altera precio, método de pago ni extras (facturación intacta).
  /// Devuelve el UID del chofer si hubo éxito, o `null` si debe intervenir ADM.
  static Future<String?> intentarAsignacionAutomatica({
    required String viajeId,
    double radioKm = 55,
    int maxCandidatos = 18,
  }) async {
    final DocumentReference<Map<String, dynamic>> vRef = _db.collection('viajes').doc(viajeId);
    final DocumentSnapshot<Map<String, dynamic>> vSnap = await vRef.get();
    if (!vSnap.exists) return null;
    final Map<String, dynamic> v0 = vSnap.data()!;

    if ((v0['tipoServicio'] ?? '').toString() != 'turismo') return null;
    if ((v0['estado'] ?? '').toString() != 'pendiente_admin') return null;
    if ((v0['uidTaxista'] ?? '').toString().isNotEmpty || (v0['taxistaId'] ?? '').toString().isNotEmpty) {
      return null;
    }

    final DateTime now = DateTime.now();
    final dynamic tsAA = v0['acceptAfter'];
    if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) return null;
    final dynamic tsPub = v0['publishAt'];
    if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) return null;

    double latO = 0, lonO = 0;
    final dynamic rawLat = v0['latOrigen'] ?? v0['latCliente'];
    final dynamic rawLon = v0['lonOrigen'] ?? v0['lonCliente'];
    if (rawLat is num) latO = rawLat.toDouble();
    if (rawLon is num) lonO = rawLon.toDouble();
    if (!latO.isFinite || !lonO.isFinite) return null;

    final String subtipo = (v0['subtipoTurismo'] ?? 'carro').toString();
    final int pax = _pasajerosRequeridos(v0);

    final QuerySnapshot<Map<String, dynamic>> q = await _db
        .collection('choferes_turismo')
        .where('estado', isEqualTo: 'aprobado')
        .where('disponible', isEqualTo: true)
        .limit(40)
        .get();

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> ordenados =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(q.docs);

    ordenados.sort((QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b) {
      final double? da = _distanciaKmHastaOrigen(a.data(), latO, lonO);
      final double? db = _distanciaKmHastaOrigen(b.data(), latO, lonO);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    int intentos = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in ordenados) {
      if (intentos >= maxCandidatos) break;
      final Map<String, dynamic> cData = doc.data();
      final Map<String, dynamic>? veh = _vehiculoQueCoincide(cData['vehiculos'] as List<dynamic>?, subtipo);
      if (veh == null) continue;
      if (_capacidadDesdeVehiculoMap(veh, subtipo) < pax) continue;

      final double? dk = _distanciaKmHastaOrigen(cData, latO, lonO);
      if (dk != null && dk > radioKm) continue;

      intentos++;
      final bool ok = await _transaccionAsignarTurismoAutomatico(
        viajeId: viajeId,
        uidChofer: doc.id,
        choferData: cData,
        vehiculo: veh,
        subtipoTurismo: subtipo,
      );
      if (ok) return doc.id;
    }
    return null;
  }

  static Future<bool> _transaccionAsignarTurismoAutomatico({
    required String viajeId,
    required String uidChofer,
    required Map<String, dynamic> choferData,
    required Map<String, dynamic> vehiculo,
    required String subtipoTurismo,
  }) async {
    final DocumentReference<Map<String, dynamic>> vRef = _db.collection('viajes').doc(viajeId);
    final DocumentReference<Map<String, dynamic>> cRef = _db.collection('choferes_turismo').doc(uidChofer);
    final DocumentReference<Map<String, dynamic>> uRef = _db.collection('usuarios').doc(uidChofer);

    bool asignado = false;
    try {
      await _db.runTransaction((Transaction tx) async {
        asignado = false;
        final DocumentSnapshot<Map<String, dynamic>> vSnap = await tx.get(vRef);
        if (!vSnap.exists) return;
        final Map<String, dynamic> d = vSnap.data()!;

        if ((d['tipoServicio'] ?? '').toString() != 'turismo') return;
        if ((d['estado'] ?? '').toString() != 'pendiente_admin') return;
        final bool yaAsignado = ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
            ((d['taxistaId'] ?? '') as String).isNotEmpty;
        if (yaAsignado) return;

        final DateTime now = DateTime.now();
        final dynamic tsAA = d['acceptAfter'];
        if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) return;
        final dynamic tsPub = d['publishAt'];
        if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) return;

        final String reservadoPor = (d['reservadoPor'] ?? '').toString();
        DateTime? reservadoHasta;
        final dynamic rh = d['reservadoHasta'];
        if (rh is Timestamp) reservadoHasta = rh.toDate();
        final bool reservaVigente =
            reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.isAfter(now));
        if (reservaVigente && reservadoPor != uidChofer) return;

        final DocumentSnapshot<Map<String, dynamic>> cSnap = await tx.get(cRef);
        if (!cSnap.exists) return;
        final Map<String, dynamic> cLive = cSnap.data()!;
        if (cLive['estado'] != 'aprobado') return;
        if (cLive['disponible'] != true) return;

        final int pax = _pasajerosRequeridos(d);
        final Map<String, dynamic>? vMatch = _vehiculoQueCoincide(cLive['vehiculos'] as List<dynamic>?, subtipoTurismo);
        if (vMatch == null) return;
        if (_capacidadDesdeVehiculoMap(vMatch, subtipoTurismo) < pax) return;

        final DocumentSnapshot<Map<String, dynamic>> uSnap = await tx.get(uRef);
        final Map<String, dynamic> uData = uSnap.data() ?? <String, dynamic>{};
        if ((uData['viajeActivoId'] ?? '').toString().isNotEmpty) return;

        final String nombreChofer = (choferData['nombre'] ?? cLive['nombre'] ?? '').toString();
        final String telChofer = (choferData['telefono'] ?? cLive['telefono'] ?? '').toString();
        final String placa = (vehiculo['placa'] ?? vMatch['placa'] ?? '').toString();
        final String marca = (vehiculo['marca'] ?? uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
        final String modelo = (vehiculo['modelo'] ?? uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
        final String color = (vehiculo['color'] ?? uData['color'] ?? uData['vehiculoColor'] ?? '').toString();
        final String tipoOriginal = subtipoTurismo;

        final String uidCliente = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();

        tx.update(vRef, {
          'uidTaxista': uidChofer,
          'taxistaId': uidChofer,
          'nombreTaxista': nombreChofer,
          'telefono': telChofer,
          'telefonoTaxista': telChofer,
          'placa': placa,
          'tipoVehiculo': '🏝️ TURISMO 🏝️',
          'tipoVehiculoOriginal': tipoOriginal,
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
          'asignacionAutomatica': true,
          'asignadoPor': 'auto',
          'asignadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
          'reservadoPor': '',
          'reservadoHasta': null,
          'ignoradosPor': FieldValue.delete(),
        });

        tx.update(cRef, {
          'disponible': false,
          'viajeActualId': viajeId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(
          uRef,
          {
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (uidCliente.isNotEmpty) {
          tx.set(
            _db.collection('usuarios').doc(uidCliente),
            {
              'viajeActivoId': viajeId,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        asignado = true;
      });
    } catch (_) {
      return false;
    }
    return asignado;
  }
}