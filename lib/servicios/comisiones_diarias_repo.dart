import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';

class ComisionesDiariasRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DateTime? _pickFechaViaje(Map<String, dynamic> data) {
    final dynamic ts = data['finalizadoEn'] ??
        data['completadoEn'] ??
        data['updatedAt'] ??
        data['createdAt'] ??
        data['creadoEn'] ??
        data['fechaHora'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  static bool _inRange(DateTime? dt, DateTime inicio, DateTime finExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(inicio) && dt.isBefore(finExclusive);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _viajesCompletadosRango({
    required DateTime inicio,
    required DateTime finExclusive,
    int limit = 2000,
  }) async {
    try {
      final q = await _db
          .collection('viajes')
          .where('completado', isEqualTo: true)
          .where('finalizadoEn',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('finalizadoEn', isLessThan: Timestamp.fromDate(finExclusive))
          .get();
      return q.docs;
    } catch (_) {
      // Fallback robusto para esquemas legacy sin finalizadoEn/index.
      final q = await _db
          .collection('viajes')
          .where('completado', isEqualTo: true)
          .limit(limit)
          .get();
      return q.docs.where((d) {
        final dt = _pickFechaViaje(d.data());
        return _inRange(dt, inicio, finExclusive);
      }).toList();
    }
  }

  // ==============================================================
  // CALCULAR COMISIÓN (con posibilidad de ajuste individual)
  // ==============================================================
  static double _calcularComision(Map<String, dynamic> data) {
    // PRIORIDAD 1: Si ya tiene comisión guardada en el viaje, usarla
    if (data.containsKey('comision') && data['comision'] != null) {
      return (data['comision'] as num?)?.toDouble() ?? 0.0;
    }

    // PRIORIDAD 2: Si el taxista tiene una comisión especial (por promoción)
    final uidTaxista = data['uidTaxista'] as String?;
    if (uidTaxista != null) {
      // Aquí podrías consultar una colección 'promociones_taxistas'
      // para ver si este taxista tiene una comisión diferente este mes
      // double? comisionEspecial = _getComisionEspecial(uidTaxista);
      // if (comisionEspecial != null) return comisionEspecial;
    }

    // PRIORIDAD 3: Comisión nominal plataforma ([PlataformaEconomia.comisionPorcento]).
    final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
    return precio * PlataformaEconomia.factorComision;
  }

  // ==============================================================
  // OBTENER COMISIONES DEL DÍA DE HOY
  // ==============================================================
  static Future<Map<String, dynamic>> getComisionesHoy() async {
    final hoy = DateTime.now();
    final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);
    final finDia = inicioDia.add(const Duration(days: 1));

    final viajesHoy = await _viajesCompletadosRango(
      inicio: inicioDia,
      finExclusive: finDia,
    );

    var totalRecaudado = 0.0; // Lo que pagaron los clientes (100%)
    var totalComisiones = 0.0; // 20% para admin
    var totalGanancias = 0.0; // 80% para taxistas
    var totalViajes = 0;

    // Estadísticas por tipo (aunque todos paguen 20%, sirve para análisis)
    var viajesNormales = 0;
    var viajesMotor = 0;
    var viajesTurismo = 0;
    var comisionesNormales = 0.0;
    var comisionesMotor = 0.0;
    var comisionesTurismo = 0.0;

    for (final viaje in viajesHoy) {
      final data = viaje.data();
      final tipoServicio = data['tipoServicio'] as String? ?? 'normal';
      final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
      final comision = _calcularComision(data);
      final ganancia = precio - comision;

      totalRecaudado += precio;
      totalComisiones += comision;
      totalGanancias += ganancia;
      totalViajes++;

      // Acumular por tipo (solo para reportes)
      switch (tipoServicio) {
        case 'motor':
          viajesMotor++;
          comisionesMotor += comision;
          break;
        case 'turismo':
          viajesTurismo++;
          comisionesTurismo += comision;
          break;
        default:
          viajesNormales++;
          comisionesNormales += comision;
      }
    }

    return <String, dynamic>{
      'fecha': inicioDia,
      'totalRecaudado': totalRecaudado,
      'totalComisiones': totalComisiones,
      'totalGanancias': totalGanancias,
      'totalViajes': totalViajes,
      'porcentajeComision': totalRecaudado > 0
          ? (totalComisiones / totalRecaudado * 100).toStringAsFixed(1)
          : PlataformaEconomia.comisionPorcento.toStringAsFixed(1),
      // Desglose por tipo (para análisis)
      'desglose': {
        'normales': {
          'cantidad': viajesNormales,
          'comisiones': comisionesNormales,
        },
        'motor': {
          'cantidad': viajesMotor,
          'comisiones': comisionesMotor,
        },
        'turismo': {
          'cantidad': viajesTurismo,
          'comisiones': comisionesTurismo,
        },
      },
    };
  }

  // ==============================================================
  // OBTENER COMISIONES DE LA SEMANA ACTUAL
  // ==============================================================
  static Future<Map<String, dynamic>> getComisionesSemana() async {
    final hoy = DateTime.now();
    // Lunes de esta semana
    final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
    final inicioDia =
        DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
    final finDia = inicioDia.add(const Duration(days: 7));

    final viajesSemana = await _viajesCompletadosRango(
      inicio: inicioDia,
      finExclusive: finDia,
    );

    var totalRecaudado = 0.0;
    var totalComisiones = 0.0;
    var totalGanancias = 0.0;
    var totalViajes = 0;

    var viajesTurismo = 0;
    var comisionesTurismo = 0.0;

    for (final viaje in viajesSemana) {
      final data = viaje.data();
      final tipoServicio = data['tipoServicio'] as String? ?? 'normal';
      final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
      final comision = _calcularComision(data);
      final ganancia = precio - comision;

      totalRecaudado += precio;
      totalComisiones += comision;
      totalGanancias += ganancia;
      totalViajes++;

      if (tipoServicio == 'turismo') {
        viajesTurismo++;
        comisionesTurismo += comision;
      }
    }

    return <String, dynamic>{
      'inicio': inicioDia,
      'fin': finDia,
      'totalRecaudado': totalRecaudado,
      'totalComisiones': totalComisiones,
      'totalGanancias': totalGanancias,
      'totalViajes': totalViajes,
      'turismo': {
        'cantidad': viajesTurismo,
        'comisiones': comisionesTurismo,
      },
    };
  }

  // ==============================================================
  // OBTENER COMISIONES DEL MES ACTUAL
  // ==============================================================
  static Future<Map<String, dynamic>> getComisionesMes() async {
    final hoy = DateTime.now();
    final inicioMes = DateTime(hoy.year, hoy.month, 1);
    // Límite exclusivo para incluir TODO el último día del mes.
    final inicioMesSiguiente = DateTime(hoy.year, hoy.month + 1, 1);

    final viajesMes = await _viajesCompletadosRango(
      inicio: inicioMes,
      finExclusive: inicioMesSiguiente,
    );

    var totalRecaudado = 0.0;
    var totalComisiones = 0.0;
    var totalGanancias = 0.0;
    var totalViajes = 0;

    for (final viaje in viajesMes) {
      final data = viaje.data();
      final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
      final comision = _calcularComision(data);
      final ganancia = precio - comision;

      totalRecaudado += precio;
      totalComisiones += comision;
      totalGanancias += ganancia;
      totalViajes++;
    }

    return <String, dynamic>{
      'mes': '${inicioMes.month}/${inicioMes.year}',
      'inicio': inicioMes,
      'fin': inicioMesSiguiente.subtract(const Duration(milliseconds: 1)),
      'totalRecaudado': totalRecaudado,
      'totalComisiones': totalComisiones,
      'totalGanancias': totalGanancias,
      'totalViajes': totalViajes,
    };
  }

  // ==============================================================
  // OBTENER COMISIONES POR RANGO DE FECHAS
  // ==============================================================
  static Future<Map<String, dynamic>> getComisionesRango({
    required DateTime inicio,
    required DateTime fin,
  }) async {
    final viajesRango = await _viajesCompletadosRango(
      inicio: inicio,
      finExclusive: fin.add(const Duration(milliseconds: 1)),
    );

    var totalRecaudado = 0.0;
    var totalComisiones = 0.0;
    var totalGanancias = 0.0;
    var totalViajes = 0;

    for (final viaje in viajesRango) {
      final data = viaje.data();
      final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
      final comision = _calcularComision(data);
      final ganancia = precio - comision;

      totalRecaudado += precio;
      totalComisiones += comision;
      totalGanancias += ganancia;
      totalViajes++;
    }

    return <String, dynamic>{
      'inicio': inicio,
      'fin': fin,
      'totalRecaudado': totalRecaudado,
      'totalComisiones': totalComisiones,
      'totalGanancias': totalGanancias,
      'totalViajes': totalViajes,
    };
  }

  // ==============================================================
  // TOP TAXISTAS DEL DÍA (los que más comisiones generaron)
  // ==============================================================
  static Future<List<Map<String, dynamic>>> getTopTaxistasHoy(
      {int limite = 5}) async {
    final hoy = DateTime.now();
    final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);
    final finDia = inicioDia.add(const Duration(days: 1));

    final viajesHoy = await _viajesCompletadosRango(
      inicio: inicioDia,
      finExclusive: finDia,
    );

    final Map<String, Map<String, dynamic>> taxistasMap =
        <String, Map<String, dynamic>>{};

    for (final viaje in viajesHoy) {
      final data = viaje.data();
      final uidTaxista = data['uidTaxista'] as String?;
      final nombreTaxista = data['nombreTaxista'] as String? ?? 'Desconocido';
      final comision = _calcularComision(data);
      final precio = (data['precio'] as num?)?.toDouble() ?? 0.0;
      final ganancia =
          (data['gananciaTaxista'] as num?)?.toDouble() ?? (precio - comision);
      final tipoServicio = data['tipoServicio'] as String? ?? 'normal';

      if (uidTaxista == null || uidTaxista.isEmpty) continue;

      if (!taxistasMap.containsKey(uidTaxista)) {
        taxistasMap[uidTaxista] = <String, dynamic>{
          'uid': uidTaxista,
          'nombre': nombreTaxista,
          'totalComisiones': 0.0,
          'totalGanancias': 0.0,
          'totalViajes': 0,
          'viajesTurismo': 0,
          'comisionesTurismo': 0.0,
        };
      }

      final taxista = taxistasMap[uidTaxista]!;
      taxista['totalComisiones'] =
          (taxista['totalComisiones'] as double) + comision;
      taxista['totalGanancias'] =
          (taxista['totalGanancias'] as double) + ganancia;
      taxista['totalViajes'] = (taxista['totalViajes'] as int) + 1;

      if (tipoServicio == 'turismo') {
        taxista['viajesTurismo'] = (taxista['viajesTurismo'] as int) + 1;
        taxista['comisionesTurismo'] =
            (taxista['comisionesTurismo'] as double) + comision;
      }
    }

    // Ordenar por comisiones (mayor a menor) y tomar límite
    final List<Map<String, dynamic>> lista = taxistasMap.values.toList();
    lista.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        (b['totalComisiones'] as double)
            .compareTo(a['totalComisiones'] as double));

    return lista.take(limite).toList();
  }

  // ==============================================================
  // TOP TAXISTAS DE LA SEMANA
  // ==============================================================
  static Future<List<Map<String, dynamic>>> getTopTaxistasSemana(
      {int limite = 5}) async {
    final hoy = DateTime.now();
    final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
    final inicioDia =
        DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
    final finDia = inicioDia.add(const Duration(days: 7));

    final viajesSemana = await _viajesCompletadosRango(
      inicio: inicioDia,
      finExclusive: finDia,
    );

    final Map<String, Map<String, dynamic>> taxistasMap =
        <String, Map<String, dynamic>>{};

    for (final viaje in viajesSemana) {
      final data = viaje.data();
      final uidTaxista = data['uidTaxista'] as String?;
      final nombreTaxista = data['nombreTaxista'] as String? ?? 'Desconocido';
      final comision = _calcularComision(data);

      if (uidTaxista == null || uidTaxista.isEmpty) continue;

      if (!taxistasMap.containsKey(uidTaxista)) {
        taxistasMap[uidTaxista] = <String, dynamic>{
          'uid': uidTaxista,
          'nombre': nombreTaxista,
          'totalComisiones': 0.0,
          'totalViajes': 0,
        };
      }

      final taxista = taxistasMap[uidTaxista]!;
      taxista['totalComisiones'] =
          (taxista['totalComisiones'] as double) + comision;
      taxista['totalViajes'] = (taxista['totalViajes'] as int) + 1;
    }

    final List<Map<String, dynamic>> lista = taxistasMap.values.toList();
    lista.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        (b['totalComisiones'] as double)
            .compareTo(a['totalComisiones'] as double));

    return lista.take(limite).toList();
  }

  // ==============================================================
  // EVOLUCIÓN DIARIA DE LA SEMANA (para gráficas)
  // ==============================================================
  static Future<List<Map<String, dynamic>>> getEvolucionSemanal() async {
    final hoy = DateTime.now();
    final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));

    final List<Map<String, dynamic>> resultados = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final dia = inicioSemana.add(Duration(days: i));
      final inicioDia = DateTime(dia.year, dia.month, dia.day);
      final finDia = inicioDia.add(const Duration(days: 1));

      final viajesDia = await _viajesCompletadosRango(
        inicio: inicioDia,
        finExclusive: finDia,
        limit: 1500,
      );

      var totalComisiones = 0.0;
      var comisionesTurismo = 0.0;

      for (final viaje in viajesDia) {
        final data = viaje.data();
        final comision = _calcularComision(data);
        totalComisiones += comision;

        if (data['tipoServicio'] == 'turismo') {
          comisionesTurismo += comision;
        }
      }

      resultados.add(<String, dynamic>{
        'dia': i,
        'fecha': inicioDia,
        'nombreDia': _getNombreDia(i),
        'comisiones': totalComisiones,
        'comisionesTurismo': comisionesTurismo,
        'viajes': viajesDia.length,
      });
    }

    return resultados;
  }

  static String _getNombreDia(int index) {
    const List<String> dias = <String>[
      'Lun',
      'Mar',
      'Mié',
      'Jue',
      'Vie',
      'Sáb',
      'Dom'
    ];
    return dias[index];
  }

  // ==============================================================
  // AUDITORIA DE TRAZABILIDAD POR VIAJE/CHOFER
  // ==============================================================
  static Future<Map<String, dynamic>> getAuditoriaViajesComision({
    int dias = 30,
    int limiteInconsistencias = 80,
  }) async {
    final DateTime desde = DateTime.now().subtract(Duration(days: dias));
    final docs = await _viajesCompletadosRango(
      inicio: desde,
      finExclusive: DateTime.now().add(const Duration(days: 1)),
      limit: 3000,
    );
    final viajes = docs
      ..sort((a, b) {
        final da =
            _pickFechaViaje(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db =
            _pickFechaViaje(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

    final List<Map<String, dynamic>> inconsistencias = <Map<String, dynamic>>[];
    final Map<String, int> abiertasPorTaxista = <String, int>{};

    int auditados = 0;
    for (final doc in viajes.take(300)) {
      final d = doc.data();
      auditados++;
      final String uidTaxista = (d['uidTaxista'] ?? '').toString();
      final String nombreTaxista =
          (d['nombreTaxista'] ?? 'Sin nombre').toString();
      final int precioCents = ((d['precio_cents'] as num?)?.toInt() ??
          (((d['precio'] as num?)?.toDouble() ?? 0) * 100).round());
      final int comisionCents = ((d['comision_cents'] as num?)?.toInt() ??
          (((d['comision'] as num?)?.toDouble() ?? 0) * 100).round());
      final int gananciaCents = ((d['ganancia_cents'] as num?)?.toInt() ??
          (((d['gananciaTaxista'] as num?)?.toDouble() ?? 0) * 100).round());
      final bool pagoRegistrado = d['pagoRegistrado'] == true;
      final bool comisionCalculada = d['comisionCalculada'] == true;
      final bool cuadra =
          (precioCents > 0) && (precioCents == comisionCents + gananciaCents);
      final bool ok = pagoRegistrado && comisionCalculada && cuadra;
      if (!ok) {
        final String motivo = !pagoRegistrado
            ? 'sin_pago_registrado'
            : (!comisionCalculada
                ? 'sin_comision_calculada'
                : 'partidas_no_cuadran');
        inconsistencias.add({
          'viajeId': doc.id,
          'uidTaxista': uidTaxista,
          'nombreTaxista': nombreTaxista,
          'motivo': motivo,
          'precio': precioCents / 100.0,
          'comision': comisionCents / 100.0,
          'ganancia': gananciaCents / 100.0,
          'estado': (d['estado'] ?? '').toString(),
        });
        if (uidTaxista.isNotEmpty) {
          abiertasPorTaxista[uidTaxista] =
              (abiertasPorTaxista[uidTaxista] ?? 0) + 1;
        }
      }
    }

    final List<Map<String, dynamic>> topTaxistasInconsistentes =
        abiertasPorTaxista.entries
            .map((e) => <String, dynamic>{
                  'uidTaxista': e.key,
                  'inconsistencias': e.value
                })
            .toList()
          ..sort((a, b) => (b['inconsistencias'] as int)
              .compareTo(a['inconsistencias'] as int));

    return <String, dynamic>{
      'auditados': auditados,
      'inconsistencias': inconsistencias.take(limiteInconsistencias).toList(),
      'totalInconsistencias': inconsistencias.length,
      'topTaxistasInconsistentes': topTaxistasInconsistentes.take(10).toList(),
    };
  }

  // ==============================================================
  // SISTEMA DE PROMOCIONES (para futura implementación)
  // ==============================================================

  /// Guarda una promoción para un taxista específico
  static Future<void> guardarPromocionTaxista({
    required String uidTaxista,
    required double comisionEspecial, // Ej: 0.15 para 15%
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? motivo,
  }) async {
    await _db.collection('promociones_taxistas').add({
      'uidTaxista': uidTaxista,
      'comisionEspecial': comisionEspecial,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': Timestamp.fromDate(fechaFin),
      'motivo': motivo ?? 'Promoción especial',
      'activa': true,
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Obtiene la comisión especial de un taxista (si tiene promoción activa)
  static Future<double?> getComisionEspecialTaxista(String uidTaxista) async {
    final ahora = DateTime.now();

    final snapshot = await _db
        .collection('promociones_taxistas')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activa', isEqualTo: true)
        .where('fechaInicio', isLessThanOrEqualTo: Timestamp.fromDate(ahora))
        .where('fechaFin', isGreaterThanOrEqualTo: Timestamp.fromDate(ahora))
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    return (snapshot.docs.first.data()['comisionEspecial'] as num?)?.toDouble();
  }
}
