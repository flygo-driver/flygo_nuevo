// lib/servicios/asignacion_turismo_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flygo_nuevo/modelo/chofer_turismo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';

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

enum MotivoRechazoPrepPoolTurismo { noAprobado, vehiculoNoCompatible }

class ResultadoEvalVehiculoTurismo {
  final Map<String, dynamic>? vehiculo;
  final String? mensaje;

  const ResultadoEvalVehiculoTurismo({this.vehiculo, this.mensaje});

  bool get ok => vehiculo != null;
}

class ResultadoPrepClaimPoolTurismo {
  final DatosClaimPoolTurismo? datos;
  final MotivoRechazoPrepPoolTurismo? motivo;
  final String? mensajeDetalle;

  const ResultadoPrepClaimPoolTurismo._({
    this.datos,
    this.motivo,
    this.mensajeDetalle,
  });

  factory ResultadoPrepClaimPoolTurismo.ok(DatosClaimPoolTurismo d) {
    return ResultadoPrepClaimPoolTurismo._(datos: d);
  }

  factory ResultadoPrepClaimPoolTurismo.error(
    MotivoRechazoPrepPoolTurismo motivo, {
    String? mensajeDetalle,
  }) {
    return ResultadoPrepClaimPoolTurismo._(
      datos: null,
      motivo: motivo,
      mensajeDetalle: mensajeDetalle,
    );
  }

  bool get ok => datos != null;

  String get mensaje =>
      mensajeDetalle ??
      AsignacionTurismoRepo.mensajePrepClaimPoolTurismo(motivo);
}

class AsignacionTurismoRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Chofer aprobado por ADM y habilitado para pool / asignación.
  static bool choferEstadoOperativo(Object? estadoRaw) {
    final String e = estadoRaw?.toString().trim().toLowerCase() ?? '';
    return e == 'aprobado' || e == 'activo';
  }

  /// Categorías de destino turístico (catálogo RD). No son tipos de vehículo.
  static const Set<String> _categoriasDestinoTurismo = {
    'AEROPUERTO',
    'MUELLE',
    'ZONA_COLONIAL',
    'CIUDAD',
    'PLAYA',
    'RESORT',
    'HOTEL',
    'TOUR',
    'PARQUE',
    'MONTANA',
    'CASCADA',
    'LAGO',
    'MUSEO',
    'ATRACCION',
  };

  static bool esCategoriaDestinoTurismo(String raw) {
    if (raw.trim().isEmpty) return false;
    return _categoriasDestinoTurismo.contains(raw.trim().toUpperCase());
  }

  static String? _codigoVehiculoDesdeCampoDoc(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final t = raw.trim();
    if (t.contains('🏝️')) return null;
    final c = normalizarCodigoTipoTurismo(t, t);
    return c.isEmpty ? null : c;
  }

  static String? _codigoVehiculoDesdeCotizacionDesglose(
    Map<String, dynamic> rawViaje,
  ) {
    final dynamic ex = rawViaje['extras'];
    if (ex is! Map) return null;
    final dynamic desg = ex['cotizacionDesglose'];
    if (desg is! Map) return null;
    final String? clave = desg['claveVehiculo']?.toString();
    if (clave == null || clave.trim().isEmpty) return null;
    return normalizarCodigoTipoTurismo(clave, clave);
  }

  /// Alinea `subtipoTurismo` / `tipoVehiculo` del documento con `vehiculos[].tipo` en `choferes_turismo`.
  static String normalizarCodigoTipoTurismo(
      String? subtipo, String? tipoVehiculoDoc) {
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
      if (t == 'carro' || t == 'jeepeta' || t == 'minivan' || t == 'bus') {
        return t;
      }
      if (t == 'viaje_multi' || t == 'ciudad' || t == 'interior') {
        return 'carro';
      }
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
        if ((vData['tipoServicio'] ?? '').toString() != 'turismo') {
          throw 'no-turismo';
        }
        final String canalRaw =
            (vData['canalAsignacion'] ?? 'admin').toString().trim();
        final String canalAsign = canalRaw.isEmpty ? 'admin' : canalRaw;
        if (canalAsign != 'admin') {
          throw 'canal-invalido';
        }

        final String estadoRaw = vData['estado']?.toString() ?? '';
        final String estadoNorm = EstadosViaje.normalizar(estadoRaw);
        final bool estadoOk = estadoRaw == 'pendiente_admin' ||
            estadoNorm == EstadosViaje.pendiente ||
            estadoNorm == EstadosViaje.pendientePago;
        if (!estadoOk) {
          throw 'estado-invalido';
        }

        if ((vData['uidTaxista'] ?? '').toString().trim().isNotEmpty ||
            (vData['taxistaId'] ?? '').toString().trim().isNotEmpty) {
          throw 'ya-asignado';
        }

        final cSnap = await tx.get(cRef);
        if (!cSnap.exists) throw 'chofer-no-existe';

        final cData = cSnap.data()!;
        if (!choferEstadoOperativo(cData['estado'])) throw 'chofer-no-aprobado';
        if (cData['disponible'] != true) throw 'chofer-no-disponible';

        final uRef = _db.collection('usuarios').doc(uidChofer);
        final uSnap = await tx.get(uRef);
        final bSnap =
            await tx.get(_db.collection('billeteras_taxista').doc(uidChofer));
        if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
            uSnap.data(), bSnap.data())) {
          throw 'chofer-bloqueo-prepago';
        }
        // Turismo: no exigir prepago completo al asignar; comisión al finalizar viaje.

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
          if (notaAdmin != null && notaAdmin.isNotEmpty)
            'notaAdminAsignacion': notaAdmin,
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
        tx.set(
            uRef,
            {
              'viajeActivoId': viajeId,
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        // Actualizar usuario del cliente
        final uidCliente = vData['uidCliente'] ?? vData['clienteId'];
        if (uidCliente != null && uidCliente.toString().isNotEmpty) {
          final clienteRef =
              _db.collection('usuarios').doc(uidCliente.toString());
          tx.set(
              clienteRef,
              {
                'viajeActivoId': viajeId,
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
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
        if (latOrigen != null &&
            lonOrigen != null &&
            data['ultimaUbicacion'] != null) {
          final ubicacion = data['ultimaUbicacion'] as GeoPoint;
          distancia = Geolocator.distanceBetween(
                latOrigen,
                lonOrigen,
                ubicacion.latitude,
                ubicacion.longitude,
              ) /
              1000;

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
        return (a['distanciaKm'] as double)
            .compareTo(b['distanciaKm'] as double);
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

  /// Documento Firestore de viaje turístico (independiente de corporativo y pool normal).
  static bool esDocumentoViajeTurismo(Map<String, dynamic> vData) {
    return (vData['tipoServicio'] ?? '').toString().trim() == 'turismo';
  }

  /// Viaje turístico publicado en pool turístico (choferes aprobados pueden aceptar).
  static bool viajeEnPoolTurismoPublico(Map<String, dynamic> vData) {
    if ((vData['tipoServicio'] ?? '').toString() != 'turismo') return false;
    final canal = (vData['canalAsignacion'] ?? '').toString().trim();
    return canal == canalTurismoPool;
  }

  /// Chofer confirmó el viaje (aceptó desde pool o asignación ADM).
  /// Requiere `aceptado == true` (no basta `uidTaxista` ni estado «asignado»).
  static bool viajeTurismoChoferConfirmado(Map<String, dynamic> vData) {
    if ((vData['tipoServicio'] ?? '').toString() != 'turismo') return false;
    final String uidTx =
        (vData['uidTaxista'] ?? vData['taxistaId'] ?? '').toString().trim();
    if (uidTx.isEmpty) return false;
    if (vData['aceptado'] != true) return false;
    final String st =
        EstadosViaje.normalizar((vData['estado'] ?? '').toString());
    if (vData['completado'] == true || EstadosViaje.esTerminal(st)) {
      return false;
    }
    return true;
  }

  /// Cliente aún espera chofer (sin confirmación real del conductor).
  static bool viajeTurismoEsperandoChofer(Map<String, dynamic> vData) {
    if ((vData['tipoServicio'] ?? '').toString() != 'turismo') return false;
    final String st =
        EstadosViaje.normalizar((vData['estado'] ?? '').toString());
    if (vData['completado'] == true || EstadosViaje.esTerminal(st)) {
      return false;
    }
    return !viajeTurismoChoferConfirmado(vData);
  }

  /// Texto principal para pantalla de espera del cliente.
  static String tituloEsperaTurismoCliente(Map<String, dynamic> vData) {
    if (viajeTurismoChoferConfirmado(vData)) {
      return 'Chofer confirmado';
    }
    if (viajeEnPoolTurismoPublico(vData)) {
      return 'En pool turístico';
    }
    if (vData['esAhora'] == true) {
      return 'Publicando en pool turístico…';
    }
    return 'Reserva turística registrada';
  }

  /// Subtítulo contextual (pool, vehículo, ventana programada).
  static String subtituloEsperaTurismoCliente(
    Map<String, dynamic> vData, {
    int choferesCompatibles = 0,
    int choferesEnLinea = 0,
  }) {
    final String vehiculo =
        etiquetaVehiculoRequeridoDesdeViaje(vData);
    if (viajeTurismoChoferConfirmado(vData)) {
      return 'Abriendo tu viaje con el chofer asignado…';
    }
    if (viajeEnPoolTurismoPublico(vData)) {
      if (choferesCompatibles > 0) {
        return 'Pediste $vehiculo.\n'
            '$choferesCompatibles chofer${choferesCompatibles == 1 ? '' : 'es'} '
            'con ese vehículo ${choferesCompatibles == 1 ? 'está' : 'están'} '
            'en línea y pueden ver tu viaje en «Pool turístico».';
      }
      if (choferesEnLinea > 0) {
        return 'Pediste $vehiculo.\n'
            'Hay choferes turísticos en línea, pero ninguno con ese vehículo ahora. '
            'Escribe a operaciones abajo y te asignamos uno.';
      }
      return 'Pediste $vehiculo.\n'
          'Tu viaje está visible para choferes de turismo aprobados. '
          'Si tarda, escribe a operaciones RAI abajo.';
    }
    final DateTime? pub = _tsDate(vData['publishAt']);
    if (pub != null && pub.isAfter(DateTime.now())) {
      final String hora =
          '${pub.hour.toString().padLeft(2, '0')}:${pub.minute.toString().padLeft(2, '0')}';
      return 'Pediste $vehiculo.\n'
          'El pool turístico abre cerca de las $hora. '
          'Mientras tanto puedes escribir a operaciones si necesitas ayuda.';
    }
    return 'Pediste $vehiculo.\n'
        'Estamos publicando tu viaje en el pool turístico para choferes aprobados.';
  }

  static DateTime? _tsDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  /// Cuenta choferes de la red con el subtipo exacto que pidió el cliente.
  static int contarChoferesCompatiblesEnRed(
    Map<String, dynamic> vData,
    Iterable<ChoferTurismo> choferes,
  ) {
    final String subtipo = subtipoTurismoRequeridoDesdeViaje(vData);
    final int pax = pasajerosRequeridosDesdeViaje(vData);
    var n = 0;
    for (final ChoferTurismo c in choferes) {
      if (!c.disponible) continue;
      final bool tiene = c.vehiculos.any((v) {
        final String t = normalizarCodigoTipoTurismo(v.tipo, v.tipo);
        if (t != subtipo) return false;
        return _capacidadPorTipoVehiculo(t) >= pax;
      });
      if (tiene) n++;
    }
    return n;
  }

  /// Pasa de cola ADM (`admin`) al pool turístico cuando no hay chofer asignado.
  /// Devuelve `true` si el documento quedó en `turismo_pool`.
  static Future<bool> liberarViajeAlPoolTurismoSiAplica({
    required String viajeId,
    bool omitirVentanaPublicacion = false,
  }) async {
    if (viajeId.trim().isEmpty) return false;
    final DocumentReference<Map<String, dynamic>> vRef =
        _db.collection('viajes').doc(viajeId);
    var liberado = false;
    await _db.runTransaction((Transaction tx) async {
      liberado = false;
      final snap = await tx.get(vRef);
      if (!snap.exists) return;
      final v = snap.data()!;

      if ((v['tipoServicio'] ?? '').toString() != 'turismo') return;

      final uidTx =
          (v['uidTaxista'] ?? v['taxistaId'] ?? '').toString().trim();
      if (uidTx.isNotEmpty) return;

      final canal = (v['canalAsignacion'] ?? 'admin').toString().trim();
      if (canal != 'admin') return;

      final estadoRaw = (v['estado'] ?? '').toString();
      final estadoNorm = EstadosViaje.normalizar(estadoRaw);
      final bool estadoOk = estadoRaw == 'pendiente_admin' ||
          estadoNorm == EstadosViaje.pendiente ||
          estadoNorm == EstadosViaje.pendientePago;
      if (!estadoOk) return;

      if (!omitirVentanaPublicacion) {
        final now = DateTime.now();
        final tsAA = v['acceptAfter'];
        if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) return;
        final tsPub = v['publishAt'];
        if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) return;
      }

      tx.update(vRef, {
        'canalAsignacion': canalTurismoPool,
        'liberadoPoolTurismoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      liberado = true;
    });
    return liberado;
  }

  static int pasajerosRequeridosDesdeViaje(Map<String, dynamic> vData) =>
      _pasajerosRequeridos(vData);

  /// Auto-asignación ADM: estado inicial o republicado tras cancelación del chofer.
  static bool estadoPermiteAutoAsignacionTurismo(Map<String, dynamic> vData) {
    if ((vData['tipoServicio'] ?? '').toString() != 'turismo') return false;
    if ((vData['uidTaxista'] ?? vData['taxistaId'] ?? '').toString().isNotEmpty) {
      return false;
    }
    final canal = (vData['canalAsignacion'] ?? 'admin').toString().trim();
    if (canal != 'admin') return false;
    final String estado = (vData['estado'] ?? '').toString();
    if (estado == 'pendiente_admin') return true;
    return estado == EstadosViaje.pendiente && vData['republicado'] == true;
  }

  /// Vehículo del chofer que cumple subtipo y capacidad para un viaje turístico.
  static Map<String, dynamic>? vehiculoTurismoCompatibleEnChofer({
    required Map<String, dynamic> choferData,
    required String subtipoTurismo,
    required int pasajerosRequeridos,
    String? tipoVehiculoViaje,
  }) {
    return evaluarVehiculoTurismoEnChofer(
      choferData: choferData,
      subtipoRequerido: subtipoTurismo,
      pasajerosRequeridos: pasajerosRequeridos,
      tipoVehiculoViaje: tipoVehiculoViaje,
    ).vehiculo;
  }

  static String labelTipoVehiculoTurismo(String codigo) {
    switch (normalizarCodigoTipoTurismo(codigo, codigo)) {
      case 'jeepeta':
        return 'Jeepeta Turismo';
      case 'minivan':
        return 'Minivan Turismo';
      case 'bus':
        return 'Bus Turismo';
      case 'carro':
      default:
        return 'Carro Turismo';
    }
  }

  static List<String> labelsVehiculosAprobadosEnChofer(
    Map<String, dynamic> choferData,
  ) {
    final List<dynamic>? vehiculos = choferData['vehiculos'] as List<dynamic>?;
    if (vehiculos == null || vehiculos.isEmpty) return const <String>[];
    final List<String> labels = <String>[];
    for (final dynamic v in vehiculos) {
      if (v is! Map) continue;
      final String codigo = normalizarCodigoTipoTurismo(
        v['tipo']?.toString(),
        v['tipoLabel']?.toString(),
      );
      final String label = (v['tipoLabel'] ?? labelTipoVehiculoTurismo(codigo))
          .toString()
          .trim();
      if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
    }
    return labels;
  }

  static ResultadoEvalVehiculoTurismo evaluarVehiculoTurismoParaViaje({
    required Map<String, dynamic> choferData,
    required Map<String, dynamic> rawViaje,
  }) {
    final String subtipo = subtipoTurismoRequeridoDesdeViaje(rawViaje);
    final int pax = pasajerosRequeridosDesdeViaje(rawViaje);
    final String tipoVehDoc = (rawViaje['tipoVehiculo'] ??
            rawViaje['tipoVehiculoOriginal'] ??
            '')
        .toString();
    return evaluarVehiculoTurismoEnChofer(
      choferData: choferData,
      subtipoRequerido: subtipo,
      pasajerosRequeridos: pax,
      tipoVehiculoViaje: tipoVehDoc,
    );
  }

  static ResultadoEvalVehiculoTurismo evaluarVehiculoTurismoEnChofer({
    required Map<String, dynamic> choferData,
    required String subtipoRequerido,
    required int pasajerosRequeridos,
    String? tipoVehiculoViaje,
  }) {
    final String st = normalizarCodigoTipoTurismo(
      subtipoRequerido,
      tipoVehiculoViaje ?? subtipoRequerido,
    );
    final String reqLabel = labelTipoVehiculoTurismo(st);
    final List<String> suyos = labelsVehiculosAprobadosEnChofer(choferData);

    final Map<String, dynamic>? v = _vehiculoQueCoincide(
      choferData['vehiculos'] as List<dynamic>?,
      st,
    );
    if (v == null) {
      final String suyosTxt = suyos.isEmpty
          ? 'ninguno registrado en tu perfil de turismo'
          : suyos.join(', ');
      return ResultadoEvalVehiculoTurismo(
        mensaje: 'Este viaje pidió $reqLabel. '
            'Tus vehículos aprobados: $suyosTxt. '
            'Si tienes el vehículo correcto, actualiza tu solicitud de chofer turismo.',
      );
    }

    final int cap = _capacidadDesdeVehiculoMap(v, st);
    if (cap < pasajerosRequeridos) {
      final String tipoLabel = labelTipoVehiculoTurismo(
        v['tipo']?.toString() ?? st,
      );
      return ResultadoEvalVehiculoTurismo(
        mensaje: 'Este viaje requiere $pasajerosRequeridos pasajero(s). '
            'Tu $tipoLabel aprobado(a) admite hasta $cap. '
            'Revisa los datos de tu vehículo en tu perfil de turismo.',
      );
    }

    return ResultadoEvalVehiculoTurismo(vehiculo: v);
  }

  /// Si el chofer no cumple aprobación o vehículo/capacidad para un viaje del pool turístico.
  static const String mensajeNoAutorizadoPoolTurismo =
      'No está autorizado como chofer de turismo. Solo los choferes aprobados para este servicio pueden aceptar este viaje.';

  static const String mensajeVehiculoNoCompatiblePoolTurismo =
      'Tu vehículo aprobado no coincide con lo que pidió este viaje. Revisa tu perfil de chofer turismo.';

  static String mensajePrepClaimPoolTurismo(
    MotivoRechazoPrepPoolTurismo? motivo,
  ) {
    switch (motivo) {
      case MotivoRechazoPrepPoolTurismo.vehiculoNoCompatible:
        return mensajeVehiculoNoCompatiblePoolTurismo;
      case MotivoRechazoPrepPoolTurismo.noAprobado:
      case null:
        return mensajeNoAutorizadoPoolTurismo;
    }
  }

  /// Código de vehículo (`carro`, `jeepeta`, …) alineado con `vehiculos[].tipo`.
  static String subtipoTurismoRequeridoDesdeViaje(Map<String, dynamic> rawViaje) {
    final String subtipo = (rawViaje['subtipoTurismo'] ?? '').toString().trim();
    final String tipoOrig =
        (rawViaje['tipoVehiculoOriginal'] ?? '').toString().trim();
    final String tipoVeh = (rawViaje['tipoVehiculo'] ?? '').toString().trim();

    if (subtipo.isNotEmpty && !esCategoriaDestinoTurismo(subtipo)) {
      final String? desdeSubtipo = _codigoVehiculoDesdeCampoDoc(subtipo);
      if (desdeSubtipo != null) return desdeSubtipo;
    }

    final String? desdeOriginal = _codigoVehiculoDesdeCampoDoc(tipoOrig);
    if (desdeOriginal != null) return desdeOriginal;

    final String? desdeDesglose =
        _codigoVehiculoDesdeCotizacionDesglose(rawViaje);
    if (desdeDesglose != null) return desdeDesglose;

    final String? desdeTipoDoc = _codigoVehiculoDesdeCampoDoc(tipoVeh);
    if (desdeTipoDoc != null) return desdeTipoDoc;

    return 'carro';
  }

  /// Etiqueta legible alineada con pool chofer y aprobación ADM (ej. Carro Turismo).
  static String etiquetaVehiculoRequeridoDesdeViaje(
    Map<String, dynamic> rawViaje,
  ) {
    return labelTipoVehiculoTurismo(subtipoTurismoRequeridoDesdeViaje(rawViaje));
  }

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
        !choferEstadoOperativo(choferData['estado'])) {
      return ResultadoPrepClaimPoolTurismo.error(
        MotivoRechazoPrepPoolTurismo.noAprobado,
      );
    }

    final String subtipo = subtipoTurismoRequeridoDesdeViaje(rawViaje);
    final int pax = pasajerosRequeridosDesdeViaje(rawViaje);
    final ResultadoEvalVehiculoTurismo eval = evaluarVehiculoTurismoEnChofer(
      choferData: choferData,
      subtipoRequerido: subtipo,
      pasajerosRequeridos: pax,
      tipoVehiculoViaje: (rawViaje['tipoVehiculo'] ??
              rawViaje['tipoVehiculoOriginal'] ??
              '')
          .toString(),
    );
    if (!eval.ok) {
      return ResultadoPrepClaimPoolTurismo.error(
        MotivoRechazoPrepPoolTurismo.vehiculoNoCompatible,
        mensajeDetalle: eval.mensaje,
      );
    }
    final Map<String, dynamic> veh = eval.vehiculo!;

    final uSnap = await _db.collection('usuarios').doc(uidChofer).get();
    final Map<String, dynamic> uData = uSnap.data() ?? <String, dynamic>{};
    final bSnap =
        await _db.collection('billeteras_taxista').doc(uidChofer).get();
    // Bloqueo solo si ya debe comisión pendiente o sin saldo operativo (no exigir comisión completa antes).
    if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
      uSnap.data(),
      bSnap.data(),
    )) {
      return ResultadoPrepClaimPoolTurismo.error(
        MotivoRechazoPrepPoolTurismo.noAprobado,
        mensajeDetalle: PagosTaxistaRepo.mensajeRecargaBannerLista,
      );
    }
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

  static int _capacidadDesdeVehiculoMap(
      Map<String, dynamic> v, String tipoFallback) {
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

  static Map<String, dynamic>? _vehiculoQueCoincide(
      List<dynamic>? vehiculos, String tipoReq) {
    final String t = normalizarCodigoTipoTurismo(tipoReq, tipoReq);
    if (vehiculos == null) return null;
    for (final dynamic v in vehiculos) {
      if (v is Map) {
        final String vt = normalizarCodigoTipoTurismo(
          v['tipo']?.toString(),
          v['tipoLabel']?.toString(),
        );
        if (vt == t) return Map<String, dynamic>.from(v);
      }
    }
    return null;
  }

  /// Publica el viaje turístico en el pool (`turismo_pool`) para que lo tome un
  /// chofer aprobado con el vehículo correcto. No asigna chofer automáticamente.
  static Future<bool> publicarViajeEnPoolTurismo({
    required String viajeId,
    bool omitirVentanaPublicacion = false,
  }) async {
    if (viajeId.trim().isEmpty) return false;

    final _CallableTurismoOutcome callable =
        await _intentarAsignacionTurismoCallable(
      viajeId: viajeId,
      omitirVentanaPublicacion: omitirVentanaPublicacion,
    );
    if (callable.reachedServer) {
      return callable.liberadoPool;
    }

    // Sin fallback en cliente: Firestore rules no permiten cambiar canalAsignacion.
    return false;
  }

  /// Compatibilidad: reintentos del cliente solo liberan al pool (sin auto-asignar).
  static Future<String?> intentarAsignacionAutomatica({
    required String viajeId,
    double radioKm = 55,
    int maxCandidatos = 18,
    bool omitirVentanaPublicacion = false,
  }) async {
    await publicarViajeEnPoolTurismo(
      viajeId: viajeId,
      omitirVentanaPublicacion: omitirVentanaPublicacion,
    );
    return null;
  }

  static Future<_CallableTurismoOutcome> _intentarAsignacionTurismoCallable({
    required String viajeId,
    bool omitirVentanaPublicacion = false,
  }) async {
    if (viajeId.trim().isEmpty) {
      return const _CallableTurismoOutcome(reachedServer: false);
    }
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('intentarAsignacionTurismoSeguro');
      final HttpsCallableResult<dynamic> res =
          await callable.call(<String, dynamic>{
        'viajeId': viajeId.trim(),
        if (omitirVentanaPublicacion) 'omitirVentanaPublicacion': true,
      });
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(res.data as Map<dynamic, dynamic>);
      if (data['ok'] != true) {
        return const _CallableTurismoOutcome(reachedServer: false);
      }
      return _CallableTurismoOutcome(
        reachedServer: true,
        liberadoPool: data['liberadoPool'] == true,
      );
    } on FirebaseFunctionsException catch (e, st) {
      if (e.code != 'not-found' && e.code != 'failed-precondition') {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'intentarAsignacionTurismoSeguro',
        );
      }
      return const _CallableTurismoOutcome(reachedServer: false);
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'intentarAsignacionTurismoSeguro',
      );
      return const _CallableTurismoOutcome(reachedServer: false);
    }
  }
}

class _CallableTurismoOutcome {
  final bool reachedServer;
  final bool liberadoPool;

  const _CallableTurismoOutcome({
    required this.reachedServer,
    this.liberadoPool = false,
  });
}
