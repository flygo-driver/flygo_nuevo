// lib/modelo/viaje.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/calculos/estados.dart';

/// Modelo de Viaje usado en la app (cliente y taxista).
class Viaje {
  final String id;

  // Identidad (cliente/taxista)
  final String clienteId;   // legacy / compat
  final String uidCliente;  // preferido
  final String uidTaxista;
  final String taxistaId;   // compat
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
  final double precio;              // precio estimado
  final double precioFinal;         // precio final (si aplica)
  final double comision;            // info de UI / contable
  final double gananciaTaxista;     // info de UI / contable

  // Preferencias
  final String metodoPago;          // 'Efectivo' | 'Transferencia' | 'Tarjeta'
  final String tipoVehiculo;        // 'Carro' | 'Jeepeta' | etc.
  final String marca;
  final String modelo;
  final String color;
  final bool idaYVuelta;
  final String telefono;
  final String placa;

  // Estado
  final String estado;              // normalizado
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
  final bool esAhora;               // calculado al crear
  final bool programado;            // !esAhora
  final DateTime? acceptAfter;      // desde cuándo se puede aceptar (ej. 2h antes)
  final DateTime? startWindowAt;    // ventana para iniciar el viaje (ej. 45m antes)

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

    // nuevos
    this.esAhora = false,
    this.programado = false,
    this.acceptAfter,
    this.startWindowAt,
  }) : fechaHora = fechaHora ?? DateTime.now();

  // === Getters de compatibilidad para la UI (parches mínimos) ===
  String get telefonoTaxista => telefono; // alias esperado por algunas vistas
  double get driverLat => latTaxista;     // alias
  double get driverLon => lonTaxista;     // alias

  // === Getters de utilidad ===
  bool get tienePickup => _validCoord(latCliente, lonCliente);
  bool get tieneDestino => _validCoord(latDestino, lonDestino);
  bool get esActivo => EstadosViaje.esActivo(estado);
  bool get esTerminal => EstadosViaje.esTerminal(estado);

  bool esProgramadoLiberable(DateTime now) {
    if (acceptAfter == null) return true;
    return !now.isBefore(acceptAfter!);
  }

  // === Helpers de presentación / disponibilidad ===
  bool get hasTelefono => telefono.trim().isNotEmpty;
  bool get hasPickup => _validCoord(latCliente, lonCliente);
  bool get hasDestino => _validCoord(latDestino, lonDestino);
  bool get hasDriverPos => _validCoord(latTaxista, lonTaxista);

  /// Resumen listo para pintar en la tarjeta de la UI
  String get vehiculoResumen {
    final partes = <String>[
      if (tipoVehiculo.trim().isNotEmpty) tipoVehiculo.trim(),
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
    final norma = digits.startsWith('1') ? digits : (digits.length == 10 ? '1$digits' : digits);
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
      try { return DateTime.parse(v); } catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _asDateOrNull(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try { return DateTime.parse(v); } catch (_) { return null; }
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
    final bool comp  = _asBool(data['completado']);

    final String estadoNorm = EstadosViaje.normalizar(
      rawEstado.isEmpty
          ? (comp ? EstadosViaje.completado : (acept ? EstadosViaje.aceptado : EstadosViaje.pendiente))
          : rawEstado,
    );

    // driverLat/driverLon compat
    final double latDrv = _asDouble(data['latTaxista'] ?? data['driverLat']);
    final double lonDrv = _asDouble(data['lonTaxista'] ?? data['driverLon']);

    return Viaje(
      id: id,
      clienteId: _asString(data['clienteId']),
      uidCliente: _asString(data['uidCliente']),
      uidTaxista: _asString(data['uidTaxista']),
      taxistaId: _asString(data['taxistaId']),
      nombreTaxista: _asString(data['nombreTaxista']),
      origen: _asString(data['origen']),
      destino: _asString(data['destino']),
      // usa los valores ya parseados (evita doble parseo)
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
      metodoPago: _asString(data['metodoPago']).isEmpty ? 'Efectivo' : _asString(data['metodoPago']),
      tipoVehiculo: _asString(data['tipoVehiculo']).isEmpty ? 'Carro' : _asString(data['tipoVehiculo']),
      marca: _asString(data['marca']),
      modelo: _asString(data['modelo']),
      color: _asString(data['color']),
      idaYVuelta: _asBool(data['idaYVuelta']),
      telefono: _asString(data['telefono']),
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
      startWindowAt: _asDateOrNull(data['startWindowAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
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
      'telefono': telefono,
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
      if (startWindowAt != null) 'startWindowAt': Timestamp.fromDate(startWindowAt!),
    };
  }

  /// Mapa recomendado para CREAR en Firestore (coincide con ViajesRepo)
  Map<String, dynamic> toCreateMap() {
    final now = DateTime.now();

    // Ventanas de negocio (mismas que usa el repo)
    const int kAcceptHoursBefore = 2;    // reclamar programados desde 2h antes
    const int kReadyMinutesBefore = 45;  // ventana de inicio 45 min antes

    // AHORA si la hora es dentro de 15 minutos
    final bool esAhoraCalc = fechaHora.isBefore(now.add(const Duration(minutes: 15)));

    final DateTime acceptAfterDT =
        esAhoraCalc ? now : fechaHora.subtract(const Duration(hours: kAcceptHoursBefore));
    final DateTime startWindowDT =
        esAhoraCalc ? now : fechaHora.subtract(const Duration(minutes: kReadyMinutesBefore));

    // Estado inicial según método de pago (compat con reglas)
    final String estadoInicial = (metodoPago.toLowerCase().trim() == 'tarjeta')
        ? EstadosViaje.pendientePago
        : EstadosViaje.pendiente;

    return {
      'uidCliente': uidCliente.isNotEmpty ? uidCliente : clienteId,
      'clienteId': clienteId.isNotEmpty ? clienteId : uidCliente,

      // Estado inicial y flags de visibilidad
      'estado': estadoInicial,
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'activo': esAhoraCalc, // ahora = activo; programado = no activo hasta ventana
      'esAhora': esAhoraCalc,
      'programado': !esAhoraCalc,
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
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

      // Scheduling de visibilidad en pools
      // 👇 Publicamos YA para que los programados salgan en “Programados” sin esperar acceptAfter
      'publishAt': Timestamp.fromDate(now),

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

    // nuevos
    bool? esAhora,
    bool? programado,
    DateTime? acceptAfter,
    DateTime? startWindowAt,
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

      // nuevos
      esAhora: esAhora ?? this.esAhora,
      programado: programado ?? this.programado,
      acceptAfter: acceptAfter ?? this.acceptAfter,
      startWindowAt: startWindowAt ?? this.startWindowAt,
    );
  }
}
