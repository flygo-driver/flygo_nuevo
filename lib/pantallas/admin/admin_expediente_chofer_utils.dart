// Utilidades compartidas para colas ADM de choferes (normal / motor / bola).
// Turismo usa colección aparte — no entra aquí.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/flygo_storage.dart';

/// Filtro de línea de servicio en expedientes ADM.
enum AdminLineaChoferFiltro { todos, normal, motor, bolaAhorro }

class AdminExpedienteChoferUtils {
  AdminExpedienteChoferUtils._();

  /// Taxistas operativos (excluye turismo — cola propia en solicitudes_turismo).
  static bool esExpedienteTaxistaOperativo(Map<String, dynamic> d) {
    final String rol = (d['rol'] ?? '').toString().trim().toLowerCase();
    if (rol != 'taxista') return false;
    final String ts = lineaCodigo(d);
    if (ts == 'turismo') return false;
    return true;
  }

  static String lineaCodigo(Map<String, dynamic> d) {
    final String ts =
        (d['tipoServicio'] ?? d['vehiculo']?['tipoServicio'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (ts.isNotEmpty) return ts;

    final String tv = (d['tipoVehiculo'] ?? d['vehiculoTipo'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (tv == 'motor') return 'motor';
    return 'normal';
  }

  static String lineaEtiqueta(Map<String, dynamic> d) {
    switch (lineaCodigo(d)) {
      case 'motor':
        return 'Motor';
      case 'bola_ahorro':
        return 'Bola Ahorro';
      case 'normal':
        return 'Normal';
      default:
        return 'Taxista';
    }
  }

  static IconData lineaIcono(Map<String, dynamic> d) {
    switch (lineaCodigo(d)) {
      case 'motor':
        return Icons.two_wheeler;
      case 'bola_ahorro':
        return Icons.savings_outlined;
      default:
        return Icons.local_taxi;
    }
  }

  static Color lineaColor(Map<String, dynamic> d) {
    switch (lineaCodigo(d)) {
      case 'motor':
        return const Color(0xFF29B6F6);
      case 'bola_ahorro':
        return const Color(0xFFFFB74D);
      default:
        return const Color(0xFF66BB6A);
    }
  }

  static bool coincideFiltroLinea(
    Map<String, dynamic> d,
    AdminLineaChoferFiltro filtro,
  ) {
    if (filtro == AdminLineaChoferFiltro.todos) return true;
    final String codigo = lineaCodigo(d);
    switch (filtro) {
      case AdminLineaChoferFiltro.normal:
        return codigo == 'normal' || codigo.isEmpty || codigo == 'taxista';
      case AdminLineaChoferFiltro.motor:
        return codigo == 'motor';
      case AdminLineaChoferFiltro.bolaAhorro:
        return codigo == 'bola_ahorro';
      case AdminLineaChoferFiltro.todos:
        return true;
    }
  }

  static bool coincideBusqueda(
    Map<String, dynamic> d,
    String uid,
    String query,
  ) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final Iterable<String> campos = <String>[
      uid,
      (d['nombre'] ?? '').toString(),
      (d['email'] ?? '').toString(),
      (d['telefono'] ?? '').toString(),
      (d['placa'] ?? d['vehiculo']?['placa'] ?? '').toString(),
      (d['vehiculoMarca'] ?? d['vehiculo']?['marca'] ?? '').toString(),
      (d['vehiculoModelo'] ?? d['vehiculo']?['modelo'] ?? '').toString(),
      lineaEtiqueta(d),
    ];
    return campos.any((c) => c.toLowerCase().contains(q));
  }

  static String vehiculoResumen(Map<String, dynamic> d) {
    final String placa =
        (d['placa'] ?? d['vehiculo']?['placa'] ?? '').toString().trim();
    final String marca =
        (d['vehiculoMarca'] ?? d['vehiculo']?['marca'] ?? d['marca'] ?? '')
            .toString()
            .trim();
    final String modelo =
        (d['vehiculoModelo'] ?? d['vehiculo']?['modelo'] ?? d['modelo'] ?? '')
            .toString()
            .trim();
    final String tipo =
        (d['tipoVehiculo'] ?? d['vehiculoTipo'] ?? d['vehiculo']?['tipo'] ?? '')
            .toString()
            .trim();

    final List<String> partes = <String>[];
    if (marca.isNotEmpty || modelo.isNotEmpty) {
      partes.add('$marca $modelo'.trim());
    }
    if (tipo.isNotEmpty && tipo.toLowerCase() != 'motor') partes.add(tipo);
    if (placa.isNotEmpty) partes.add('Placa $placa');
    return partes.isEmpty ? 'Sin datos de vehículo' : partes.join(' · ');
  }

  static DateTime fechaOrden(Map<String, dynamic> d) {
    final Timestamp? enviado = d['docsEnviadosEn'] as Timestamp?;
    if (enviado != null) return enviado.toDate();
    final Timestamp? actualizado = d['actualizadoEn'] as Timestamp?;
    if (actualizado != null) return actualizado.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int contarPorLinea(
    Iterable<Map<String, dynamic>> docs,
    AdminLineaChoferFiltro filtro,
  ) {
    return docs.where((d) => coincideFiltroLinea(d, filtro)).length;
  }

  static Map<String, dynamic> docsMap(Map<String, dynamic> d) {
    final raw = d['docs'];
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static int documentosCompletosCount(Map<String, dynamic> d) {
    final Map<String, dynamic> map = docsMap(d);
    const keys = <String>[
      'licenciaUrl',
      'matriculaUrl',
      'seguroUrl',
      'fotoVehiculoUrl',
      'placaUrl',
    ];
    var n = 0;
    for (final k in keys) {
      final url = (map[k] ?? '').toString().trim();
      if (urlAbrible(url)) n++;
    }
    return n;
  }

  static bool urlAbrible(String url) {
    if (RaiDocUrl.isFirestoreDoc(url)) return true;
    final u = Uri.tryParse(url.trim());
    return u != null &&
        u.hasScheme &&
        (u.scheme == 'http' || u.scheme == 'https');
  }
}
