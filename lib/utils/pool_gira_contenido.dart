import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Catálogo profesional de inclusiones para Giras por Cupos.
class PoolGiraIncluyeOpcion {
  const PoolGiraIncluyeOpcion(this.label, this.icon);
  final String label;
  final IconData icon;
}

class PoolGiraItinerarioItem {
  const PoolGiraItinerarioItem({required this.hora, required this.actividad});
  final String hora;
  final String actividad;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'hora': hora.trim(),
        'actividad': actividad.trim(),
      };

  static PoolGiraItinerarioItem? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final h = (raw['hora'] ?? '').toString().trim();
    final a = (raw['actividad'] ?? '').toString().trim();
    if (h.isEmpty && a.isEmpty) return null;
    return PoolGiraItinerarioItem(hora: h, actividad: a);
  }
}

/// Punto del recorrido de recogida: el chofer pasa por varios lugares a
/// diferentes horas antes de salir al destino (ej. 4:30am Lucerna, 6am Megacentro).
class PoolGiraPuntoRecogida {
  const PoolGiraPuntoRecogida({required this.hora, required this.lugar});
  final String hora;
  final String lugar;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'hora': hora.trim(),
        'lugar': lugar.trim(),
      };

  static PoolGiraPuntoRecogida? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final h = (raw['hora'] ?? '').toString().trim();
    final l = (raw['lugar'] ?? '').toString().trim();
    if (h.isEmpty && l.isEmpty) return null;
    return PoolGiraPuntoRecogida(hora: h, lugar: l);
  }
}

/// Campos extendidos de contenido (Firestore en `viajes_pool`).
class PoolGiraContenidoExtra {
  const PoolGiraContenidoExtra({
    this.nombreGira = '',
    this.eslogan = '',
    this.provincia = '',
    this.municipio = '',
    this.duracionTexto = '',
    this.direccionExacta = '',
    this.referenciaLugar = '',
    this.noIncluye = '',
    this.queDebeLlevar = '',
    this.reglas = '',
    this.observaciones = '',
    this.edadMinima,
    this.ninosPermitidos = true,
    this.mascotasPermitidas = false,
    this.maxAsientosPorCompra = 10,
    this.itinerario = const <PoolGiraItinerarioItem>[],
    this.puntosRecogida = const <PoolGiraPuntoRecogida>[],
  });

  PoolGiraContenidoExtra copyWith({
    String? nombreGira,
    String? eslogan,
    String? provincia,
    String? municipio,
    String? duracionTexto,
    String? direccionExacta,
    String? referenciaLugar,
    String? noIncluye,
    String? queDebeLlevar,
    String? reglas,
    String? observaciones,
    int? edadMinima,
    bool? ninosPermitidos,
    bool? mascotasPermitidas,
    int? maxAsientosPorCompra,
    List<PoolGiraItinerarioItem>? itinerario,
    List<PoolGiraPuntoRecogida>? puntosRecogida,
  }) {
    return PoolGiraContenidoExtra(
      nombreGira: nombreGira ?? this.nombreGira,
      eslogan: eslogan ?? this.eslogan,
      provincia: provincia ?? this.provincia,
      municipio: municipio ?? this.municipio,
      duracionTexto: duracionTexto ?? this.duracionTexto,
      direccionExacta: direccionExacta ?? this.direccionExacta,
      referenciaLugar: referenciaLugar ?? this.referenciaLugar,
      noIncluye: noIncluye ?? this.noIncluye,
      queDebeLlevar: queDebeLlevar ?? this.queDebeLlevar,
      reglas: reglas ?? this.reglas,
      observaciones: observaciones ?? this.observaciones,
      edadMinima: edadMinima ?? this.edadMinima,
      ninosPermitidos: ninosPermitidos ?? this.ninosPermitidos,
      mascotasPermitidas: mascotasPermitidas ?? this.mascotasPermitidas,
      maxAsientosPorCompra: maxAsientosPorCompra ?? this.maxAsientosPorCompra,
      itinerario: itinerario ?? this.itinerario,
      puntosRecogida: puntosRecogida ?? this.puntosRecogida,
    );
  }

  final String nombreGira;
  final String eslogan;
  final String provincia;
  final String municipio;
  final String duracionTexto;
  final String direccionExacta;
  final String referenciaLugar;
  final String noIncluye;
  final String queDebeLlevar;
  final String reglas;
  final String observaciones;
  final int? edadMinima;
  final bool ninosPermitidos;
  final bool mascotasPermitidas;
  final int maxAsientosPorCompra;
  final List<PoolGiraItinerarioItem> itinerario;
  final List<PoolGiraPuntoRecogida> puntosRecogida;

  Map<String, dynamic> toFirestore() {
    final m = <String, dynamic>{};
    void str(String k, String v) {
      final t = v.trim();
      if (t.isNotEmpty) m[k] = t;
    }

    str('nombreGira', nombreGira);
    str('eslogan', eslogan);
    str('provincia', provincia);
    str('municipio', municipio);
    str('duracionTexto', duracionTexto);
    str('direccionExacta', direccionExacta);
    str('referenciaLugar', referenciaLugar);
    str('noIncluye', noIncluye);
    str('queDebeLlevar', queDebeLlevar);
    str('reglas', reglas);
    str('observaciones', observaciones);
    if (edadMinima != null && edadMinima! > 0) m['edadMinima'] = edadMinima;
    m['ninosPermitidos'] = ninosPermitidos;
    m['mascotasPermitidas'] = mascotasPermitidas;
    if (maxAsientosPorCompra > 0) {
      m['maxAsientosPorCompra'] = maxAsientosPorCompra;
    }
    if (itinerario.isNotEmpty) {
      m['itinerario'] = itinerario.map((e) => e.toMap()).toList();
    }
    if (puntosRecogida.isNotEmpty) {
      m['puntosRecogida'] = puntosRecogida.map((e) => e.toMap()).toList();
    }
    return m;
  }

  static PoolGiraContenidoExtra fromMap(Map<String, dynamic> d) {
    final List<PoolGiraItinerarioItem> it = <PoolGiraItinerarioItem>[];
    final rawIt = d['itinerario'];
    if (rawIt is List) {
      for (final item in rawIt) {
        final parsed = PoolGiraItinerarioItem.fromMap(item);
        if (parsed != null) it.add(parsed);
      }
    }
    final List<PoolGiraPuntoRecogida> pr = <PoolGiraPuntoRecogida>[];
    final rawPr = d['puntosRecogida'];
    if (rawPr is List) {
      for (final item in rawPr) {
        final parsed = PoolGiraPuntoRecogida.fromMap(item);
        if (parsed != null) pr.add(parsed);
      }
    }
    return PoolGiraContenidoExtra(
      nombreGira: (d['nombreGira'] ?? '').toString(),
      eslogan: (d['eslogan'] ?? '').toString(),
      provincia: (d['provincia'] ?? '').toString(),
      municipio: (d['municipio'] ?? '').toString(),
      duracionTexto: (d['duracionTexto'] ?? '').toString(),
      direccionExacta: (d['direccionExacta'] ?? '').toString(),
      referenciaLugar: (d['referenciaLugar'] ?? '').toString(),
      noIncluye: (d['noIncluye'] ?? '').toString(),
      queDebeLlevar: (d['queDebeLlevar'] ?? '').toString(),
      reglas: (d['reglas'] ?? '').toString(),
      observaciones: (d['observaciones'] ?? '').toString(),
      edadMinima: d['edadMinima'] is num ? (d['edadMinima'] as num).toInt() : null,
      ninosPermitidos: d['ninosPermitidos'] != false,
      mascotasPermitidas: d['mascotasPermitidas'] == true,
      maxAsientosPorCompra: d['maxAsientosPorCompra'] is num
          ? (d['maxAsientosPorCompra'] as num).toInt().clamp(1, 99)
          : 10,
      itinerario: it,
      puntosRecogida: pr,
    );
  }
}

class PoolGiraContenidoCatalog {
  PoolGiraContenidoCatalog._();

  static const List<PoolGiraIncluyeOpcion> incluyeOpciones = <PoolGiraIncluyeOpcion>[
    PoolGiraIncluyeOpcion('Transporte', Icons.directions_bus_filled_outlined),
    PoolGiraIncluyeOpcion('Aire acondicionado', Icons.ac_unit_outlined),
    PoolGiraIncluyeOpcion('Refrigerios', Icons.cookie_outlined),
    PoolGiraIncluyeOpcion('Agua', Icons.water_drop_outlined),
    PoolGiraIncluyeOpcion('Refrescos', Icons.local_drink_outlined),
    PoolGiraIncluyeOpcion('Jugos', Icons.emoji_food_beverage_outlined),
    PoolGiraIncluyeOpcion('Tragos', Icons.wine_bar_outlined),
    PoolGiraIncluyeOpcion('Desayuno', Icons.free_breakfast_outlined),
    PoolGiraIncluyeOpcion('Almuerzo', Icons.lunch_dining_outlined),
    PoolGiraIncluyeOpcion('Cena', Icons.dinner_dining_outlined),
    PoolGiraIncluyeOpcion('Entrada', Icons.confirmation_number_outlined),
    PoolGiraIncluyeOpcion('Guía turístico', Icons.tour_outlined),
    PoolGiraIncluyeOpcion('Fotos', Icons.photo_camera_outlined),
    PoolGiraIncluyeOpcion('Videos', Icons.videocam_outlined),
    PoolGiraIncluyeOpcion('Música', Icons.music_note_outlined),
    PoolGiraIncluyeOpcion('Nevera', Icons.kitchen_outlined),
    PoolGiraIncluyeOpcion('Hielo', Icons.severe_cold_outlined),
    PoolGiraIncluyeOpcion('Botiquín', Icons.medical_services_outlined),
    PoolGiraIncluyeOpcion('Seguro', Icons.health_and_safety_outlined),
    PoolGiraIncluyeOpcion('Juegos', Icons.sports_esports_outlined),
    PoolGiraIncluyeOpcion('Rifas', Icons.card_giftcard_outlined),
    PoolGiraIncluyeOpcion('Souvenir', Icons.shopping_bag_outlined),
  ];

  static IconData iconoParaIncluye(String label) {
    final t = label.trim().toLowerCase();
    for (final o in incluyeOpciones) {
      if (o.label.toLowerCase() == t) return o.icon;
    }
    return Icons.check_circle_outline;
  }

  /// Etiqueta de estado visible para el cliente.
  static String estadoGiraCliente({
    required String estado,
    required int cuposDisponibles,
    required int capacidad,
  }) {
    final e = estado.trim().toLowerCase();
    if (e == 'cancelado' || e == 'cancelado_por_admin') return 'Cancelada';
    if (e == 'finalizado') return 'Finalizada';
    if (cuposDisponibles <= 0 || e == 'lleno') return 'Agotada';
    if (esUltimosCupos(cuposDisponibles, capacidad)) return 'Últimos cupos';
    if (e == 'activo' || e == 'en_ruta') return 'En curso';
    return 'Disponible';
  }

  static bool esUltimosCupos(int cuposDisponibles, int capacidad) {
    if (capacidad <= 0 || cuposDisponibles <= 0) return false;
    final ratio = cuposDisponibles / capacidad;
    return cuposDisponibles <= 3 || ratio <= 0.2;
  }

  static Color colorEstadoGira(String etiqueta) {
    switch (etiqueta) {
      case 'Últimos cupos':
        return const Color(0xFFDC2626);
      case 'Agotada':
        return const Color(0xFF6B7280);
      case 'Cancelada':
        return const Color(0xFF9CA3AF);
      case 'Finalizada':
        return const Color(0xFF4B5563);
      case 'En curso':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF059669);
    }
  }

  /// Fechas legibles sin desbordar (salida y regreso en líneas separadas).
  static List<String> lineasFechaSalidaRegreso({
    required DateTime salida,
    DateTime? regreso,
  }) {
    final fFecha = DateFormat('EEE d MMM yyyy', 'es');
    final fHora = DateFormat('HH:mm');
    final salidaTxt =
        'Salida: ${fFecha.format(salida)} · ${fHora.format(salida)}';
    if (regreso == null) return <String>[salidaTxt];
    final regresoTxt =
        'Regreso: ${fFecha.format(regreso)} · ${fHora.format(regreso)}';
    return <String>[salidaTxt, regresoTxt];
  }
}
