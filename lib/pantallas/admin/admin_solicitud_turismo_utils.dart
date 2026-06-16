// Utilidades ADM para cola solicitudes_turismo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_expediente_chofer_utils.dart';

enum AdminTipoVehiculoTurismoFiltro { todos, carro, jeepeta, minivan, bus }

class AdminSolicitudTurismoUtils {
  AdminSolicitudTurismoUtils._();

  static const Map<String, String> _labelsTipo = <String, String>{
    'carro': 'Carro Turismo',
    'jeepeta': 'Jeepeta Turismo',
    'minivan': 'Minivan Turismo',
    'bus': 'Bus Turismo',
  };

  static List<Map<String, dynamic>> vehiculosDesdeSolicitud(
    Map<String, dynamic> data,
  ) {
    final List<dynamic> vehiculosRaw = data['vehiculos'] as List? ?? [];
    if (vehiculosRaw.isNotEmpty) {
      return vehiculosRaw.map((dynamic v) {
        if (v is Map) {
          final String t = (v['tipo'] ?? '').toString().toLowerCase();
          return <String, dynamic>{
            'tipo': t,
            'tipoLabel': (v['tipoLabel'] ?? '').toString().isNotEmpty
                ? v['tipoLabel']
                : (_labelsTipo[t] ?? v['tipo'] ?? t),
            'marca': v['marca'] ?? '',
            'modelo': v['modelo'] ?? '',
            'color': v['color'] ?? '',
            'placa': v['placa'] ?? '',
            'anio': v['anio'] ?? 0,
            'fotoUrl': v['fotoUrl'],
          };
        }
        return <String, dynamic>{
          'tipo': v.toString().toLowerCase(),
          'tipoLabel': v.toString(),
          'marca': '',
          'modelo': '',
          'color': '',
          'placa': '',
          'anio': 0,
        };
      }).toList();
    }

    final List<dynamic> codigos = data['vehiculosSolicitados'] as List? ?? [];
    return codigos.map((dynamic c) {
      final String t = c.toString().toLowerCase();
      return <String, dynamic>{
        'tipo': t,
        'tipoLabel': _labelsTipo[t] ?? t,
        'marca': '',
        'modelo': '',
        'color': '',
        'placa': '',
        'anio': 0,
      };
    }).toList();
  }

  static Set<String> tiposVehiculo(Map<String, dynamic> data) {
    return vehiculosDesdeSolicitud(data)
        .map((v) => (v['tipo'] ?? '').toString().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  static bool coincideFiltroTipo(
    Map<String, dynamic> data,
    AdminTipoVehiculoTurismoFiltro filtro,
  ) {
    if (filtro == AdminTipoVehiculoTurismoFiltro.todos) return true;
    final String codigo = filtro.name;
    return tiposVehiculo(data).contains(codigo);
  }

  static bool coincideBusqueda(
    Map<String, dynamic> data,
    String docId,
    String query,
  ) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final Iterable<String> campos = <String>[
      docId,
      (data['uidChofer'] ?? '').toString(),
      (data['nombre'] ?? '').toString(),
      (data['email'] ?? '').toString(),
      (data['telefono'] ?? '').toString(),
      (data['notas'] ?? '').toString(),
      ...vehiculosDesdeSolicitud(data).expand((v) => <String>[
            (v['tipoLabel'] ?? '').toString(),
            (v['tipo'] ?? '').toString(),
            (v['marca'] ?? '').toString(),
            (v['modelo'] ?? '').toString(),
            (v['placa'] ?? '').toString(),
            (v['color'] ?? '').toString(),
          ]),
    ];
    return campos.any((c) => c.toLowerCase().contains(q));
  }

  static DateTime fechaOrden(Map<String, dynamic> data) {
    final Timestamp? solicitud = data['fechaSolicitud'] as Timestamp?;
    if (solicitud != null) return solicitud.toDate();
    final Timestamp? revisado = data['revisadoEn'] as Timestamp?;
    if (revisado != null) return revisado.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int contarPorTipo(
    Iterable<Map<String, dynamic>> solicitudes,
    AdminTipoVehiculoTurismoFiltro filtro,
  ) {
    return solicitudes.where((d) => coincideFiltroTipo(d, filtro)).length;
  }

  static Map<String, dynamic> documentosMap(Map<String, dynamic> data) {
    final raw = data['documentos'];
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static int documentosCompletosCount(Map<String, dynamic> data) {
    final Map<String, dynamic> m = documentosMap(data);
    var n = 0;
    for (final key in <String>['licencia', 'seguro', 'fotoVehiculo']) {
      final url = (m[key] ?? '').toString().trim();
      if (AdminExpedienteChoferUtils.urlAbrible(url)) n++;
    }
    return n;
  }

  static Color colorTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'jeepeta':
        return const Color(0xFFAB47BC);
      case 'minivan':
        return const Color(0xFF7E57C2);
      case 'bus':
        return const Color(0xFF5C6BC0);
      case 'carro':
      default:
        return const Color(0xFF8E24AA);
    }
  }

  static IconData iconoTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'jeepeta':
        return Icons.directions_car_filled;
      case 'minivan':
        return Icons.airport_shuttle;
      case 'bus':
        return Icons.directions_bus;
      case 'carro':
      default:
        return Icons.tour;
    }
  }

  static String vehiculoLinea(Map<String, dynamic> v) {
    final marca = (v['marca'] ?? '').toString().trim();
    final modelo = (v['modelo'] ?? '').toString().trim();
    final anio = v['anio'];
    final color = (v['color'] ?? '').toString().trim();
    final placa = (v['placa'] ?? '').toString().trim();
    final partes = <String>[];
    if (marca.isNotEmpty || modelo.isNotEmpty) {
      partes.add('$marca $modelo'.trim());
    }
    if (anio != null && anio.toString() != '0' && anio.toString().isNotEmpty) {
      partes.add(anio.toString());
    }
    if (color.isNotEmpty) partes.add(color);
    if (placa.isNotEmpty) partes.add('Placa $placa');
    return partes.isEmpty ? 'Sin detalle de vehículo' : partes.join(' · ');
  }
}
