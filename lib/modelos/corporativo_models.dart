import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/legal/terms_data.dart';

import 'package:flygo_nuevo/utils/corporativo_recurrencia_helper.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';

/// Causas de pausa / cambio operativo (encargado).
abstract final class CorporativoPausaCausa {
  CorporativoPausaCausa._();

  static const feriado = 'feriado_no_laborable';
  static const pausaTotal = 'pausa_total_ruta';
  static const quitarPasajero = 'quitar_pasajero';
  static const agregarPasajero = 'agregar_pasajero';
  static const reactivar = 'reactivar';

  static String etiqueta(String id) => switch (id) {
        feriado => 'Feriado / no laborable',
        pausaTotal => 'Pausa total de la ruta',
        quitarPasajero => 'Pasajero fuera de la ruta',
        agregarPasajero => 'Pasajero agregado / reactivado',
        reactivar => 'Ruta reactivada',
        _ => id.isEmpty ? '—' : id,
      };

  static String efectoBusqueda(String id) => switch (id) {
        feriado =>
          'Esos días NO se busca el grupo ni se publica el viaje. No se cobra.',
        pausaTotal =>
          'Mientras esté pausada NO se busca a nadie ni se publica. No se cobra.',
        quitarPasajero =>
          'Ese pasajero deja de ir en la ruta; los demás sí se buscan.',
        agregarPasajero =>
          'El pasajero vuelve a la ruta y se busca en los días operativos.',
        reactivar => 'La ruta vuelve a publicarse y se busca el grupo.',
        _ => 'Revisá el estado de la ruta antes de enviar.',
      };
}

/// Datos del encargado guardados en la empresa (admin → encargado coherente).
class CorporativoEncargadoPerfil {
  const CorporativoEncargadoPerfil({
    required this.uid,
    this.nombre = '',
    this.cedula = '',
    this.telefono = '',
    this.email = '',
  });

  final String uid;
  final String nombre;
  final String cedula;
  final String telefono;
  final String email;

  Map<String, dynamic> toMap() => {
        'uid': uid,
        if (nombre.isNotEmpty) 'nombre': nombre,
        if (cedula.isNotEmpty) 'cedula': cedula,
        if (telefono.isNotEmpty) 'telefono': telefono,
        if (email.isNotEmpty) 'email': email,
      };

  static CorporativoEncargadoPerfil? fromMap(dynamic raw, {String? uidFallback}) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final uid = (m['uid'] ?? uidFallback ?? '').toString().trim();
    if (uid.isEmpty) return null;
    return CorporativoEncargadoPerfil(
      uid: uid,
      nombre: (m['nombre'] ?? '').toString().trim(),
      cedula: (m['cedula'] ?? '').toString().trim(),
      telefono: (m['telefono'] ?? '').toString().trim(),
      email: (m['email'] ?? '').toString().trim(),
    );
  }
}

/// Pasajero en plantilla corporativa (activar/desactivar sin borrar).
class CorporativoPasajero {
  CorporativoPasajero({
    required this.id,
    required this.nombre,
    required this.sector,
    required this.referencia,
    required this.destinoLabel,
    required this.lat,
    required this.lon,
    this.horaDejada = '',
    this.orden = 0,
    this.activo = true,
    this.abordado = false,
    this.abordadoEn,
    this.dejadoConfirmado = false,
    this.dejadoEn,
  });

  final String id;
  final String nombre;
  final String sector;
  final String referencia;
  final String destinoLabel;
  final double lat;
  final double lon;
  final String horaDejada;
  final int orden;
  final bool activo;
  final bool abordado;
  final DateTime? abordadoEn;
  final bool dejadoConfirmado;
  final DateTime? dejadoEn;

  CorporativoPasajero copyWith({
    String? id,
    String? nombre,
    String? sector,
    String? referencia,
    String? destinoLabel,
    double? lat,
    double? lon,
    String? horaDejada,
    int? orden,
    bool? activo,
    bool? abordado,
    DateTime? abordadoEn,
    bool? dejadoConfirmado,
    DateTime? dejadoEn,
  }) {
    return CorporativoPasajero(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      sector: sector ?? this.sector,
      referencia: referencia ?? this.referencia,
      destinoLabel: destinoLabel ?? this.destinoLabel,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      horaDejada: horaDejada ?? this.horaDejada,
      orden: orden ?? this.orden,
      activo: activo ?? this.activo,
      abordado: abordado ?? this.abordado,
      abordadoEn: abordadoEn ?? this.abordadoEn,
      dejadoConfirmado: dejadoConfirmado ?? this.dejadoConfirmado,
      dejadoEn: dejadoEn ?? this.dejadoEn,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = (v ?? '').toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'sector': sector,
        'referencia': referencia,
        'destinoLabel': destinoLabel,
        'lat': lat,
        'lon': lon,
        if (horaDejada.isNotEmpty) 'horaDejada': horaDejada,
        if (orden > 0) 'orden': orden,
        'activo': activo,
        if (abordado) 'abordado': true,
        if (abordadoEn != null) 'abordadoEn': abordadoEn!.toIso8601String(),
        if (dejadoConfirmado) 'dejadoConfirmado': true,
        if (dejadoEn != null) 'dejadoEn': dejadoEn!.toIso8601String(),
      };

  static CorporativoPasajero fromMap(Map<String, dynamic> m) {
    return CorporativoPasajero(
      id: (m['id'] ?? '').toString(),
      nombre: (m['nombre'] ?? '').toString(),
      sector: (m['sector'] ?? '').toString(),
      referencia: (m['referencia'] ?? '').toString(),
      destinoLabel: (m['destinoLabel'] ?? m['destino'] ?? '').toString(),
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lon: (m['lon'] as num?)?.toDouble() ?? 0,
      horaDejada: (m['horaDejada'] ?? '').toString(),
      orden: (m['orden'] as num?)?.toInt() ?? 0,
      activo: m['activo'] != false,
      abordado: m['abordado'] == true,
      abordadoEn: _ts(m['abordadoEn']),
      dejadoConfirmado: m['dejadoConfirmado'] == true,
      dejadoEn: _ts(m['dejadoEn']),
    );
  }
}

/// Snapshot del conductor RAI asignado a una ruta (visible para el encargado).
class CorporativoChoferPerfil {
  const CorporativoChoferPerfil({
    required this.uid,
    this.nombre = '',
    this.telefono = '',
    this.email = '',
    this.cedula = '',
    this.placa = '',
    this.marca = '',
    this.modelo = '',
    this.color = '',
    this.anio = '',
    this.tipoVehiculo = '',
    this.documentosVerificados = false,
    this.fotoUrl = '',
    this.asignadoEn,
    this.calificacionPromedio = 0,
    this.aniosExperiencia = 0,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String email;
  final String cedula;
  final String placa;
  final String marca;
  final String modelo;
  final String color;
  final String anio;
  final String tipoVehiculo;
  final bool documentosVerificados;
  final String fotoUrl;
  final DateTime? asignadoEn;
  final double calificacionPromedio;
  final int aniosExperiencia;

  bool get asignado => uid.trim().isNotEmpty;

  String get vehiculoDescripcion {
    final partes = <String>[
      if (marca.isNotEmpty) marca,
      if (modelo.isNotEmpty) modelo,
      if (color.isNotEmpty) color,
      if (anio.isNotEmpty) anio,
    ];
    return partes.join(' · ');
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        if (nombre.isNotEmpty) 'nombre': nombre,
        if (telefono.isNotEmpty) 'telefono': telefono,
        if (email.isNotEmpty) 'email': email,
        if (cedula.isNotEmpty) 'cedula': cedula,
        if (placa.isNotEmpty) 'placa': placa,
        if (marca.isNotEmpty) 'marca': marca,
        if (modelo.isNotEmpty) 'modelo': modelo,
        if (color.isNotEmpty) 'color': color,
        if (anio.isNotEmpty) 'anio': anio,
        if (tipoVehiculo.isNotEmpty) 'tipoVehiculo': tipoVehiculo,
        'documentosVerificados': documentosVerificados,
        if (fotoUrl.isNotEmpty) 'fotoUrl': fotoUrl,
        if (asignadoEn != null) 'asignadoEn': Timestamp.fromDate(asignadoEn!),
        if (calificacionPromedio > 0) 'calificacionPromedio': calificacionPromedio,
        if (aniosExperiencia > 0) 'aniosExperiencia': aniosExperiencia,
      };

  static CorporativoChoferPerfil? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final uid = (m['uid'] ?? '').toString().trim();
    if (uid.isEmpty) return null;
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }
    return CorporativoChoferPerfil(
      uid: uid,
      nombre: (m['nombre'] ?? '').toString().trim(),
      telefono: (m['telefono'] ?? '').toString().trim(),
      email: (m['email'] ?? m['correo'] ?? '').toString().trim(),
      cedula: (m['cedula'] ?? '').toString().trim(),
      placa: (m['placa'] ?? '').toString().trim(),
      marca: (m['marca'] ?? m['vehiculoMarca'] ?? '').toString().trim(),
      modelo: (m['modelo'] ?? m['vehiculoModelo'] ?? '').toString().trim(),
      color: (m['color'] ?? m['vehiculoColor'] ?? '').toString().trim(),
      anio: (m['anio'] ?? m['vehiculoAnio'] ?? '').toString().trim(),
      tipoVehiculo: (m['tipoVehiculo'] ?? '').toString().trim(),
      documentosVerificados: m['documentosVerificados'] == true,
      fotoUrl: (m['fotoUrl'] ?? m['photoURL'] ?? '').toString().trim(),
      asignadoEn: ts(m['asignadoEn']),
      calificacionPromedio: (m['calificacionPromedio'] as num?)?.toDouble() ??
          _ratingDesdeMap(m),
      aniosExperiencia: (m['aniosExperiencia'] as num?)?.toInt() ??
          _aniosDesdeMap(m),
    );
  }

  static double _ratingDesdeMap(Map<String, dynamic> m) {
    final suma = (m['ratingSuma'] as num?)?.toDouble() ?? 0;
    final cnt = (m['ratingConteo'] as num?)?.toInt() ?? 0;
    if (cnt <= 0) return 0;
    return (suma / cnt).clamp(0, 5);
  }

  static int _aniosDesdeMap(Map<String, dynamic> m) {
    DateTime? reg;
    final fr = m['fechaRegistro'];
    if (fr is Timestamp) reg = fr.toDate();
    if (reg == null) return 0;
    return (DateTime.now().difference(reg).inDays / 365).floor().clamp(0, 40);
  }
}

/// Plantilla reutilizable con horario, recurrencia y ruta guardada para navegación.
class CorporativoPlantilla {
  CorporativoPlantilla({
    required this.id,
    required this.empresaId,
    required this.nombre,
    required this.encargadoNombre,
    required this.clienteNombre,
    required this.referencia,
    required this.origenLabel,
    required this.origenLat,
    required this.origenLon,
    required this.pasajeros,
    this.esFijo = false,
    this.publicacionAutomatica = true,
    this.horaRecogidaGrupo = '07:00',
    this.patronRecurrencia = CorporativoPatronRecurrencia.lunVie,
    this.diasSemana = const [1, 2, 3, 4, 5],
    this.fechaAnclaInterdiaria,
    this.fechaInicioServicio,
    this.minutosPublicarAntes = 90,
    this.minutosAvisoChofer = 40,
    this.choferPreferidoUid,
    this.choferPreferidoNombre,
    this.choferPreferidoTelefono,
    this.choferRespaldoUid,
    this.tiempoConfirmacionMin = 30,
    this.politicaSustituto = 'auto',
    this.choferAsignadoPerfil,
    this.precioAcordado = 0,
    this.activa = true,
    this.diasPausaFeriado = const [],
    this.pausaCausa = '',
    this.pausaNota = '',
    this.rutaPuntos = const [],
    this.googleMapsRutaUrl = '',
    this.wazeOrigenUrl = '',
    this.ultimoViajeId,
    this.ultimaNotificacionFijaKey,
    this.ultimaPublicacionFijaKey,
    this.ultimoErrorPublicacion,
    this.ultimoErrorPublicacionEn,
    this.modoInformativo = true,
  });

  final String id;
  final String empresaId;
  final String nombre;
  final String encargadoNombre;
  final String clienteNombre;
  final String referencia;
  final String origenLabel;
  final double origenLat;
  final double origenLon;
  final List<CorporativoPasajero> pasajeros;
  final bool esFijo;
  final bool publicacionAutomatica;
  final String horaRecogidaGrupo;
  final String patronRecurrencia;
  final List<int> diasSemana;
  final String? fechaAnclaInterdiaria;
  /// Primer día calendario en que esta ruta puede publicarse/operar (yyyy-MM-dd).
  final String? fechaInicioServicio;
  final int minutosPublicarAntes;
  final int minutosAvisoChofer;
  final String? choferPreferidoUid;
  final String? choferPreferidoNombre;
  final String? choferPreferidoTelefono;
  final String? choferRespaldoUid;
  final int tiempoConfirmacionMin;
  /// auto | manual | pausar
  final String politicaSustituto;
  final CorporativoChoferPerfil? choferAsignadoPerfil;
  final double precioAcordado;
  final bool activa;
  /// Días yyyy-MM-dd sin operación (feriado / cierre). No se busca el grupo.
  final List<String> diasPausaFeriado;
  /// Última causa elegida por el encargado (feriado, pausa_total, etc.).
  final String pausaCausa;
  final String pausaNota;
  final List<Map<String, dynamic>> rutaPuntos;
  final String googleMapsRutaUrl;
  final String wazeOrigenUrl;
  final String? ultimoViajeId;
  final String? ultimaNotificacionFijaKey;
  final String? ultimaPublicacionFijaKey;
  final String? ultimoErrorPublicacion;
  final DateTime? ultimoErrorPublicacionEn;
  /// Chofer ve lista + copiar direcciones (sin PIN ni navegación in-app).
  final bool modoInformativo;

  /// Compat: campo legacy en Firestore.
  String get horaRecogida => horaRecogidaGrupo;

  List<CorporativoPasajero> get pasajerosActivos {
    final list = pasajeros.where((p) => p.activo).toList();
    list.sort((a, b) {
      final oa = a.orden > 0 ? a.orden : 999;
      final ob = b.orden > 0 ? b.orden : 999;
      return oa.compareTo(ob);
    });
    return list;
  }

  Map<String, dynamic> toMap() => {
        'empresaId': empresaId,
        'nombre': nombre,
        'encargadoNombre': encargadoNombre,
        'clienteNombre': clienteNombre,
        'referencia': referencia,
        'origenLabel': origenLabel,
        'origenLat': origenLat,
        'origenLon': origenLon,
        'pasajeros': pasajeros.map((p) => p.toMap()).toList(),
        'esFijo': esFijo,
        'publicacionAutomatica': publicacionAutomatica,
        'horaRecogidaGrupo':
            normalizarHoraHHmm(horaRecogidaGrupo) ?? horaRecogidaGrupo,
        'horaRecogida':
            normalizarHoraHHmm(horaRecogidaGrupo) ?? horaRecogidaGrupo,
        'patronRecurrencia': patronRecurrencia,
        'diasSemana': CorporativoPatronRecurrencia.diasEfectivos(
          patronRecurrencia,
          diasSemana,
        ),
        if (fechaAnclaInterdiaria != null && fechaAnclaInterdiaria!.isNotEmpty)
          'fechaAnclaInterdiaria': fechaAnclaInterdiaria,
        if (fechaInicioServicio != null && fechaInicioServicio!.isNotEmpty)
          'fechaInicioServicio': fechaInicioServicio,
        'minutosPublicarAntes': minutosPublicarAntes,
        'minutosAvisoChofer': minutosAvisoChofer,
        if (choferPreferidoUid != null && choferPreferidoUid!.isNotEmpty)
          'choferPreferidoUid': choferPreferidoUid,
        if (choferPreferidoNombre != null && choferPreferidoNombre!.isNotEmpty)
          'choferPreferidoNombre': choferPreferidoNombre,
        if (choferPreferidoTelefono != null &&
            choferPreferidoTelefono!.isNotEmpty)
          'choferPreferidoTelefono': choferPreferidoTelefono,
        if (choferRespaldoUid != null && choferRespaldoUid!.isNotEmpty)
          'choferRespaldoUid': choferRespaldoUid,
        'tiempoConfirmacionMin': tiempoConfirmacionMin,
        if (politicaSustituto.isNotEmpty) 'politicaSustituto': politicaSustituto,
        if (choferAsignadoPerfil != null && choferAsignadoPerfil!.asignado)
          'choferAsignadoPerfil': choferAsignadoPerfil!.toMap(),
        'precioAcordado': precioAcordado,
        'activa': activa,
        'diasPausaFeriado': diasPausaFeriado,
        'pausaCausa': pausaCausa,
        'pausaNota': pausaNota,
        if (rutaPuntos.isNotEmpty) 'rutaPuntos': rutaPuntos,
        if (googleMapsRutaUrl.isNotEmpty) 'googleMapsRutaUrl': googleMapsRutaUrl,
        if (wazeOrigenUrl.isNotEmpty) 'wazeOrigenUrl': wazeOrigenUrl,
        if (ultimoViajeId != null && ultimoViajeId!.trim().isNotEmpty)
          'ultimoViajeId': ultimoViajeId!.trim(),
        if (ultimaNotificacionFijaKey != null &&
            ultimaNotificacionFijaKey!.trim().isNotEmpty)
          'ultimaNotificacionFijaKey': ultimaNotificacionFijaKey!.trim(),
        if (ultimaPublicacionFijaKey != null &&
            ultimaPublicacionFijaKey!.trim().isNotEmpty)
          'ultimaPublicacionFijaKey': ultimaPublicacionFijaKey!.trim(),
        if (ultimoErrorPublicacion != null && ultimoErrorPublicacion!.isNotEmpty)
          'ultimoErrorPublicacion': ultimoErrorPublicacion,
        if (ultimoErrorPublicacionEn != null)
          'ultimoErrorPublicacionEn': Timestamp.fromDate(ultimoErrorPublicacionEn!),
        'corporativoModoInformativo': modoInformativo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

  static CorporativoPlantilla fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? {};
    final rawPas = m['pasajeros'];
    final List<CorporativoPasajero> pas = rawPas is List
        ? rawPas
            .whereType<Map>()
            .map((e) => CorporativoPasajero.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <CorporativoPasajero>[];
    final rawDias = m['diasSemana'];
    final dias = rawDias is List
        ? rawDias.map((e) => (e as num).toInt()).toList()
        : <int>[1, 2, 3, 4, 5];
    final rawRuta = m['rutaPuntos'];
    final rutaPuntos = rawRuta is List
        ? rawRuta
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final horaRaw =
        (m['horaRecogidaGrupo'] ?? m['horaRecogida'] ?? '07:00').toString();
    final hora = normalizarHoraHHmm(horaRaw) ?? '07:00';

    return CorporativoPlantilla(
      id: doc.id,
      empresaId: (m['empresaId'] ?? '').toString(),
      nombre: (m['nombre'] ?? '').toString(),
      encargadoNombre: (m['encargadoNombre'] ?? '').toString(),
      clienteNombre: (m['clienteNombre'] ?? '').toString(),
      referencia: (m['referencia'] ?? '').toString(),
      origenLabel: (m['origenLabel'] ?? '').toString(),
      origenLat: (m['origenLat'] as num?)?.toDouble() ?? 0,
      origenLon: (m['origenLon'] as num?)?.toDouble() ?? 0,
      pasajeros: pas,
      esFijo: m['esFijo'] == true,
      publicacionAutomatica: m['publicacionAutomatica'] != false,
      horaRecogidaGrupo: hora,
      patronRecurrencia: (m['patronRecurrencia'] ?? CorporativoPatronRecurrencia.lunVie)
          .toString(),
      diasSemana: dias,
      fechaAnclaInterdiaria:
          (m['fechaAnclaInterdiaria'] ?? '').toString().trim().isEmpty
              ? null
              : (m['fechaAnclaInterdiaria'] ?? '').toString(),
      fechaInicioServicio:
          (m['fechaInicioServicio'] ?? '').toString().trim().isEmpty
              ? null
              : (m['fechaInicioServicio'] ?? '').toString(),
      minutosPublicarAntes: (m['minutosPublicarAntes'] as num?)?.toInt() ?? 90,
      minutosAvisoChofer: (m['minutosAvisoChofer'] as num?)?.toInt() ?? 40,
      choferPreferidoUid: _optStr(m['choferPreferidoUid']),
      choferPreferidoNombre: _optStr(m['choferPreferidoNombre']),
      choferPreferidoTelefono: _optStr(m['choferPreferidoTelefono']),
      choferRespaldoUid: _optStr(m['choferRespaldoUid']),
      tiempoConfirmacionMin: (m['tiempoConfirmacionMin'] as num?)?.toInt() ?? 30,
      politicaSustituto: (m['politicaSustituto'] ?? 'auto').toString(),
      choferAsignadoPerfil: CorporativoChoferPerfil.fromMap(
        m['choferAsignadoPerfil'],
      ),
      precioAcordado: (m['precioAcordado'] as num?)?.toDouble() ?? 0,
      activa: m['activa'] != false,
      diasPausaFeriado: () {
        final raw = m['diasPausaFeriado'];
        if (raw is! List) return <String>[];
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.length >= 8)
            .toList();
      }(),
      pausaCausa: (m['pausaCausa'] ?? '').toString(),
      pausaNota: (m['pausaNota'] ?? '').toString(),
      rutaPuntos: rutaPuntos,
      googleMapsRutaUrl: (m['googleMapsRutaUrl'] ?? '').toString(),
      wazeOrigenUrl: (m['wazeOrigenUrl'] ?? '').toString(),
      ultimoViajeId: _optStr(m['ultimoViajeId']),
      ultimaNotificacionFijaKey: _optStr(m['ultimaNotificacionFijaKey']),
      ultimaPublicacionFijaKey: _optStr(m['ultimaPublicacionFijaKey']),
      ultimoErrorPublicacion: _optStr(m['ultimoErrorPublicacion']),
      ultimoErrorPublicacionEn: (m['ultimoErrorPublicacionEn'] as Timestamp?)?.toDate(),
      modoInformativo: m['corporativoModoInformativo'] != false,
    );
  }

  static String? _optStr(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  CorporativoPlantilla copyWith({
    String? choferPreferidoUid,
    String? choferPreferidoNombre,
    String? choferPreferidoTelefono,
    String? choferRespaldoUid,
    int? tiempoConfirmacionMin,
    String? politicaSustituto,
    CorporativoChoferPerfil? choferAsignadoPerfil,
    double? precioAcordado,
    List<Map<String, dynamic>>? rutaPuntos,
    String? googleMapsRutaUrl,
    String? wazeOrigenUrl,
  }) {
    return CorporativoPlantilla(
      id: id,
      empresaId: empresaId,
      nombre: nombre,
      encargadoNombre: encargadoNombre,
      clienteNombre: clienteNombre,
      referencia: referencia,
      origenLabel: origenLabel,
      origenLat: origenLat,
      origenLon: origenLon,
      pasajeros: pasajeros,
      esFijo: esFijo,
      publicacionAutomatica: publicacionAutomatica,
      horaRecogidaGrupo: horaRecogidaGrupo,
      patronRecurrencia: patronRecurrencia,
      diasSemana: diasSemana,
      fechaAnclaInterdiaria: fechaAnclaInterdiaria,
      fechaInicioServicio: fechaInicioServicio,
      minutosPublicarAntes: minutosPublicarAntes,
      minutosAvisoChofer: minutosAvisoChofer,
      choferPreferidoUid: choferPreferidoUid ?? this.choferPreferidoUid,
      choferPreferidoNombre:
          choferPreferidoNombre ?? this.choferPreferidoNombre,
      choferPreferidoTelefono:
          choferPreferidoTelefono ?? this.choferPreferidoTelefono,
      choferRespaldoUid: choferRespaldoUid ?? this.choferRespaldoUid,
      tiempoConfirmacionMin: tiempoConfirmacionMin ?? this.tiempoConfirmacionMin,
      politicaSustituto: politicaSustituto ?? this.politicaSustituto,
      choferAsignadoPerfil: choferAsignadoPerfil ?? this.choferAsignadoPerfil,
      precioAcordado: precioAcordado ?? this.precioAcordado,
      activa: activa,
      diasPausaFeriado: diasPausaFeriado,
      pausaCausa: pausaCausa,
      pausaNota: pausaNota,
      rutaPuntos: rutaPuntos ?? this.rutaPuntos,
      googleMapsRutaUrl: googleMapsRutaUrl ?? this.googleMapsRutaUrl,
      wazeOrigenUrl: wazeOrigenUrl ?? this.wazeOrigenUrl,
      ultimoViajeId: ultimoViajeId,
      ultimaNotificacionFijaKey: ultimaNotificacionFijaKey,
      ultimaPublicacionFijaKey: ultimaPublicacionFijaKey,
      ultimoErrorPublicacion: ultimoErrorPublicacion,
      ultimoErrorPublicacionEn: ultimoErrorPublicacionEn,
      modoInformativo: modoInformativo,
    );
  }
}

class CorporativoEmpresa {
  CorporativoEmpresa({
    required this.id,
    required this.nombre,
    required this.encargadoUids,
    this.tipoDocumento = 'rnc',
    this.documentoLegal = '',
    this.telefonoEmpresa = '',
    this.emailEmpresa = '',
    this.direccion = '',
    this.encargadosPerfil = const {},
    this.facturacionCicloDias = 15,
    this.formaPagoRai = '',
    this.activa = true,
    this.contratoActivo = false,
    this.contratoDesde,
    this.contratoHasta,
    this.periodoActual,
    this.tarifaViajeContratadaRd = 0,
    this.contratoCorporativoAceptado = false,
    this.contratoCorporativoVersion = '',
    this.logoUrl = '',
  });

  final String id;
  final String nombre;
  final List<String> encargadoUids;
  /// `rnc` o `cedula` (empresa o persona física).
  final String tipoDocumento;
  final String documentoLegal;
  final String telefonoEmpresa;
  final String emailEmpresa;
  final String direccion;
  final Map<String, CorporativoEncargadoPerfil> encargadosPerfil;
  final int facturacionCicloDias;
  /// Cómo la empresa suele pagar a RAI: transferencia|deposito|cheque|efectivo|otro.
  final String formaPagoRai;
  final bool activa;
  /// Contrato RAI activo: sin esto no se publican rutas (servicio contratado).
  final bool contratoActivo;
  final DateTime? contratoDesde;
  final DateTime? contratoHasta;
  final CorporativoPeriodoActual? periodoActual;
  /// Tarifa por viaje acordada empresa ↔ RAI (e-CF al cierre del período).
  final double tarifaViajeContratadaRd;
  /// Aceptación digital del contrato corporativo v1 (encargado).
  final bool contratoCorporativoAceptado;
  final String contratoCorporativoVersion;
  /// Logo corporativo (URL en Firebase Storage).
  final String logoUrl;

  bool get tieneLogo => logoUrl.trim().isNotEmpty;

  bool get contratoDigitalFirmado {
    if (!contratoCorporativoAceptado) return false;
    return contratoCorporativoVersion.trim() == kCorporativoContractVersion;
  }

  bool get contratoVigente {
    if (!activa || !contratoActivo) return false;
    if (contratoHasta == null) return true;
    return !contratoHasta!.isBefore(DateTime.now());
  }

  String get etiquetaDocumento =>
      tipoDocumento.trim().toLowerCase() == 'cedula' ? 'Cédula' : 'RNC';

  CorporativoEncargadoPerfil? perfilEncargado(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return null;
    return encargadosPerfil[id];
  }

  /// Encargados con nombre visible (perfil guardado en la empresa).
  List<CorporativoEncargadoPerfil> get encargadosConPerfil {
    final out = <CorporativoEncargadoPerfil>[];
    for (final uid in encargadoUids) {
      final p = perfilEncargado(uid);
      if (p != null) {
        out.add(p);
      } else {
        out.add(CorporativoEncargadoPerfil(uid: uid));
      }
    }
    return out;
  }

  String get resumenEncargados {
    if (encargadoUids.isEmpty) return 'Sin encargado vinculado';
    final parts = encargadosConPerfil.map((p) {
      final nombre = p.nombre.trim().isNotEmpty ? p.nombre.trim() : 'Sin nombre en perfil';
      final tel = p.telefono.trim();
      final email = p.email.trim();
      final extra = [
        if (tel.isNotEmpty) tel,
        if (email.isNotEmpty) email,
      ].join(' · ');
      return extra.isEmpty ? nombre : '$nombre · $extra';
    });
    return parts.join('\n');
  }

  /// Referencia sugerida al crear rutas (RNC/cédula de la empresa).
  String get referenciaRutas {
    final doc = documentoLegal.trim();
    if (doc.isEmpty) return '';
    return '$etiquetaDocumento $doc';
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'encargadoUids': encargadoUids,
        if (tipoDocumento.isNotEmpty) 'tipoDocumento': tipoDocumento,
        if (documentoLegal.isNotEmpty) 'documentoLegal': documentoLegal,
        if (telefonoEmpresa.isNotEmpty) 'telefonoEmpresa': telefonoEmpresa,
        if (emailEmpresa.isNotEmpty) 'emailEmpresa': emailEmpresa,
        if (direccion.isNotEmpty) 'direccion': direccion,
        if (logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (encargadosPerfil.isNotEmpty)
          'encargadosPerfil': encargadosPerfil.map(
            (k, v) => MapEntry(k, v.toMap()),
          ),
        'facturacionCicloDias': facturacionCicloDias,
        if (formaPagoRai.isNotEmpty) 'formaPagoRai': formaPagoRai,
        'activa': activa,
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

  static CorporativoEmpresa fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? {};
    final raw = m['encargadoUids'];
    final uids = raw is List
        ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final rawPerfiles = m['encargadosPerfil'];
    final perfiles = <String, CorporativoEncargadoPerfil>{};
    if (rawPerfiles is Map) {
      rawPerfiles.forEach((key, value) {
        final p = CorporativoEncargadoPerfil.fromMap(
          value,
          uidFallback: key.toString(),
        );
        if (p != null) perfiles[p.uid] = p;
      });
    }
    return CorporativoEmpresa(
      id: doc.id,
      nombre: (m['nombre'] ?? '').toString(),
      encargadoUids: uids,
      tipoDocumento: (m['tipoDocumento'] ?? 'rnc').toString(),
      documentoLegal: (m['documentoLegal'] ?? m['rnc'] ?? '').toString(),
      telefonoEmpresa: (m['telefonoEmpresa'] ?? '').toString(),
      emailEmpresa: (m['emailEmpresa'] ?? '').toString(),
      direccion: (m['direccion'] ?? '').toString(),
      encargadosPerfil: perfiles,
      facturacionCicloDias: (m['facturacionCicloDias'] as num?)?.toInt() ?? 15,
      formaPagoRai: (m['formaPagoRai'] ?? m['metodoPagoPreferido'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      activa: m['activa'] != false,
      contratoActivo: m['contratoActivo'] == true,
      contratoDesde: _ts(m['contratoDesde']),
      contratoHasta: _ts(m['contratoHasta']),
      periodoActual: CorporativoPeriodoActual.fromMap(
        m['periodoActual'] is Map
            ? Map<String, dynamic>.from(m['periodoActual'] as Map)
            : null,
      ),
      tarifaViajeContratadaRd:
          (m['tarifaViajeContratadaRd'] as num?)?.toDouble() ?? 0,
      contratoCorporativoAceptado: m['contratoCorporativoAceptado'] == true,
      contratoCorporativoVersion:
          (m['contratoCorporativoVersion'] ?? '').toString(),
      logoUrl: (m['logoUrl'] ?? m['logo'] ?? '').toString().trim(),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

/// Resumen del período de facturación en curso (acumulado por chofer).
class CorporativoPeriodoChofer {
  const CorporativoPeriodoChofer({
    required this.uid,
    required this.nombre,
    required this.viajes,
    required this.montoRd,
  });

  final String uid;
  final String nombre;
  final int viajes;
  final double montoRd;

  static CorporativoPeriodoChofer fromEntry(String uid, Map<String, dynamic> m) {
    return CorporativoPeriodoChofer(
      uid: uid,
      nombre: (m['nombre'] ?? 'Chofer').toString(),
      viajes: (m['viajes'] as num?)?.toInt() ?? 0,
      montoRd: (m['montoRd'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CorporativoPeriodoActual {
  const CorporativoPeriodoActual({
    this.inicio,
    this.fin,
    this.viajesCount = 0,
    this.montoTotalRd = 0,
    this.porChofer = const {},
    this.codigoAcceso = '',
    this.codigoVigente = true,
    this.estadoCodigo = 'activo',
    this.pendienteCobro = false,
  });

  final DateTime? inicio;
  final DateTime? fin;
  final int viajesCount;
  final double montoTotalRd;
  final Map<String, CorporativoPeriodoChofer> porChofer;
  /// Mismo código para todos los viajes del período (hasta liquidar).
  final String codigoAcceso;
  final bool codigoVigente;
  final String estadoCodigo;
  final bool pendienteCobro;

  bool get codigoActivo =>
      codigoVigente &&
      estadoCodigo == 'activo' &&
      codigoAcceso.replaceAll(RegExp(r'\D'), '').length == 6 &&
      (fin == null || fin!.isAfter(DateTime.now()));

  static CorporativoPeriodoActual? fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return null;
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final rawChoferes = m['porChofer'];
    final choferes = <String, CorporativoPeriodoChofer>{};
    if (rawChoferes is Map) {
      rawChoferes.forEach((key, value) {
        if (value is Map) {
          choferes[key.toString()] = CorporativoPeriodoChofer.fromEntry(
            key.toString(),
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    return CorporativoPeriodoActual(
      inicio: ts(m['inicio']),
      fin: ts(m['fin']),
      viajesCount: (m['viajesCount'] as num?)?.toInt() ?? 0,
      montoTotalRd: (m['montoTotalRd'] as num?)?.toDouble() ?? 0,
      porChofer: choferes,
      codigoAcceso: (m['codigoAcceso'] ?? '').toString().trim(),
      codigoVigente: m['codigoVigente'] != false,
      estadoCodigo: (m['estadoCodigo'] ?? 'activo').toString(),
      pendienteCobro: m['pendienteCobro'] == true,
    );
  }
}
