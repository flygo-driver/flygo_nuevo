/// Extrae destino y preferencia de servicio desde frases habladas o escritas.
class RaiDestinoDesdeVozAnalisis {
  const RaiDestinoDesdeVozAnalisis({
    required this.textoOriginal,
    this.destinoExtraido,
    this.preferMotor = false,
    this.preferTaxi = false,
    this.preferTurismo = false,
    this.esPedidoDestino = false,
    this.esDireccionDirecta = false,
  });

  final String textoOriginal;
  final String? destinoExtraido;
  final bool preferMotor;
  final bool preferTaxi;
  final bool preferTurismo;
  final bool esPedidoDestino;
  final bool esDireccionDirecta;

  bool get tieneDestinoParaBuscar =>
      (destinoExtraido?.trim().length ?? 0) >= 3;

  /// Texto optimizado para Google Places / RAI dirección.
  String get consultaPlaces {
    final ext = destinoExtraido?.trim();
    if (ext != null && ext.length >= 3) return ext;
    return textoOriginal.trim();
  }
}

class RaiDestinoDesdeVoz {
  RaiDestinoDesdeVoz._();

  static final List<RegExp> _patronesDestino = [
    RegExp(
      r'^(?:quiero|necesito|me gustar[ií]a|quisiera|puedes|pod[eé]is|podr[ií]as|'
      r'me puedes|me podr[ií]as)\s+(?:ir|llegar|viajar|mandar|pedir)\s+'
      r'(?:un\s+(?:taxi|motor|viaje)\s+)?(?:a|al|a la|a el|hasta|para|hacia)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:llev[aá]me|ll[eé]vame|tra[eé]me|m[aá]ndame|ponme)\s+'
      r'(?:a|al|a la|a el|hasta|para|hacia)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:voy|viajo|salgo|salir|destino|mi destino es|el destino es)\s+'
      r'(?:a|al|a la|a el|para|hacia|hasta)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:(?:un|una)\s+)?(?:taxi|motor|moto|motocicleta|viaje|carro)\s+'
      r'(?:a|al|a la|a el|para|hacia|hasta)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:busco|buscar|necesito)\s+(?:ir\s+)?(?:a|al|a la|hasta)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:direcci[oó]n|destino)\s*(?:es|:)?\s*(.+)$',
      caseSensitive: false,
    ),
  ];

  static const _sufijosRuido = [
    ' por favor',
    ' gracias',
    ' ahora',
    ' hoy',
    ' ya',
    ' en rai',
    ' en la app',
    ' con rai',
  ];

  static const _prefijosRuido = [
    'quiero ir a ',
    'quiero ir al ',
    'quiero ir a la ',
    'quiero ir a el ',
    'necesito ir a ',
    'necesito ir al ',
    'me gustaría ir a ',
    'me gustaria ir a ',
    'llevame a ',
    'llévame a ',
    'llevame al ',
    'llévame al ',
    'voy para ',
    'voy a ',
    'destino ',
    'dirección ',
    'direccion ',
    'buscar ',
  ];

  static RaiDestinoDesdeVozAnalisis analizar(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return RaiDestinoDesdeVozAnalisis(textoOriginal: text);
    }

    final lower = text.toLowerCase();
    final preferMotor = _match(lower, [
      'motor',
      'moto',
      'motocicleta',
      'en motor',
      'un motor',
    ]);
    final preferTurismo = _match(lower, [
      'turismo',
      'excursión',
      'excursion',
      'tour',
    ]);
    final preferTaxi = _match(lower, [
      'taxi',
      'carro',
      'viaje',
      'programar',
      'programado',
    ]) && !preferMotor;

    String? extraido;
    for (final re in _patronesDestino) {
      final m = re.firstMatch(text);
      if (m != null && m.groupCount >= 1) {
        final candidato = _limpiarDestino(m.group(1) ?? '');
        if (candidato.length >= 3) {
          extraido = candidato;
          break;
        }
      }
    }

    extraido ??= () {
      final candidato = _limpiarDestino(_stripPrefijosConocidos(text));
      return candidato.length >= 3 ? candidato : null;
    }();

    final esPedido = extraido != null &&
        extraido.toLowerCase() != lower;

    final esDireccionDirecta =
        extraido == null && _pareceDireccionLiteral(text);

    if (extraido != null &&
        extraido.toLowerCase() == lower &&
        _pareceDireccionLiteral(text)) {
      final refinado = _limpiarDestino(text);
      extraido = refinado.length >= 3 ? refinado : extraido;
    }

    return RaiDestinoDesdeVozAnalisis(
      textoOriginal: text,
      destinoExtraido: extraido,
      preferMotor: preferMotor,
      preferTaxi: preferTaxi || (!preferMotor && !preferTurismo && esPedido),
      preferTurismo: preferTurismo,
      esPedidoDestino: esPedido,
      esDireccionDirecta: esDireccionDirecta,
    );
  }

  /// Normaliza frases de destino (compartido con KB local).
  static String? normalizarParaPlaces(String raw) {
    final a = analizar(raw);
    if (a.tieneDestinoParaBuscar) return a.consultaPlaces;
    if (a.esDireccionDirecta && raw.trim().length >= 3) {
      return _limpiarDestino(raw);
    }
    return _limpiarDestino(_stripPrefijosConocidos(raw));
  }

  static bool confianzaAltaEnPrimerResultado({
    required String consulta,
    required String displayLabel,
    required int totalResultados,
  }) {
    if (totalResultados == 1) return true;
    if (totalResultados == 0) return false;

    final q = _norm(consulta);
    final label = _norm(displayLabel);
    if (label.contains(q) || q.contains(label)) return true;

    final words = q
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .take(8)
        .toList();
    if (words.isEmpty) return false;

    var hits = 0;
    for (final w in words) {
      if (label.contains(w)) hits++;
    }
    if (words.length <= 2) return hits >= 1;
    return hits >= 2;
  }

  static String _stripPrefijosConocidos(String t) {
    var out = t.trim();
    var lower = out.toLowerCase();
    for (final p in _prefijosRuido) {
      if (lower.startsWith(p)) {
        out = out.substring(p.length).trim();
        lower = out.toLowerCase();
      }
    }
    return out;
  }

  static String _limpiarDestino(String t) {
    var out = t.trim();
    if (out.endsWith('?')) out = out.substring(0, out.length - 1).trim();

    var lower = out.toLowerCase();
    for (final s in _sufijosRuido) {
      if (lower.endsWith(s)) {
        out = out.substring(0, out.length - s.length).trim();
        lower = out.toLowerCase();
      }
    }

    // Aeropuertos frecuentes en RD
    if (lower.contains('aeropuerto') && lower.contains('punta')) {
      return 'Aeropuerto Punta Cana PUJ';
    }
    if (lower.contains('las americas') ||
        lower.contains('las américas') ||
        lower.contains(' sdq')) {
      return 'Aeropuerto Las Américas SDQ Santo Domingo';
    }
    if (lower.contains('zona colonial')) {
      return 'Zona Colonial Santo Domingo';
    }

    return out.length >= 3 ? out : '';
  }

  static bool _pareceDireccionLiteral(String text) {
    if (text.length < 8) return false;
    if (text.contains('?')) return false;

    final lower = text.toLowerCase();
    if (_match(lower, [
      'como funciona',
      'cómo funciona',
      'cuanto cuesta',
      'cuánto cuesta',
      'soporte',
      'reclamo',
      'sin internet',
    ])) {
      return false;
    }

    return text.contains(',') ||
        RegExp(r'\d').hasMatch(text) ||
        _match(lower, [
          'calle',
          'avenida',
          'av.',
          'av ',
          'sector',
          'colmado',
          'malecón',
          'malecon',
          'barrio',
          'esquina',
          'frente a',
          'cerca de',
          'hotel',
          'aeropuerto',
          'playa',
          'santo domingo',
          'santiago',
          'punta cana',
          'bávaro',
          'bavaro',
          'los mina',
          'los minas',
          'naco',
          'piantini',
          'gazcue',
          'verón',
          'veron',
        ]);
  }

  static bool _match(String q, List<String> keys) {
    for (final k in keys) {
      if (q.contains(k)) return true;
    }
    return false;
  }

  static String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }
}
