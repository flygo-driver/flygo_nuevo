import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';

/// Modo del pool principal (AHORA / PROGRAMADOS) según registro del conductor.
abstract final class TaxistaPoolModoConductor {
  static const String motor = 'motor';
  static const String vehiculo = 'vehiculo';
}

/// Reglas compartidas: lista «Viajes disponibles» y pantalla detalle (mismo criterio de claim).
class ViajePoolTaxistaGate {
  ViajePoolTaxistaGate._();

  static String poolModoConductorDesdeUsuario(Map<String, dynamic>? uData) {
    if (uData == null) return TaxistaPoolModoConductor.vehiculo;
    String raw = (uData['tipoServicio'] ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) {
      final veh = uData['vehiculo'];
      if (veh is Map) {
        raw = (veh['tipoServicio'] ?? '').toString().trim().toLowerCase();
      }
    }
    if (raw == TaxistaPoolModoConductor.motor) {
      return TaxistaPoolModoConductor.motor;
    }
    return TaxistaPoolModoConductor.vehiculo;
  }

  static String tipoServicioViajeNormalizado(Map<String, dynamic> data) {
    return (data['tipoServicio'] ?? 'normal').toString().trim().toLowerCase();
  }

  /// Motor ↔ motor; carro/taxi/multiparada ↔ todo lo que no sea motor ni turismo.
  static bool viajeCoincideModoConductor(
    Map<String, dynamic> data,
    String poolModoConductor,
  ) {
    final tipo = tipoServicioViajeNormalizado(data);
    if (poolModoConductor == TaxistaPoolModoConductor.motor) {
      return tipo == TaxistaPoolModoConductor.motor;
    }
    return tipo != TaxistaPoolModoConductor.motor && tipo != 'turismo';
  }

  static String etiquetaPoolModo(String poolModoConductor) {
    if (poolModoConductor == TaxistaPoolModoConductor.motor) {
      return 'Pool motores';
    }
    return 'Pool vehículos';
  }

  static String descripcionPoolModo(String poolModoConductor) {
    if (poolModoConductor == TaxistaPoolModoConductor.motor) {
      return 'Solo viajes de motores. Te avisamos cuando llegue uno.';
    }
    return 'Taxi, programados y multiparada. Te avisamos al instante.';
  }

  static DateTime fechaHoraDeViaje(Map<String, dynamic> data) {
    final fh = data['fechaHora'];
    if (fh is Timestamp) return fh.toDate();
    if (fh is DateTime) return fh;
    if (fh is String) {
      return DateTime.tryParse(fh) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime acceptAfterDeViaje(
      Map<String, dynamic> data, DateTime fecha) {
    final raw = data['acceptAfter'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final p = DateTime.tryParse(raw);
      if (p != null) return p;
    }
    return fecha.subtract(
      const Duration(minutes: TripPublishWindows.poolLeadMinutesProgramado),
    );
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
    final bool reservaVigente = reservadoPor.isNotEmpty &&
        (vence == null || vence.isAfter(DateTime.now()));
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
  static bool viajeTomableEnPool(
    Map<String, dynamic> data,
    String myUid, {
    String poolModoConductor = TaxistaPoolModoConductor.vehiculo,
  }) {
    final String bolaPid =
        (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
    if (bolaPid.isNotEmpty && data['bolaNegociacionAbierta'] == true) {
      return false;
    }

    final String tipoServicio = (data['tipoServicio'] ?? 'normal').toString();
    final String canalAsignacion =
        (data['canalAsignacion'] ?? 'pool').toString();

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

    if (!viajeCoincideModoConductor(data, poolModoConductor)) return false;

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

  /// Claim pool: turismo_pool (chofer turismo) o coincidencia motor/vehículo normal.
  static bool conductorPuedeClaimViajeEnPool(
    Map<String, dynamic> data,
    String poolModoConductor,
  ) {
    if (esTurismoPoolTomable(data)) return true;
    return viajeCoincideModoConductor(data, poolModoConductor);
  }

  /// Viaje espejo Bola Ahorro: negociación y ejecución van por [bolas_pueblo], no por ViajeEnCurso ni auto-router.
  static bool esViajeEspejoBolaParaFlujo(Map<String, dynamic> data) {
    if ((data['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro') {
      return true;
    }
    final pid =
        (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
    return pid.isNotEmpty;
  }

  /// Mientras el espejo está en pool **sin aceptar**, el taxista sigue el flujo Bola Pueblo.
  /// Con `aceptado` o estados de ejecución, aplica el mismo flujo que un viaje pool ([ViajeEnCursoTaxista]).
  static bool debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(
      Map<String, dynamic> data) {
    if (!esViajeEspejoBolaParaFlujo(data)) return false;
    final estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final bool aceptado = (data['aceptado'] ?? false) == true;
    if (aceptado ||
        estadoNorm == EstadosViaje.aceptado ||
        estadoNorm == EstadosViaje.enCaminoPickup ||
        estadoNorm == EstadosViaje.aBordo ||
        estadoNorm == EstadosViaje.enCurso ||
        estadoNorm == EstadosViaje.completado) {
      return false;
    }
    return true;
  }

  static bool _usuarioEsClienteEnDoc(Map<String, dynamic> data, String uid) {
    final String u = uid.trim();
    return (data['uidCliente'] ?? '').toString().trim() == u ||
        (data['clienteId'] ?? '').toString().trim() == u;
  }

  static bool _usuarioEsTaxistaEnDoc(Map<String, dynamic> data, String uid) {
    final String u = uid.trim();
    return (data['uidTaxista'] ?? '').toString().trim() == u ||
        (data['taxistaId'] ?? '').toString().trim() == u;
  }

  /// ¿El shell debe cubrir pantalla completa con viaje en curso?
  /// Excluye: Bola en negociación, programado lejano (pool aún cerrado).
  static bool viajeDocDebeMostrarOverlayShell(
    Map<String, dynamic> data,
    String uid,
  ) {
    final String st =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (data['completado'] == true || EstadosViaje.esTerminal(st)) {
      return false;
    }

    if (debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(data)) {
      return false;
    }

    final bool esCliente = _usuarioEsClienteEnDoc(data, uid);
    final bool esTaxista = _usuarioEsTaxistaEnDoc(data, uid);

    if (esCliente &&
        data['programado'] == true &&
        data['activo'] != true &&
        data['esAhora'] != true &&
        !ventanaPublicacionYAceptacionOk(data)) {
      return false;
    }

    if (EstadosViaje.activos.contains(st)) return true;

    if (data['activo'] == true) return true;

    if (esCliente &&
        (data['tipoServicio'] ?? '').toString() == 'turismo' &&
        st == 'pendiente_admin') {
      return true;
    }

    if (st == EstadosViaje.pendiente ||
        st == EstadosViaje.pendientePago ||
        st == 'pendiente_admin') {
      if (esCliente &&
          (data['esAhora'] == true || ventanaPublicacionYAceptacionOk(data))) {
        return true;
      }
      if (esTaxista && (data['uidTaxista'] ?? '').toString().trim() == uid) {
        return true;
      }
    }

    return false;
  }
}
