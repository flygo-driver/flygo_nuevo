import 'package:cloud_firestore/cloud_firestore.dart'
    show GeoPoint, Timestamp, FieldValue;
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';

/// Modelo de Viaje usado en la app (cliente y taxista).
class Viaje {
  final String id;

  // Identidad (cliente/taxista)
  final String clienteId;
  final String uidCliente;
  final String uidTaxista;
  final String taxistaId;
  final String nombreTaxista;

  // Direcciones y coords
  final String origen;
  final String destino;
  final double latCliente;
  final double lonCliente;
  final double latDestino;
  final double lonDestino;

  // Posición en vivo del taxista (ping)
  final double latTaxista;
  final double lonTaxista;

  // Precios
  final double precio;
  final double precioFinal;
  final double comision;
  final double gananciaTaxista;

  // Preferencias
  final String metodoPago;
  final String tipoVehiculo;
  final String marca;
  final String modelo;
  final String color;
  final bool idaYVuelta;

  // Teléfonos / placa
  final String telefono;
  final String placa;

  // Estado
  final String estado;
  final bool aceptado;
  final bool rechazado;
  final bool completado;
  final bool calificado;

  // Rating/feedback
  final double calificacion;
  final String comentario;

  // Fecha/hora del servicio
  final DateTime fechaHora;

  // Programados
  final bool esAhora;
  final bool programado;
  final DateTime?
      acceptAfter; // Claim permitido desde aquí (alineado con publishAt en programados)
  final DateTime?
      publishAt; // Visibilidad en pool; ver TripPublishWindows.poolLeadMinutesProgramado
  final DateTime? startWindowAt;

  // ============================================
  // ✅ CAMPOS NUEVOS PARA VERSIÓN 2.0
  // ============================================
  final String tipoServicio; // 'normal' | 'motor' | 'turismo'
  final String subtipoTurismo; // 'carro' | 'jeepeta' | 'minivan' | 'bus'
  final String canalAsignacion; // 'pool' | 'admin'
  final String? catalogoTurismoId; // ID del destino en catálogo turístico

  // ✅ NUEVO: GeoPoint para consultas geoespaciales
  final GeoPoint? origenGeoPoint;

  // 🔥 NUEVOS: Código de verificación (6 dígitos)
  final String? codigoVerificacion;
  final bool codigoVerificado;

  // ✅ NUEVO: Waypoints para múltiples paradas
  final List<Map<String, dynamic>>? waypoints;

  // 👇 NUEVO: Campo extras para información adicional (pasajeros, etc.)
  final Map<String, dynamic>? extras;

  /// Inicio del trayecto hacia destino (escrito por ViajesRepo / flujos estándar).
  final DateTime? inicioEnRutaEn;

  /// Alternativa usada en pantalla taxista al marcar viaje iniciado.
  final DateTime? viajeIniciadoEn;

  Viaje({
    this.id = '',
    this.clienteId = '',
    this.uidCliente = '',
    this.uidTaxista = '',
    this.taxistaId = '',
    this.nombreTaxista = '',
    this.origen = '',
    this.destino = '',
    this.latCliente = 0.0,
    this.lonCliente = 0.0,
    this.latDestino = 0.0,
    this.lonDestino = 0.0,
    this.latTaxista = 0.0,
    this.lonTaxista = 0.0,
    this.precio = 0.0,
    this.precioFinal = 0.0,
    this.comision = 0.0,
    this.gananciaTaxista = 0.0,
    this.metodoPago = 'Efectivo',
    this.tipoVehiculo = 'Carro',
    this.marca = '',
    this.modelo = '',
    this.color = '',
    this.idaYVuelta = false,
    this.telefono = '',
    this.placa = '',
    this.estado = EstadosViaje.pendiente,
    this.aceptado = false,
    this.rechazado = false,
    this.completado = false,
    this.calificado = false,
    this.calificacion = 0.0,
    this.comentario = '',
    DateTime? fechaHora,
    this.esAhora = false,
    this.programado = false,
    this.acceptAfter,
    this.publishAt, // 🔥 NUEVO
    this.startWindowAt,
    this.tipoServicio = 'normal',
    this.subtipoTurismo = '',
    this.canalAsignacion = 'pool',
    this.catalogoTurismoId,
    this.origenGeoPoint,
    // 🔥 NUEVOS
    this.codigoVerificacion,
    this.codigoVerificado = false,
    // ✅ NUEVO: Waypoints
    this.waypoints,
    // 👇 NUEVO: extras
    this.extras,
    this.inicioEnRutaEn,
    this.viajeIniciadoEn,
  }) : fechaHora = fechaHora ?? DateTime.now();

  // === Getters de compatibilidad para la UI (parches mínimos) ===
  String get telefonoTaxista => telefono;
  double get driverLat => latTaxista;
  double get driverLon => lonTaxista;

  // === Getters de utilidad ===
  bool get tienePickup => _validCoord(latCliente, lonCliente);
  bool get tieneDestino => _validCoord(latDestino, lonDestino);
  bool get esActivo => EstadosViaje.esActivo(estado);
  bool get esTerminal => EstadosViaje.esTerminal(estado);

  // === Getters específicos para versión 2.0 ===
  bool get esMotor => tipoServicio == 'motor';
  bool get esTurismo => tipoServicio == 'turismo';
  bool get esNormal => tipoServicio == 'normal';
  bool get vaAlPool => canalAsignacion == 'pool';
  bool get vaAAdmin => canalAsignacion == 'admin';

  // 🔥 NUEVA FUNCIÓN: Determina si el viaje programado está disponible para aceptar
  bool esProgramadoDisponible(DateTime now) {
    if (acceptAfter == null) return true;
    // Solo disponible si faltan 30 minutos o menos
    return !now.isBefore(acceptAfter!);
  }

  // 🔥 NUEVA FUNCIÓN: Obtiene minutos restantes para disponibilidad
  int getMinutosRestantesParaDisponible(DateTime now) {
    if (acceptAfter == null) return 0;
    final diff = acceptAfter!.difference(now);
    return diff.inMinutes > 0 ? diff.inMinutes : 0;
  }

  // === Helpers de presentación / disponibilidad ===
  bool get hasTelefono => telefono.trim().isNotEmpty;
  bool get hasPickup => _validCoord(latCliente, lonCliente);
  bool get hasDestino => _validCoord(latDestino, lonDestino);
  bool get hasDriverPos => _validCoord(latTaxista, lonTaxista);

  /// Referencia de tiempo para cronómetro "en ruta" (campos ya existentes en Firestore).
  DateTime? get inicioRutaDesde => inicioEnRutaEn ?? viajeIniciadoEn;

  /// Resumen listo para pintar en la tarjeta de la UI
  String get vehiculoResumen {
    final partes = <String>[
      if (tipoServicio != 'normal') '$tipoServicio:',
      if (tipoVehiculo.trim().isNotEmpty) tipoVehiculo.trim(),
      if (esTurismo && subtipoTurismo.isNotEmpty) '($subtipoTurismo)',
      if (marca.trim().isNotEmpty) marca.trim(),
      if (modelo.trim().isNotEmpty) modelo.trim(),
      if (color.trim().isNotEmpty) 'Color: ${color.trim()}',
      if (placa.trim().isNotEmpty) 'Placa: ${placa.trim()}',
    ];
    return partes.isEmpty ? '—' : partes.join(' · ');
  }

  /// Teléfono visible normalizado (p. ej. +18095551212) o '—'
  String get telefonoVisible {
    final raw = telefono.trim();
    final digits = raw.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) return '—';
    final norma = digits.startsWith('1')
        ? digits
        : (digits.length == 10 ? '1$digits' : digits);
    return '+$norma';
  }

  // ---- Helpers de parseo/validación ----
  static String _asString(dynamic v) => (v ?? '').toString();

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return 0.0;
      return d;
    }
    if (v is String) {
      final d = double.tryParse(v) ?? 0.0;
      if (d.isNaN || d.isInfinite) return 0.0;
      return d;
    }
    return 0.0;
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes' || s == 'si' || s == 'sí';
    }
    return false;
  }

  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _asDateOrNull(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  static bool _validCoord(double lat, double lon) {
    if (lat.isNaN || lon.isNaN) return false;
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat == 0 && lon == 0) return false;
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  /// Compat: camelCase, snake_case o campo usado en acuerdos bola si el doc lo trae.
  static String? _primerCodigoVerificacion(Map<String, dynamic> data) {
    for (final key in [
      'codigoVerificacion',
      'codigo_verificacion',
      'codigoVerificacionBola'
    ]) {
      final s = _asString(data[key]).trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  // ---- Factory/serialización ----
  factory Viaje.fromMap(String id, Map<String, dynamic> data) {
    // Fallbacks de pickup por compat (latOrigen/lonOrigen)
    final double latCli = _asDouble(data['latCliente']);
    final double lonCli = _asDouble(data['lonCliente']);
    final bool cliOk = _validCoord(latCli, lonCli);
    final double latOri = _asDouble(data['latOrigen']);
    final double lonOri = _asDouble(data['lonOrigen']);

    final String rawEstado = _asString(data['estado']);
    final bool acept = _asBool(data['aceptado']);
    final bool comp = _asBool(data['completado']);

    final String estadoNorm = EstadosViaje.normalizar(
      rawEstado.isEmpty
          ? (comp
              ? EstadosViaje.completado
              : (acept ? EstadosViaje.aceptado : EstadosViaje.pendiente))
          : rawEstado,
    );

    // driverLat/driverLon compat
    final double latDrv = _asDouble(data['latTaxista'] ?? data['driverLat']);
    final double lonDrv = _asDouble(data['lonTaxista'] ?? data['driverLon']);

    // uidTaxista/taxistaId compat (si uno viene vacío)
    final String uidTx = _asString(data['uidTaxista']).trim();
    final String taxId = _asString(data['taxistaId']).trim();
    final String uidTaxistaFinal = uidTx.isNotEmpty ? uidTx : taxId;
    final String taxistaIdFinal = taxId.isNotEmpty ? taxId : uidTx;

    // teléfono compat: algunos flujos guardan "telefonoTaxista"
    final String tel = _asString(data['telefonoTaxista']).trim().isNotEmpty
        ? _asString(data['telefonoTaxista']).trim()
        : _asString(data['telefono']).trim();

    // ============================================
    // ✅ PARSEO DE CAMPOS NUEVOS (con valores por defecto)
    // ============================================
    final String tipoServicioRaw = _asString(data['tipoServicio']);
    final String tipoServicioFinal =
        tipoServicioRaw.isEmpty ? 'normal' : tipoServicioRaw;

    final String subtipoTurismoRaw = _asString(data['subtipoTurismo']);

    final String canalAsignacionRaw = _asString(data['canalAsignacion']);
    final String canalAsignacionFinal =
        canalAsignacionRaw.isEmpty ? 'pool' : canalAsignacionRaw;

    final String? catalogoId = data['catalogoTurismoId']?.toString();

    // ✅ NUEVO: origenGeoPoint
    final geo = data['origenGeoPoint'];
    final origenGeoPoint = geo is GeoPoint ? geo : null;

    // 🔥 NUEVO: código de verificación
    final String? codigoVerif = _primerCodigoVerificacion(data);
    final bool codigoVerifOk = _asBool(data['codigoVerificado']);

    // ✅ NUEVO: waypoints
    final List<Map<String, dynamic>>? waypoints = data['waypoints'] is List
        ? List<Map<String, dynamic>>.from(data['waypoints'])
        : null;

    // 👇 NUEVO: extras
    final Map<String, dynamic>? extras = data['extras'] is Map
        ? Map<String, dynamic>.from(data['extras'])
        : null;

    return Viaje(
      id: id,
      clienteId: _asString(data['clienteId']),
      uidCliente: _asString(data['uidCliente']),
      uidTaxista: uidTaxistaFinal,
      taxistaId: taxistaIdFinal,
      nombreTaxista: _asString(data['nombreTaxista']),
      origen: _asString(data['origen']),
      destino: _asString(data['destino']),
      latCliente: cliOk ? latCli : latOri,
      lonCliente: cliOk ? lonCli : lonOri,
      latDestino: _asDouble(data['latDestino']),
      lonDestino: _asDouble(data['lonDestino']),
      latTaxista: latDrv,
      lonTaxista: lonDrv,
      precio: _asDouble(data['precio']),
      precioFinal: _asDouble(data['precioFinal']),
      comision: _asDouble(data['comision']),
      gananciaTaxista: _asDouble(data['gananciaTaxista']),
      metodoPago: _asString(data['metodoPago']).isEmpty
          ? 'Efectivo'
          : _asString(data['metodoPago']),
      tipoVehiculo: _asString(data['tipoVehiculo']).isEmpty
          ? 'Carro'
          : _asString(data['tipoVehiculo']),
      marca: _asString(data['marca']),
      modelo: _asString(data['modelo']),
      color: _asString(data['color']),
      idaYVuelta: _asBool(data['idaYVuelta']),
      telefono: tel,
      placa: _asString(data['placa']),
      estado: estadoNorm,
      aceptado: acept,
      rechazado: _asBool(data['rechazado']),
      completado: comp,
      calificado: _asBool(data['calificado']),
      calificacion: _asDouble(data['calificacion']),
      comentario: _asString(data['comentario']),
      fechaHora: _asDate(data['fechaHora']),
      esAhora: _asBool(data['esAhora']),
      programado: _asBool(data['programado']),
      acceptAfter: _asDateOrNull(data['acceptAfter']),
      publishAt: _asDateOrNull(data['publishAt']), // 🔥 NUEVO
      startWindowAt: _asDateOrNull(data['startWindowAt']),

      // Nuevos
      tipoServicio: tipoServicioFinal,
      subtipoTurismo: subtipoTurismoRaw,
      canalAsignacion: canalAsignacionFinal,
      catalogoTurismoId: catalogoId,
      origenGeoPoint: origenGeoPoint,

      // 🔥 NUEVOS
      codigoVerificacion: codigoVerif,
      codigoVerificado: codigoVerifOk,

      // ✅ NUEVO: waypoints
      waypoints: waypoints,

      // 👇 NUEVO: extras
      extras: extras,

      inicioEnRutaEn: _asDateOrNull(data['inicioEnRutaEn']),
      viajeIniciadoEn: _asDateOrNull(data['viajeIniciadoEn']),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'clienteId': clienteId,
      'uidCliente': uidCliente,
      'uidTaxista': uidTaxista,
      'taxistaId': taxistaId,
      'nombreTaxista': nombreTaxista,
      'origen': origen,
      'destino': destino,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,

      // compat driver
      'latTaxista': latTaxista,
      'lonTaxista': lonTaxista,
      'driverLat': latTaxista,
      'driverLon': lonTaxista,

      'precio': precio,
      'precioFinal': precioFinal,
      'comision': comision,
      'gananciaTaxista': gananciaTaxista,

      'metodoPago': metodoPago,
      'tipoVehiculo': tipoVehiculo,
      'marca': marca,
      'modelo': modelo,
      'color': color,
      'idaYVuelta': idaYVuelta,

      // compat teléfono
      'telefono': telefono,
      'telefonoTaxista': telefono,

      'placa': placa,

      'estado': estado,
      'aceptado': aceptado,
      'rechazado': rechazado,
      'completado': completado,
      'calificado': calificado,
      'calificacion': calificacion,
      'comentario': comentario,

      'fechaHora': Timestamp.fromDate(fechaHora),

      // programados
      'esAhora': esAhora,
      'programado': programado,
      if (acceptAfter != null) 'acceptAfter': Timestamp.fromDate(acceptAfter!),
      if (publishAt != null)
        'publishAt': Timestamp.fromDate(publishAt!), // 🔥 NUEVO
      if (startWindowAt != null)
        'startWindowAt': Timestamp.fromDate(startWindowAt!),

      // 🔥 NUEVOS
      if (codigoVerificacion != null) 'codigoVerificacion': codigoVerificacion,
      'codigoVerificado': codigoVerificado,

      // ✅ NUEVO: waypoints
      if (waypoints != null) 'waypoints': waypoints,

      // 👇 NUEVO: extras
      if (extras != null) 'extras': extras,
    };

    // Nuevos campos
    if (tipoServicio != 'normal') {
      map['tipoServicio'] = tipoServicio;
    }
    if (subtipoTurismo.isNotEmpty) {
      map['subtipoTurismo'] = subtipoTurismo;
    }
    if (canalAsignacion != 'pool') {
      map['canalAsignacion'] = canalAsignacion;
    }
    if (catalogoTurismoId != null) {
      map['catalogoTurismoId'] = catalogoTurismoId;
    }
    if (origenGeoPoint != null) {
      map['origenGeoPoint'] = origenGeoPoint;
    }

    return map;
  }

  /// Mapa recomendado para CREAR en Firestore (coincide con ViajesRepo)
  Map<String, dynamic> toCreateMap() {
    final now = DateTime.now();

    final bool esAhoraCalc =
        TripPublishWindows.esAhoraPorFechaPickup(fechaHora, now);

    final DateTime publishAtDT = esAhoraCalc
        ? now
        : TripPublishWindows.poolOpensAtForScheduledPickup(fechaHora, now);
    final DateTime acceptAfterDT = esAhoraCalc
        ? now
        : TripPublishWindows.acceptAfterForScheduledPickup(fechaHora, now);
    final DateTime startWindowDT = esAhoraCalc
        ? now
        : TripPublishWindows.startWindowAtForScheduledPickup(fechaHora, now);

    // Estado inicial según método de pago
    final String estadoInicial = (metodoPago.toLowerCase().trim() == 'tarjeta')
        ? EstadosViaje.pendientePago
        : EstadosViaje.pendiente;

    // Determinar canal de asignación automáticamente
    final String tipoServicioFinal =
        tipoServicio.isEmpty ? 'normal' : tipoServicio;
    final bool esTurismo = tipoServicioFinal == 'turismo';
    final String canalAsignacionFinal = esTurismo ? 'admin' : 'pool';

    // 🔥 Generar código de verificación de 6 dígitos
    final String codigoVerif =
        (100000 + (now.millisecondsSinceEpoch % 900000)).toString();

    return {
      'uidCliente': uidCliente.isNotEmpty ? uidCliente : clienteId,
      'clienteId': clienteId.isNotEmpty ? clienteId : uidCliente,

      // Estado inicial y flags
      'estado': estadoInicial,
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'activo': esAhoraCalc,
      'esAhora': esAhoraCalc,
      'programado': !esAhoraCalc,
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'publishAt': Timestamp.fromDate(publishAtDT), // 🔥 NUEVO
      'startWindowAt': Timestamp.fromDate(startWindowDT),

      // Trayecto
      'origen': origen,
      'destino': destino,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,

      // compat
      'latOrigen': latCliente,
      'lonOrigen': lonCliente,

      // GeoPoint para consultas espaciales
      'origenGeoPoint': GeoPoint(latCliente, lonCliente),

      // Fecha/hora del servicio
      'fechaHora': Timestamp.fromDate(fechaHora),

      // Pago / vehículo
      'precio': precio,
      'metodoPago': metodoPago,
      'tipoVehiculo': tipoVehiculo,
      if (marca.isNotEmpty) 'marca': marca,
      if (modelo.isNotEmpty) 'modelo': modelo,
      if (color.isNotEmpty) 'color': color,
      'idaYVuelta': idaYVuelta,

      // Aún sin taxista
      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'telefonoTaxista': '',
      'placa': '',

      // Pool
      'reservadoPor': '',
      'reservadoHasta': null,
      'ignoradosPor': <String>[],

      // Tracking inicial
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,

      // Campos nuevos
      'tipoServicio': tipoServicioFinal,
      'canalAsignacion': canalAsignacionFinal,
      if (subtipoTurismo.isNotEmpty) 'subtipoTurismo': subtipoTurismo,
      if (catalogoTurismoId != null) 'catalogoTurismoId': catalogoTurismoId,

      // 🔥 NUEVOS - Código de verificación
      'codigoVerificacion': codigoVerif,
      'codigoVerificado': false,

      // ✅ NUEVO: waypoints (se agregarán externamente si existen)
      // No se incluyen aquí porque se añaden en ViajesRepo.crearViajePendiente

      // 👇 NUEVO: extras (se agregarán externamente)
      // No se incluyen aquí porque se añaden en ViajesRepo.crearViajePendiente

      // Timestamps
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
  }

  Viaje copyWith({
    String? id,
    String? clienteId,
    String? uidCliente,
    String? uidTaxista,
    String? taxistaId,
    String? nombreTaxista,
    String? origen,
    String? destino,
    double? latCliente,
    double? lonCliente,
    double? latDestino,
    double? lonDestino,
    double? latTaxista,
    double? lonTaxista,
    double? precio,
    double? precioFinal,
    double? comision,
    double? gananciaTaxista,
    String? metodoPago,
    String? tipoVehiculo,
    String? marca,
    String? modelo,
    String? color,
    bool? idaYVuelta,
    String? telefono,
    String? placa,
    String? estado,
    bool? aceptado,
    bool? rechazado,
    bool? completado,
    bool? calificado,
    double? calificacion,
    String? comentario,
    DateTime? fechaHora,
    bool? esAhora,
    bool? programado,
    DateTime? acceptAfter,
    DateTime? publishAt, // 🔥 NUEVO
    DateTime? startWindowAt,
    String? tipoServicio,
    String? subtipoTurismo,
    String? canalAsignacion,
    String? catalogoTurismoId,
    GeoPoint? origenGeoPoint,
    // 🔥 NUEVOS
    String? codigoVerificacion,
    bool? codigoVerificado,
    // ✅ NUEVO: waypoints
    List<Map<String, dynamic>>? waypoints,
    // 👇 NUEVO: extras
    Map<String, dynamic>? extras,
    DateTime? inicioEnRutaEn,
    DateTime? viajeIniciadoEn,
  }) {
    return Viaje(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      uidCliente: uidCliente ?? this.uidCliente,
      uidTaxista: uidTaxista ?? this.uidTaxista,
      taxistaId: taxistaId ?? this.taxistaId,
      nombreTaxista: nombreTaxista ?? this.nombreTaxista,
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      latCliente: latCliente ?? this.latCliente,
      lonCliente: lonCliente ?? this.lonCliente,
      latDestino: latDestino ?? this.latDestino,
      lonDestino: lonDestino ?? this.lonDestino,
      latTaxista: latTaxista ?? this.latTaxista,
      lonTaxista: lonTaxista ?? this.lonTaxista,
      precio: precio ?? this.precio,
      precioFinal: precioFinal ?? this.precioFinal,
      comision: comision ?? this.comision,
      gananciaTaxista: gananciaTaxista ?? this.gananciaTaxista,
      metodoPago: metodoPago ?? this.metodoPago,
      tipoVehiculo: tipoVehiculo ?? this.tipoVehiculo,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      color: color ?? this.color,
      idaYVuelta: idaYVuelta ?? this.idaYVuelta,
      telefono: telefono ?? this.telefono,
      placa: placa ?? this.placa,
      estado: estado ?? this.estado,
      aceptado: aceptado ?? this.aceptado,
      rechazado: rechazado ?? this.rechazado,
      completado: completado ?? this.completado,
      calificado: calificado ?? this.calificado,
      calificacion: calificacion ?? this.calificacion,
      comentario: comentario ?? this.comentario,
      fechaHora: fechaHora ?? this.fechaHora,
      esAhora: esAhora ?? this.esAhora,
      programado: programado ?? this.programado,
      acceptAfter: acceptAfter ?? this.acceptAfter,
      publishAt: publishAt ?? this.publishAt, // 🔥 NUEVO
      startWindowAt: startWindowAt ?? this.startWindowAt,
      tipoServicio: tipoServicio ?? this.tipoServicio,
      subtipoTurismo: subtipoTurismo ?? this.subtipoTurismo,
      canalAsignacion: canalAsignacion ?? this.canalAsignacion,
      catalogoTurismoId: catalogoTurismoId ?? this.catalogoTurismoId,
      origenGeoPoint: origenGeoPoint ?? this.origenGeoPoint,
      // 🔥 NUEVOS
      codigoVerificacion: codigoVerificacion ?? this.codigoVerificacion,
      codigoVerificado: codigoVerificado ?? this.codigoVerificado,
      // ✅ NUEVO: waypoints
      waypoints: waypoints ?? this.waypoints,
      // 👇 NUEVO: extras
      extras: extras ?? this.extras,
      inicioEnRutaEn: inicioEnRutaEn ?? this.inicioEnRutaEn,
      viajeIniciadoEn: viajeIniciadoEn ?? this.viajeIniciadoEn,
    );
  }
}
