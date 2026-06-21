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

  /// Reserva futura cuyo pool aún no abrió (~45 min antes de recogida).
  static bool esReservaProgramadaLejana(Map<String, dynamic> data) {
    if (data['programado'] != true) return false;
    if (data['esAhora'] == true) return false;
    if (data['activo'] == true) return false;
    return !ventanaPublicacionYAceptacionOk(data);
  }

  /// ¿Un viaje ya existente impide crear otro pedido del cliente?
  static bool clienteViajeExistenteBloqueaNuevoPedido(
    Map<String, dynamic> data,
    String uid, {
    required bool nuevoEsAhora,
  }) {
    if (!_usuarioEsClienteEnDoc(data, uid)) return false;
    final String st =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (data['completado'] == true || EstadosViaje.esTerminal(st)) {
      return false;
    }
    if (esReservaProgramadaLejana(data)) {
      return !nuevoEsAhora;
    }
    return true;
  }

  static Map<String, String> patchUsuarioTrasCrearViajeCliente({
    required String uidCliente,
    required String nuevoViajeId,
    required bool nuevoEsAhora,
    required Map<String, dynamic>? userData,
    required Map<String, dynamic>? viajeActivoDoc,
  }) {
    final String sigPrev =
        (userData?['siguienteViajeId'] ?? '').toString().trim();
    final String vidPrev =
        (userData?['viajeActivoId'] ?? '').toString().trim();

    String viajeActivoId = nuevoViajeId;
    String siguienteViajeId = sigPrev;

    if (vidPrev.isNotEmpty && viajeActivoDoc != null) {
      if (esReservaProgramadaLejana(viajeActivoDoc)) {
        if (nuevoEsAhora) {
          if (sigPrev.isEmpty) {
            siguienteViajeId = vidPrev;
          }
          viajeActivoId = nuevoViajeId;
        } else {
          viajeActivoId = nuevoViajeId;
        }
      } else if (!nuevoEsAhora &&
          viajeDocDebeMostrarOverlayShell(viajeActivoDoc, uidCliente)) {
        viajeActivoId = vidPrev;
        siguienteViajeId = nuevoViajeId;
      }
    }

    return <String, String>{
      'viajeActivoId': viajeActivoId,
      'siguienteViajeId': siguienteViajeId,
    };
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

    if (_usuarioEsClienteEnDoc(data, myUid)) return false;

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

  /// Viaje espejo Bola Ahorro. Negociación → tablero; operación → ViajeEnCurso*.
  static bool esViajeEspejoBolaParaFlujo(Map<String, dynamic> data) {
    if ((data['tipoServicio'] ?? '').toString().trim() == 'bola_ahorro') {
      return true;
    }
    final pid =
        (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
    return pid.isNotEmpty;
  }

  static String bolaPuebloIdDesdeViajeDoc(Map<String, dynamic> data) {
    return (data['bolaPuebloId'] ?? data['bolaId'] ?? '').toString().trim();
  }

  /// Solo durante negociación abierta (sin conductor asignado en el espejo).
  /// Tras acordar tarifa → mismo flujo que taxi: [ViajeEnCursoTaxista] / [ViajeEnCursoCliente].
  static bool debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(
      Map<String, dynamic> data) {
    if (!esViajeEspejoBolaParaFlujo(data)) return false;

    final String uidTx = (data['uidTaxista'] ?? data['taxistaId'] ?? '')
        .toString()
        .trim();
    final String estadoNorm =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());

    if (estadoNorm == EstadosViaje.enCurso ||
        estadoNorm == EstadosViaje.completado) {
      return false;
    }

    // Tras acordar tarifa: conductor asignado → Mi viaje en curso (no tablero Bola).
    if (uidTx.isNotEmpty) {
      if (data['bolaNegociacionAbierta'] != true) return false;
      if (estadoNorm == EstadosViaje.aceptado ||
          EstadosViaje.activos.contains(estadoNorm)) {
        return false;
      }
    }

    return data['bolaNegociacionAbierta'] == true;
  }

  /// Tras acordar tarifa → [ViajeEnCursoTaxista] / [ViajeEnCursoCliente] (igual que taxi).
  /// Solo negociación abierta usa tablero Bola.
  static bool clientePinBolaPermitidoEnViajeEnCurso({
    required Map<String, dynamic> viajeData,
    required Map<String, dynamic>? bolaData,
  }) {
    if (!esViajeEspejoBolaParaFlujo(viajeData)) return true;
    if (bolaPuebloIdDesdeViajeDoc(viajeData).isEmpty) return true;
    if (!debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(viajeData)) {
      return true;
    }

    // Acordada / operativa: el pasajero debe ver el PIN al llegar al viaje en curso
    // (no esperar pickupConfirmadoTaxista solo para mostrar el código).
    if (bolaData != null) {
      final String estadoBola =
          (bolaData['estado'] ?? '').toString().trim().toLowerCase();
      if (estadoBola == 'acordada' || estadoBola == 'en_curso') {
        return true;
      }
    }

    final String uidTx = (viajeData['uidTaxista'] ?? viajeData['taxistaId'] ?? '')
        .toString()
        .trim();
    if (uidTx.isNotEmpty) {
      final String st =
          EstadosViaje.normalizar((viajeData['estado'] ?? '').toString());
      if (EstadosViaje.activos.contains(st)) return true;
    }

    if (bolaData == null) return false;
    if (!bolaData.containsKey('pickupConfirmadoTaxista')) return true;
    return bolaData['pickupConfirmadoTaxista'] == true;
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
