// Estado operativo de choferes turismo para panel ADM (auto-asignación).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';

enum AdminFiltroOperativoTurismo {
  todos,
  candidatosAuto,
  noDisponibles,
  sinGps,
  enViaje,
}

class AdminChoferTurismoOperativo {
  const AdminChoferTurismoOperativo({
    required this.aprobadoOperativo,
    required this.disponible,
    required this.tieneGps,
    required this.enViaje,
    required this.tieneVehiculos,
    required this.bloqueoPagos,
    required this.bloqueoPagosCargado,
  });

  final bool aprobadoOperativo;
  final bool disponible;
  final bool tieneGps;
  final bool enViaje;
  final bool tieneVehiculos;
  final bool bloqueoPagos;
  final bool bloqueoPagosCargado;

  bool get candidatoSync =>
      aprobadoOperativo && disponible && !enViaje && tieneVehiculos;

  bool get listoAutoAsignacion =>
      candidatoSync && bloqueoPagosCargado && !bloqueoPagos;

  List<AdminOperativoBadge> badgesSync() {
    final List<AdminOperativoBadge> out = <AdminOperativoBadge>[];
    if (!aprobadoOperativo) {
      out.add(const AdminOperativoBadge(
        label: 'No operativo',
        color: Color(0xFFFF5252),
        icon: Icons.block,
      ));
    }
    if (disponible) {
      out.add(const AdminOperativoBadge(
        label: 'Disponible',
        color: Color(0xFF66BB6A),
        icon: Icons.check_circle_outline,
      ));
    } else {
      out.add(const AdminOperativoBadge(
        label: 'No disponible',
        color: Color(0xFFFFB74D),
        icon: Icons.pause_circle_outline,
      ));
    }
    if (!tieneGps) {
      out.add(const AdminOperativoBadge(
        label: 'Sin GPS',
        color: Color(0xFF29B6F6),
        icon: Icons.location_off_outlined,
      ));
    } else {
      out.add(const AdminOperativoBadge(
        label: 'GPS OK',
        color: Color(0xFF66BB6A),
        icon: Icons.location_on_outlined,
      ));
    }
    if (enViaje) {
      out.add(const AdminOperativoBadge(
        label: 'En viaje',
        color: Color(0xFFFF5252),
        icon: Icons.directions_car,
      ));
    }
    if (!tieneVehiculos) {
      out.add(const AdminOperativoBadge(
        label: 'Sin vehículo',
        color: Color(0xFFFF5252),
        icon: Icons.no_crash_outlined,
      ));
    }
    return out;
  }

  AdminOperativoBadge? badgePagos() {
    if (!bloqueoPagosCargado) {
      return const AdminOperativoBadge(
        label: 'Pagos…',
        color: Color(0xFF90A4AE),
        icon: Icons.hourglass_empty,
      );
    }
    if (bloqueoPagos) {
      return const AdminOperativoBadge(
        label: 'Bloqueo pagos',
        color: Color(0xFFFF5252),
        icon: Icons.account_balance_wallet_outlined,
      );
    }
    return const AdminOperativoBadge(
      label: 'Pagos OK',
      color: Color(0xFF66BB6A),
      icon: Icons.verified_outlined,
    );
  }

  String get resumenAutoAsignacion {
    if (listoAutoAsignacion) {
      return tieneGps
          ? 'Listo para auto-asignación'
          : 'Listo (sin GPS: menor prioridad por distancia)';
    }
    if (!bloqueoPagosCargado) return 'Verificando pagos…';
    final List<String> motivos = <String>[];
    if (!aprobadoOperativo) motivos.add('no aprobado');
    if (!disponible) motivos.add('no disponible');
    if (enViaje) motivos.add('en viaje');
    if (!tieneVehiculos) motivos.add('sin vehículo');
    if (bloqueoPagos) motivos.add('bloqueo pagos');
    if (motivos.isEmpty) return 'Revisar estado operativo';
    return 'No auto-asignable: ${motivos.join(', ')}';
  }

  static AdminChoferTurismoOperativo desdeChoferDoc(Map<String, dynamic> data) {
    final bool aprobado =
        AsignacionTurismoRepo.choferEstadoOperativo(data['estado']);
    final bool disponible = data['disponible'] == true;
    final bool enViaje =
        (data['viajeActualId'] ?? '').toString().trim().isNotEmpty;
    final bool tieneGps = data['ultimaUbicacion'] is GeoPoint;
    final List<dynamic> vehiculos = data['vehiculos'] as List? ?? const [];
    final bool tieneVehiculos = vehiculos.isNotEmpty;

    return AdminChoferTurismoOperativo(
      aprobadoOperativo: aprobado,
      disponible: disponible,
      tieneGps: tieneGps,
      enViaje: enViaje,
      tieneVehiculos: tieneVehiculos,
      bloqueoPagos: false,
      bloqueoPagosCargado: false,
    );
  }

  AdminChoferTurismoOperativo conBloqueoPagos(bool bloqueado) {
    return AdminChoferTurismoOperativo(
      aprobadoOperativo: aprobadoOperativo,
      disponible: disponible,
      tieneGps: tieneGps,
      enViaje: enViaje,
      tieneVehiculos: tieneVehiculos,
      bloqueoPagos: bloqueado,
      bloqueoPagosCargado: true,
    );
  }

  static Future<bool> consultarBloqueoPagos(String uid) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('usuarios').doc(uid).get(),
      db.collection('billeteras_taxista').doc(uid).get(),
    ]);
    final DocumentSnapshot<Map<String, dynamic>> uSnap =
        results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final DocumentSnapshot<Map<String, dynamic>> bSnap =
        results[1] as DocumentSnapshot<Map<String, dynamic>>;

    return !PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
      uSnap.data(),
      bSnap.data(),
    );
  }

  bool coincideFiltro(AdminFiltroOperativoTurismo filtro) {
    switch (filtro) {
      case AdminFiltroOperativoTurismo.todos:
        return true;
      case AdminFiltroOperativoTurismo.candidatosAuto:
        return listoAutoAsignacion;
      case AdminFiltroOperativoTurismo.noDisponibles:
        return !disponible;
      case AdminFiltroOperativoTurismo.sinGps:
        return !tieneGps;
      case AdminFiltroOperativoTurismo.enViaje:
        return enViaje;
    }
  }
}

class AdminOperativoBadge {
  final String label;
  final Color color;
  final IconData icon;

  const AdminOperativoBadge({
    required this.label,
    required this.color,
    required this.icon,
  });
}
