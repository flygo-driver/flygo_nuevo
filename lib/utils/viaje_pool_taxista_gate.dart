import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Reglas compartidas: lista «Viajes disponibles» y pantalla detalle (mismo criterio de claim).
class ViajePoolTaxistaGate {
  ViajePoolTaxistaGate._();

  static DateTime fechaHoraDeViaje(Map<String, dynamic> data) {
    final fh = data['fechaHora'];
    if (fh is Timestamp) return fh.toDate();
    if (fh is DateTime) return fh;
    if (fh is String) {
      return DateTime.tryParse(fh) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime acceptAfterDeViaje(Map<String, dynamic> data, DateTime fecha) {
    final raw = data['acceptAfter'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final p = DateTime.tryParse(raw);
      if (p != null) return p;
    }
    return fecha.subtract(const Duration(hours: 2));
  }

  static bool estadoPermiteClaimPool(String estadoRaw, String estadoNorm) {
    final estadoLower = estadoRaw.toLowerCase().trim();
    return estadoNorm == EstadosViaje.pendiente ||
        estadoNorm == EstadosViaje.pendientePago ||
        estadoLower == 'buscando' ||
        estadoLower == 'disponible' ||
        estadoLower == 'pendiente_admin' ||
        estadoRaw == 'pendienteAdmin';
  }

  static bool reservaVigenteBloquea(Map<String, dynamic> data) {
    final reservadoPor = (data['reservadoPor'] ?? '').toString();
    final rh = data['reservadoHasta'];
    DateTime? vence;
    if (rh is Timestamp) vence = rh.toDate();
    if (rh is DateTime) vence = rh;
    final bool reservaVigente =
        reservadoPor.isNotEmpty && (vence == null || vence.isAfter(DateTime.now()));
    return reservaVigente;
  }

  static bool ventanaPublicacionYAceptacionOk(Map<String, dynamic> data) {
    final now = DateTime.now();
    final fecha = fechaHoraDeViaje(data);
    final acceptAfter = acceptAfterDeViaje(data, fecha);
    if (now.isBefore(acceptAfter)) return false;

    final rawPublishAt = data['publishAt'];
    DateTime? publishAt;
    if (rawPublishAt is Timestamp) publishAt = rawPublishAt.toDate();
    if (rawPublishAt is DateTime) publishAt = rawPublishAt;
    if (rawPublishAt is String) publishAt = DateTime.tryParse(rawPublishAt);
    if (publishAt != null && now.isBefore(publishAt)) return false;
    return true;
  }

  /// Misma lógica que el filtro de la lista del pool (taxista normal / motor).
  static bool viajeTomableEnPool(Map<String, dynamic> data, String myUid) {
    final String tipoServicio = (data['tipoServicio'] ?? 'normal').toString();
    final String canalAsignacion = (data['canalAsignacion'] ?? 'pool').toString();

    if (tipoServicio == 'turismo' ||
        canalAsignacion == 'admin' ||
        canalAsignacion == AsignacionTurismoRepo.canalTurismoPool) {
      return false;
    }

    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;

    final String estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final String estadoRaw = (data['estado'] ?? '').toString().trim();
    if (!estadoPermiteClaimPool(estadoRaw, estadoNorm)) return false;

    if (reservaVigenteBloquea(data)) return false;

    return ventanaPublicacionYAceptacionOk(data);
  }

  /// Turismo canal admin: no se acepta en app; se muestra aviso en detalle.
  static bool esTurismoSoloAdminPendiente(Map<String, dynamic> data) {
    final tipoServicio = (data['tipoServicio'] ?? 'normal').toString();
    final canalAsignacion = (data['canalAsignacion'] ?? 'pool').toString();
    if (tipoServicio != 'turismo' || canalAsignacion != 'admin') return false;
    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;

    final String estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final String estadoRaw = (data['estado'] ?? '').toString().trim();
    if (!estadoPermiteClaimPool(estadoRaw, estadoNorm)) return false;
    if (reservaVigenteBloquea(data)) return false;
    return ventanaPublicacionYAceptacionOk(data);
  }

  /// Turismo pool: claim va por flujo dedicado en [_aceptarViaje] del detalle.
  static bool esTurismoPoolTomable(Map<String, dynamic> data) {
    final tipoServicio = (data['tipoServicio'] ?? 'normal').toString();
    final canalAsignacion = (data['canalAsignacion'] ?? 'pool').toString();
    if (tipoServicio != 'turismo' ||
        canalAsignacion != AsignacionTurismoRepo.canalTurismoPool) {
      return false;
    }
    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;

    final String estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final String estadoRaw = (data['estado'] ?? '').toString().trim();
    if (!estadoPermiteClaimPool(estadoRaw, estadoNorm)) return false;
    if (reservaVigenteBloquea(data)) return false;
    return ventanaPublicacionYAceptacionOk(data);
  }
}
