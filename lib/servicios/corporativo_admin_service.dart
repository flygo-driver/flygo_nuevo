import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/utils/corporativo_recurrencia_helper.dart';

/// Usuario encontrado en búsqueda admin corporativo.
class CorporativoUsuarioCandidato {
  const CorporativoUsuarioCandidato({
    required this.uid,
    this.nombre = '',
    this.email = '',
    this.telefono = '',
    this.cedula = '',
    this.rol = '',
    this.empresaId = '',
    this.empresaNombre = '',
    this.matchPor = '',
  });

  final String uid;
  final String nombre;
  final String email;
  final String telefono;
  final String cedula;
  final String rol;
  final String empresaId;
  final String empresaNombre;
  final String matchPor;

  factory CorporativoUsuarioCandidato.fromMap(Map<dynamic, dynamic> raw) {
    return CorporativoUsuarioCandidato(
      uid: (raw['uid'] ?? '').toString().trim(),
      nombre: (raw['nombre'] ?? '').toString().trim(),
      email: (raw['email'] ?? '').toString().trim(),
      telefono: (raw['telefono'] ?? '').toString().trim(),
      cedula: (raw['cedula'] ?? '').toString().trim(),
      rol: (raw['rol'] ?? '').toString().trim(),
      empresaId: (raw['empresaId'] ?? '').toString().trim(),
      empresaNombre: (raw['empresaNombre'] ?? '').toString().trim(),
      matchPor: (raw['matchPor'] ?? '').toString().trim(),
    );
  }

  String get subtitulo {
    final parts = <String>[
      if (email.isNotEmpty) email,
      if (telefono.isNotEmpty) 'Tel $telefono',
      if (cedula.isNotEmpty) 'Céd. $cedula',
      if (empresaNombre.isNotEmpty) 'Empresa: $empresaNombre',
    ];
    return parts.isEmpty ? 'Usuario RAI' : parts.join(' · ');
  }
}

/// Empresa encontrada en búsqueda admin.
class CorporativoEmpresaCandidato {
  const CorporativoEmpresaCandidato({
    required this.empresaId,
    this.empresaNombre = '',
    this.documentoLegal = '',
    this.activa = true,
    this.contratoActivo = false,
  });

  final String empresaId;
  final String empresaNombre;
  final String documentoLegal;
  final bool activa;
  final bool contratoActivo;

  factory CorporativoEmpresaCandidato.fromMap(Map<dynamic, dynamic> raw) {
    return CorporativoEmpresaCandidato(
      empresaId: (raw['empresaId'] ?? '').toString().trim(),
      empresaNombre: (raw['empresaNombre'] ?? '').toString().trim(),
      documentoLegal: (raw['documentoLegal'] ?? '').toString().trim(),
      activa: raw['activa'] != false,
      contratoActivo: raw['contratoActivo'] == true,
    );
  }
}

class CorporativoBusquedaResultado {
  const CorporativoBusquedaResultado({
    this.tipoUsado = 'auto',
    this.usuarios = const [],
    this.empresas = const [],
  });

  final String tipoUsado;
  final List<CorporativoUsuarioCandidato> usuarios;
  final List<CorporativoEmpresaCandidato> empresas;
}

/// Resultado de búsqueda de conductor en admin corporativo.
class CorporativoChoferCandidato {
  const CorporativoChoferCandidato({
    required this.uid,
    this.nombre = '',
    this.telefono = '',
    this.email = '',
    this.cedula = '',
    this.placa = '',
    this.marca = '',
    this.modelo = '',
    this.enPool = false,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String email;
  final String cedula;
  final String placa;
  final String marca;
  final String modelo;
  final bool enPool;

  String get vehiculoLabel {
    final parts = [marca, modelo].where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  factory CorporativoChoferCandidato.fromMap(Map<dynamic, dynamic> raw) {
    return CorporativoChoferCandidato(
      uid: (raw['uid'] ?? '').toString().trim(),
      nombre: (raw['nombre'] ?? '').toString().trim(),
      telefono: (raw['telefono'] ?? '').toString().trim(),
      email: (raw['email'] ?? '').toString().trim(),
      cedula: (raw['cedula'] ?? '').toString().trim(),
      placa: (raw['placa'] ?? '').toString().trim(),
      marca: (raw['marca'] ?? '').toString().trim(),
      modelo: (raw['modelo'] ?? '').toString().trim(),
      enPool: raw['enPool'] == true,
    );
  }
}

/// Ruta corporativa con chofer fijo asignado (vista admin).
class CorporativoAsignacionRutaAdmin {
  const CorporativoAsignacionRutaAdmin({
    required this.choferUid,
    required this.choferNombre,
    required this.choferTelefono,
    this.choferEmail = '',
    required this.empresaId,
    required this.empresaNombre,
    required this.plantillaId,
    required this.plantillaNombre,
    required this.horaRecogida,
    required this.diasLabel,
    required this.pasajerosActivos,
    required this.origenLabel,
    this.activa = true,
    this.precioAcordado = 0,
  });

  final String choferUid;
  final String choferNombre;
  final String choferTelefono;
  final String choferEmail;
  final String empresaId;
  final String empresaNombre;
  final String plantillaId;
  final String plantillaNombre;
  final String horaRecogida;
  final String diasLabel;
  final int pasajerosActivos;
  final String origenLabel;
  final bool activa;
  final double precioAcordado;

  String get tituloChoferEmpresa =>
      '$choferNombre está asignado para $empresaNombre';

  String get detalleRuta {
    final tarifa = precioAcordado > 0
        ? ' · RD\$ ${precioAcordado.toStringAsFixed(0)}'
        : '';
    return '«$plantillaNombre» · $horaRecogida · $diasLabel · '
        '$pasajerosActivos pasajero(s)$tarifa · $origenLabel';
  }
}

/// Plantilla corporativa con contexto de empresa (vista admin multi-empresa).
class CorporativoPlantillaConEmpresa {
  const CorporativoPlantillaConEmpresa({
    required this.empresaId,
    required this.empresaNombre,
    required this.plantilla,
  });

  final String empresaId;
  final String empresaNombre;
  final CorporativoPlantilla plantilla;
}

/// Operaciones admin sobre cuentas y empresas corporativas (callable backend).
abstract final class CorporativoAdminService {
  CorporativoAdminService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static final _db = FirebaseFirestore.instance;

  /// Marca liquidación archivada como pagada (período ya cerrado automáticamente).
  static Future<void> marcarLiquidacionPagada({
    required String empresaId,
    required String liquidacionId,
  }) async {
    final emp = empresaId.trim();
    final liq = liquidacionId.trim();
    if (emp.isEmpty || liq.isEmpty) {
      throw ArgumentError('empresaId o liquidacionId vacío');
    }
    await _fn.httpsCallable('marcarLiquidacionCorporativoPagada').call({
      'empresaId': emp,
      'liquidacionId': liq,
    });
  }

  /// Marca período pagado y pone acumulado en cero (solo admin RAI).
  static Future<String?> marcarCuentaPagada(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) throw ArgumentError('empresaId vacío');
    final res = await _fn.httpsCallable('marcarCuentaCorporativoPagada').call({
      'empresaId': id,
    });
    final data = res.data;
    if (data is Map) {
      return (data['codigoAcceso'] ?? '').toString().trim();
    }
    return null;
  }

  /// Busca UID de usuario por correo (Auth + Firestore, case-insensitive).
  static Future<String?> resolverUidPorEmail(String email) async {
    final datos = await buscarUsuarioPorEmail(email);
    final uid = (datos['uid'] ?? '').trim();
    return uid.isEmpty ? null : uid;
  }

  /// Busca usuario RAI por correo y trae nombre/cédula/tel del perfil.
  static Future<Map<String, String>> buscarUsuarioPorEmail(String email) async {
    final resultados = await buscarCorporativo(busqueda: email, tipoBusqueda: 'email');
    if (resultados.usuarios.isEmpty) {
      // Fallback legacy
      final normalized = email.trim().toLowerCase();
      if (!normalized.contains('@')) return {};
      try {
        final res = await _fn.httpsCallable('adminResolverUsuarioPorEmail').call({
          'email': normalized,
        });
        final data = res.data;
        if (data is! Map) return {};
        return {
          'uid': (data['uid'] ?? '').toString().trim(),
          'nombre': (data['nombre'] ?? '').toString().trim(),
          'cedula': (data['cedula'] ?? '').toString().trim(),
          'telefono': (data['telefono'] ?? '').toString().trim(),
          'email': (data['email'] ?? normalized).toString().trim(),
          'rol': (data['rol'] ?? '').toString().trim(),
        };
      } catch (_) {
        return {};
      }
    }
    final u = resultados.usuarios.first;
    return {
      'uid': u.uid,
      'nombre': u.nombre,
      'cedula': u.cedula,
      'telefono': u.telefono,
      'email': u.email,
      'rol': u.rol,
    };
  }

  /// Búsqueda coherente: nombre, correo, teléfono, cédula o empresa.
  static Future<CorporativoBusquedaResultado> buscarCorporativo({
    required String busqueda,
    String tipoBusqueda = 'auto',
  }) async {
    final q = busqueda.trim();
    if (q.length < 2) return const CorporativoBusquedaResultado();
    final res = await _fn.httpsCallable('adminBuscarCorporativo').call({
      'busqueda': q,
      'tipoBusqueda': tipoBusqueda.trim().isEmpty ? 'auto' : tipoBusqueda.trim(),
    });
    final data = res.data;
    if (data is! Map) return const CorporativoBusquedaResultado();
    final usuariosRaw = data['usuarios'];
    final empresasRaw = data['empresas'];
    return CorporativoBusquedaResultado(
      tipoUsado: (data['tipoUsado'] ?? 'auto').toString(),
      usuarios: usuariosRaw is List
          ? usuariosRaw
              .whereType<Map>()
              .map(CorporativoUsuarioCandidato.fromMap)
              .where((u) => u.uid.isNotEmpty)
              .toList(growable: false)
          : const [],
      empresas: empresasRaw is List
          ? empresasRaw
              .whereType<Map>()
              .map(CorporativoEmpresaCandidato.fromMap)
              .where((e) => e.empresaId.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  /// Datos del usuario para prellenar formulario admin.
  static Future<Map<String, String>> datosUsuario(String uid) async {
    final snap = await _db.collection('usuarios').doc(uid.trim()).get();
    if (!snap.exists) return {};
    final u = snap.data() ?? {};
    return {
      'nombre': (u['nombre'] ?? u['displayName'] ?? '').toString().trim(),
      'cedula': (u['cedula'] ?? u['ciTaxista'] ?? '').toString().trim(),
      'telefono': (u['telefono'] ?? u['whatsapp'] ?? '').toString().trim(),
      'email': (u['email'] ?? u['correo'] ?? '').toString().trim().toLowerCase(),
    };
  }

  /// Crea empresa + encargado (contrato pendiente de activar).
  static Future<String> crearEmpresa({
    required String nombreEmpresa,
    String encargadoUid = '',
    String encargadoEmail = '',
    String tipoDocumento = 'rnc',
    required String documentoLegal,
    String telefonoEmpresa = '',
    String emailEmpresa = '',
    String direccion = '',
    String encargadoNombre = '',
    String encargadoCedula = '',
    String encargadoTelefono = '',
    int facturacionCicloDias = 15,
    String formaPagoRai = 'transferencia',
    int contratoMeses = 12,
  }) async {
    final res = await _fn.httpsCallable('adminCrearEmpresaCorporativa').call({
      'nombreEmpresa': nombreEmpresa.trim(),
      if (encargadoUid.trim().isNotEmpty) 'encargadoUid': encargadoUid.trim(),
      if (encargadoEmail.trim().isNotEmpty)
        'encargadoEmail': encargadoEmail.trim(),
      'tipoDocumento': tipoDocumento.trim(),
      'documentoLegal': documentoLegal.trim(),
      if (telefonoEmpresa.trim().isNotEmpty)
        'telefonoEmpresa': telefonoEmpresa.trim(),
      if (emailEmpresa.trim().isNotEmpty) 'emailEmpresa': emailEmpresa.trim(),
      if (direccion.trim().isNotEmpty) 'direccion': direccion.trim(),
      if (encargadoNombre.trim().isNotEmpty)
        'encargadoNombre': encargadoNombre.trim(),
      if (encargadoCedula.trim().isNotEmpty)
        'encargadoCedula': encargadoCedula.trim(),
      if (encargadoTelefono.trim().isNotEmpty)
        'encargadoTelefono': encargadoTelefono.trim(),
      'facturacionCicloDias': facturacionCicloDias,
      if (formaPagoRai.trim().isNotEmpty)
        'formaPagoRai': formaPagoRai.trim().toLowerCase(),
      'contratoMeses': contratoMeses,
    });
    final data = res.data;
    if (data is! Map) throw Exception('Respuesta inválida');
    final id = (data['empresaId'] ?? '').toString().trim();
    if (id.isEmpty) throw Exception('No se creó la empresa');
    return id;
  }

  /// Actualiza datos de empresa corporativa.
  static Future<void> actualizarEmpresa({
    required String empresaId,
    String nombreEmpresa = '',
    String tipoDocumento = '',
    String documentoLegal = '',
    String telefonoEmpresa = '',
    String emailEmpresa = '',
    String direccion = '',
    int facturacionCicloDias = 0,
    String? formaPagoRai,
    double? tarifaViajeContratadaRd,
  }) async {
    await _fn.httpsCallable('adminActualizarEmpresaCorporativa').call({
      'empresaId': empresaId.trim(),
      if (nombreEmpresa.trim().isNotEmpty) 'nombreEmpresa': nombreEmpresa.trim(),
      if (tipoDocumento.trim().isNotEmpty) 'tipoDocumento': tipoDocumento.trim(),
      if (documentoLegal.trim().isNotEmpty)
        'documentoLegal': documentoLegal.trim(),
      if (telefonoEmpresa.trim().isNotEmpty)
        'telefonoEmpresa': telefonoEmpresa.trim(),
      if (emailEmpresa.trim().isNotEmpty) 'emailEmpresa': emailEmpresa.trim(),
      if (direccion.trim().isNotEmpty) 'direccion': direccion.trim(),
      if (facturacionCicloDias > 0)
        'facturacionCicloDias': facturacionCicloDias,
      if (formaPagoRai != null)
        'formaPagoRai': formaPagoRai.trim().toLowerCase(),
      if (tarifaViajeContratadaRd != null)
        'tarifaViajeContratadaRd': tarifaViajeContratadaRd.round(),
    });
  }

  /// Activa contrato de servicio (empresa puede operar rutas).
  static Future<void> activarContrato({
    required String empresaId,
    int contratoMeses = 12,
    double tarifaViajeContratadaRd = 0,
  }) async {
    await _fn.httpsCallable('adminActivarContratoCorporativo').call({
      'empresaId': empresaId.trim(),
      'contratoMeses': contratoMeses,
      if (tarifaViajeContratadaRd > 0)
        'tarifaViajeContratadaRd': tarifaViajeContratadaRd.round(),
    });
  }

  /// Agrega encargado a empresa existente.
  static Future<void> agregarEncargado({
    required String empresaId,
    String encargadoUid = '',
    String encargadoEmail = '',
    String encargadoNombre = '',
    String encargadoCedula = '',
    String encargadoTelefono = '',
  }) async {
    await _fn.httpsCallable('adminAgregarEncargadoCorporativo').call({
      'empresaId': empresaId.trim(),
      if (encargadoUid.trim().isNotEmpty) 'encargadoUid': encargadoUid.trim(),
      if (encargadoEmail.trim().isNotEmpty)
        'encargadoEmail': encargadoEmail.trim(),
      if (encargadoNombre.trim().isNotEmpty)
        'encargadoNombre': encargadoNombre.trim(),
      if (encargadoCedula.trim().isNotEmpty)
        'encargadoCedula': encargadoCedula.trim(),
      if (encargadoTelefono.trim().isNotEmpty)
        'encargadoTelefono': encargadoTelefono.trim(),
    });
  }

  /// Refresca nombre/tel/cédula de encargados desde su perfil de usuario RAI.
  static Future<void> sincronizarEncargados(String empresaId) async {
    await _fn.httpsCallable('adminSincronizarEncargadosCorporativo').call({
      'empresaId': empresaId.trim(),
    });
  }

  /// Soft-delete: desactiva empresa (deja de operar).
  static Future<void> desactivarEmpresa(String empresaId) async {
    await _fn.httpsCallable('adminDesactivarEmpresaCorporativa').call({
      'empresaId': empresaId.trim(),
    });
  }

  /// Reactiva empresa desactivada.
  static Future<void> reactivarEmpresa(String empresaId) async {
    await _fn.httpsCallable('adminReactivarEmpresaCorporativa').call({
      'empresaId': empresaId.trim(),
    });
  }

  /// Busca conductores por teléfono, correo, cédula o nombre.
  static Future<List<CorporativoChoferCandidato>> buscarChoferes({
    required String busqueda,
    String tipoBusqueda = 'auto',
  }) async {
    final q = busqueda.trim();
    if (q.length < 3) return [];
    try {
      final res = await _fn.httpsCallable('adminBuscarChoferRai').call({
        'busqueda': q,
        'tipoBusqueda':
            tipoBusqueda.trim().isEmpty ? 'auto' : tipoBusqueda.trim(),
      });
      final data = res.data;
      if (data is Map) {
        final raw = data['candidatos'];
        if (raw is List && raw.isNotEmpty) {
          return raw
              .whereType<Map>()
              .map((e) => CorporativoChoferCandidato.fromMap(e))
              .where((c) => c.uid.isNotEmpty)
              .toList(growable: false);
        }
      }
    } catch (_) {
      // Callable no desplegado o error temporal → respaldo Firestore directo.
    }
    return _buscarChoferesLocal(q, tipoBusqueda);
  }

  static bool _esRolTaxista(Map<String, dynamic> u) {
    final rol = (u['rol'] ?? '').toString().toLowerCase();
    return rol == 'taxista' || rol == 'conductor' || rol == 'driver';
  }

  static Future<List<CorporativoChoferCandidato>> _buscarChoferesLocal(
    String q,
    String tipoBusqueda,
  ) async {
    final out = <CorporativoChoferCandidato>[];
    final seen = <String>{};

    Future<void> pushUsuario(
      String uid,
      Map<String, dynamic> u, {
      bool enPool = false,
    }) async {
      if (uid.isEmpty || seen.contains(uid) || !_esRolTaxista(u)) return;
      var enP = enPool;
      if (!enP) {
        try {
          final pool = await _db.collection('choferes_corporativos').doc(uid).get();
          enP = pool.exists && pool.data()?['activo'] != false;
        } catch (_) {}
      }
      seen.add(uid);
      out.add(
        CorporativoChoferCandidato(
          uid: uid,
          nombre: (u['nombre'] ?? u['displayName'] ?? '').toString().trim(),
          telefono: (u['telefono'] ?? '').toString().trim(),
          email: (u['email'] ?? u['correo'] ?? '').toString().trim(),
          cedula: (u['ciTaxista'] ?? u['cedula'] ?? u['cedulaTaxista'] ?? '')
              .toString()
              .trim(),
          placa: (u['placa'] ?? '').toString().trim(),
          marca: (u['vehiculoMarca'] ?? u['marca'] ?? '').toString().trim(),
          modelo: (u['vehiculoModelo'] ?? u['modelo'] ?? '').toString().trim(),
          enPool: enP,
        ),
      );
    }

    final tipo = tipoBusqueda.trim().isEmpty ? 'auto' : tipoBusqueda.trim();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final needle = q.toLowerCase();

    if (tipo == 'email' || q.contains('@')) {
      for (final mail in [q.toLowerCase(), q]) {
        final snap = await _db
            .collection('usuarios')
            .where('email', isEqualTo: mail)
            .limit(4)
            .get();
        for (final d in snap.docs) {
          await pushUsuario(d.id, d.data());
        }
      }
      return out;
    }

    if (tipo == 'telefono' || digits.length >= 10) {
      final tel = digits.length >= 10 ? digits : q;
      final poolSnap = await _db
          .collection('choferes_corporativos')
          .where('telefono', isGreaterThanOrEqualTo: tel)
          .where('telefono', isLessThanOrEqualTo: '$tel\uf8ff')
          .limit(10)
          .get();
      for (final d in poolSnap.docs) {
        final c = d.data();
        final uSnap = await _db.collection('usuarios').doc(d.id).get();
        final u = uSnap.data() ?? c;
        await pushUsuario(d.id, u, enPool: true);
      }
      final uSnap = await _db
          .collection('usuarios')
          .where('telefono', isGreaterThanOrEqualTo: tel)
          .where('telefono', isLessThanOrEqualTo: '$tel\uf8ff')
          .limit(10)
          .get();
      for (final d in uSnap.docs) {
        await pushUsuario(d.id, d.data());
      }
      return out;
    }

    final poolAll = await _db.collection('choferes_corporativos').limit(80).get();
    for (final d in poolAll.docs) {
      final c = d.data();
      final nombre = (c['nombre'] ?? '').toString().toLowerCase();
      final tel = (c['telefono'] ?? '').toString();
      final mail = (c['email'] ?? '').toString().toLowerCase();
      if (!nombre.contains(needle) &&
          !tel.contains(digits) &&
          !mail.contains(needle)) {
        continue;
      }
      final uSnap = await _db.collection('usuarios').doc(d.id).get();
      await pushUsuario(d.id, uSnap.data() ?? c, enPool: true);
      if (out.length >= 12) break;
    }

    if (out.isEmpty) {
      final variant = q.isNotEmpty
          ? q[0].toUpperCase() + q.substring(1).toLowerCase()
          : q;
      final uSnap = await _db
          .collection('usuarios')
          .where('nombre', isGreaterThanOrEqualTo: variant)
          .where('nombre', isLessThanOrEqualTo: '$variant\uf8ff')
          .limit(15)
          .get();
      for (final d in uSnap.docs) {
        final nombre =
            (d.data()['nombre'] ?? d.data()['displayName'] ?? '').toString();
        if (!nombre.toLowerCase().contains(needle)) continue;
        await pushUsuario(d.id, d.data());
        if (out.length >= 12) break;
      }
    }

    return out;
  }

  /// Asigna conductor por teléfono (habilita pool + amarra a la ruta).
  /// Si hay choque de horario con otra empresa, [forzar] confirma igual.
  static Future<Map<String, dynamic>> asignarChoferPlantilla({
    required String empresaId,
    required String plantillaId,
    String? choferUid,
    String? busqueda,
    String tipoBusqueda = 'telefono',
    String? telefonoChofer,
    bool forzar = false,
  }) async {
    final res = await _fn.httpsCallable('adminAsignarChoferPlantilla').call({
      'empresaId': empresaId.trim(),
      'plantillaId': plantillaId.trim(),
      if (choferUid != null && choferUid.trim().isNotEmpty)
        'choferUid': choferUid.trim(),
      if (busqueda != null && busqueda.trim().isNotEmpty) 'busqueda': busqueda.trim(),
      if (tipoBusqueda.trim().isNotEmpty) 'tipoBusqueda': tipoBusqueda.trim(),
      if (telefonoChofer != null && telefonoChofer.trim().isNotEmpty)
        'telefonoChofer': telefonoChofer.trim(),
      'forzar': forzar,
    });
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ok': true, 'asignado': true};
  }

  /// Quita conductor de plantilla corporativa.
  static Future<void> desasignarChoferPlantilla({
    required String empresaId,
    required String plantillaId,
  }) async {
    await _fn.httpsCallable('adminDesasignarChoferPlantilla').call({
      'empresaId': empresaId.trim(),
      'plantillaId': plantillaId.trim(),
    });
  }

  /// Admin: elimina la ruta/plantilla completa.
  static Future<int> eliminarPlantilla({
    required String empresaId,
    required String plantillaId,
  }) async {
    final res = await _fn.httpsCallable('adminEliminarRutaCorporativa').call({
      'empresaId': empresaId.trim(),
      'plantillaId': plantillaId.trim(),
    });
    final data = res.data;
    if (data is Map) {
      return (data['viajesCancelados'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Admin: cambia hora de recogida y propaga al chofer / encargado en tiempo real.
  static Future<Map<String, dynamic>> actualizarHoraPlantilla({
    required String empresaId,
    required String plantillaId,
    required String horaNueva,
    bool forzar = false,
  }) async {
    final res = await _fn
        .httpsCallable('adminActualizarHoraPlantillaCorporativa')
        .call({
      'empresaId': empresaId.trim(),
      'plantillaId': plantillaId.trim(),
      'horaNueva': horaNueva.trim(),
      if (forzar) 'forzar': true,
    });
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'ok': true};
  }

  /// Habilita taxista en pool corporativo (admin directo).
  static Future<void> habilitarChoferCorporativo({
    String choferUid = '',
    String telefono = '',
  }) async {
    await _fn.httpsCallable('adminHabilitarChoferCorporativo').call({
      if (choferUid.trim().isNotEmpty) 'choferUid': choferUid.trim(),
      if (telefono.trim().isNotEmpty) 'telefono': telefono.trim(),
    });
  }

  /// Quita taxista del pool corporativo.
  static Future<void> deshabilitarChoferCorporativo({
    required String choferUid,
  }) async {
    await _fn.httpsCallable('adminDeshabilitarChoferCorporativo').call({
      'choferUid': choferUid.trim(),
    });
  }


  static int _pasajerosActivosCount(Map<String, dynamic> data) {
    final raw = data['pasajeros'];
    if (raw is! List) return 0;
    return raw.where((p) {
      if (p is! Map) return false;
      return p['activo'] != false;
    }).length;
  }

  /// Choferes habilitados en pool corporativo (lista completa).
  static Stream<List<CorporativoChoferCandidato>> streamChoferesPoolActivos() {
    return _db
        .collection('choferes_corporativos')
        .where('estado', whereIn: ['aprobado', 'activo'])
        .limit(120)
        .snapshots()
        .map((snap) {
      final out = <CorporativoChoferCandidato>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['activo'] == false) continue;
        out.add(
          CorporativoChoferCandidato(
            uid: d.id,
            nombre: (data['nombre'] ?? '').toString().trim(),
            telefono: (data['telefono'] ?? '').toString().trim(),
            email: (data['email'] ?? '').toString().trim(),
            cedula: (data['cedula'] ?? '').toString().trim(),
            placa: (data['placa'] ?? '').toString().trim(),
            marca: (data['marca'] ?? '').toString().trim(),
            modelo: (data['modelo'] ?? '').toString().trim(),
            enPool: true,
          ),
        );
      }
      out.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      return out;
    });
  }

  /// Todas las rutas con chofer fijo asignado (tiempo real).
  /// Lee por subcolección de cada empresa (evita permission-denied de collectionGroup).
  static Stream<List<CorporativoAsignacionRutaAdmin>> streamAsignacionesRutas() {
    return Stream.multi((controller) {
      Map<String, String> empresasNombres = {};
      final plantillasPorEmpresa =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final subs = <String, StreamSubscription<dynamic>>{};
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? empresasSub;
      Map<String, String> choferEmails = {};

      void emit() {
        final list = <CorporativoAsignacionRutaAdmin>[];
        for (final entry in plantillasPorEmpresa.entries) {
          final empresaId = entry.key;
          final nombreEmp = empresasNombres[empresaId]?.trim().isNotEmpty == true
              ? empresasNombres[empresaId]!.trim()
              : 'Empresa $empresaId';
          for (final doc in entry.value) {
            final item = _asignacionDesdePlantillaDoc(
              doc: doc,
              empresaId: empresaId,
              empresaNombre: nombreEmp,
              choferEmail: choferEmails,
            );
            if (item != null) list.add(item);
          }
        }
        list.sort((a, b) {
          final c = a.choferNombre.toLowerCase().compareTo(
                b.choferNombre.toLowerCase(),
              );
          if (c != 0) return c;
          return a.empresaNombre.toLowerCase().compareTo(
                b.empresaNombre.toLowerCase(),
              );
        });
        controller.add(list);
      }

      void cancelarSubsPlantillasExcept(Set<String> empresaIds) {
        for (final id in subs.keys.toList()) {
          if (id.startsWith('pl:') && !empresaIds.contains(id.substring(3))) {
            subs[id]?.cancel();
            subs.remove(id);
            plantillasPorEmpresa.remove(id.substring(3));
          }
        }
      }

      subs['choferes'] = _db
          .collection('choferes_corporativos')
          .where('estado', whereIn: ['aprobado', 'activo'])
          .limit(120)
          .snapshots()
          .listen(
        (snap) {
          choferEmails = {
            for (final d in snap.docs)
              d.id: (d.data()['email'] ?? '').toString().trim(),
          };
          emit();
        },
        onError: controller.addError,
      );

      empresasSub = _db.collection('empresas_corporativas').snapshots().listen(
        (snap) {
          empresasNombres = {
            for (final d in snap.docs)
              d.id: ((d.data()['nombre'] ??
                          d.data()['nombreComercial'] ??
                          d.id) as Object)
                      .toString()
                      .trim(),
          };
          final ids = snap.docs.map((d) => d.id).toSet();
          cancelarSubsPlantillasExcept(ids);

          for (final d in snap.docs) {
            final eid = d.id;
            final subKey = 'pl:$eid';
            if (subs.containsKey(subKey)) continue;
            subs[subKey] = _db
                .collection('empresas_corporativas')
                .doc(eid)
                .collection('plantillas_ruta')
                .snapshots()
                .listen(
              (plSnap) {
                plantillasPorEmpresa[eid] = plSnap.docs;
                emit();
              },
              onError: controller.addError,
            );
          }
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        empresasSub?.cancel();
        for (final s in subs.values) {
          s.cancel();
        }
        subs.clear();
      };
    });
  }

  static CorporativoAsignacionRutaAdmin? _asignacionDesdePlantillaDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String empresaId,
    required String empresaNombre,
    Map<String, String> choferEmail = const {},
  }) {
    final data = doc.data();
    final choferUid = (data['choferPreferidoUid'] ?? '').toString().trim();
    if (choferUid.isEmpty) return null;
    if (data['activa'] == false) return null;

    final nombreEmp = empresaNombre.trim().isNotEmpty
        ? empresaNombre.trim()
        : 'Empresa $empresaId';
    final nombrePl = (data['nombre'] ?? '').toString().trim();

    return CorporativoAsignacionRutaAdmin(
      choferUid: choferUid,
      choferNombre:
          (data['choferPreferidoNombre'] ?? 'Conductor RAI').toString().trim(),
      choferTelefono: (data['choferPreferidoTelefono'] ?? '').toString().trim(),
      choferEmail: choferEmail[choferUid] ?? '',
      empresaId: empresaId,
      empresaNombre: nombreEmp,
      plantillaId: doc.id,
      plantillaNombre:
          nombrePl.isEmpty ? 'Ruta corporativa' : nombrePl,
      horaRecogida: (data['horaRecogidaGrupo'] ?? data['horaRecogida'] ?? '—')
          .toString()
          .trim(),
      diasLabel: CorporativoPatronRecurrencia.etiqueta(
        (data['patronRecurrencia'] ?? '').toString(),
      ),
      pasajerosActivos: _pasajerosActivosCount(data),
      origenLabel: (data['origenLabel'] ?? data['origen'] ?? '—').toString(),
      activa: data['activa'] != false,
      precioAcordado: (data['precioAcordado'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, List<CorporativoAsignacionRutaAdmin>> agruparAsignacionesPorChofer(
    List<CorporativoAsignacionRutaAdmin> items,
  ) {
    final map = <String, List<CorporativoAsignacionRutaAdmin>>{};
    for (final item in items) {
      map.putIfAbsent(item.choferUid, () => []).add(item);
    }
    return map;
  }

  /// Búsqueda admin: nombre, correo, teléfono, empresa, ruta, UID.
  static bool asignacionCoincideBusqueda(
    CorporativoAsignacionRutaAdmin a,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final campos = [
      a.choferNombre,
      a.choferTelefono,
      a.choferEmail,
      a.choferUid,
      a.empresaNombre,
      a.empresaId,
      a.plantillaNombre,
      a.origenLabel,
      a.horaRecogida,
      a.diasLabel,
    ];
    return campos.any((c) => c.toLowerCase().contains(q));
  }

  /// Todas las plantillas activas de todas las empresas (tiempo real).
  static Stream<List<CorporativoPlantillaConEmpresa>> streamPlantillasTodasEmpresas() {
    return Stream.multi((controller) {
      Map<String, String> empresasNombres = {};
      final plantillasPorEmpresa =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final subs = <String, StreamSubscription<dynamic>>{};
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? empresasSub;

      void emit() {
        final list = <CorporativoPlantillaConEmpresa>[];
        for (final entry in plantillasPorEmpresa.entries) {
          final empresaId = entry.key;
          final nombreEmp = empresasNombres[empresaId]?.trim().isNotEmpty == true
              ? empresasNombres[empresaId]!.trim()
              : 'Empresa $empresaId';
          for (final doc in entry.value) {
            final data = doc.data();
            if (data['activa'] == false) continue;
            try {
              final pl = CorporativoPlantilla.fromDoc(doc);
              list.add(
                CorporativoPlantillaConEmpresa(
                  empresaId: empresaId,
                  empresaNombre: nombreEmp,
                  plantilla: pl,
                ),
              );
            } catch (_) {
              // Doc mal formado: no tumbar toda la lista admin.
            }
          }
        }
        list.sort((a, b) {
          final ec = a.empresaNombre.toLowerCase().compareTo(
                b.empresaNombre.toLowerCase(),
              );
          if (ec != 0) return ec;
          final hc = a.plantilla.horaRecogidaGrupo.compareTo(
                b.plantilla.horaRecogidaGrupo,
              );
          if (hc != 0) return hc;
          return a.plantilla.nombre.toLowerCase().compareTo(
                b.plantilla.nombre.toLowerCase(),
              );
        });
        controller.add(list);
      }

      void cancelarSubsPlantillasExcept(Set<String> empresaIds) {
        for (final id in subs.keys.toList()) {
          if (id.startsWith('pl:') && !empresaIds.contains(id.substring(3))) {
            subs[id]?.cancel();
            subs.remove(id);
            plantillasPorEmpresa.remove(id.substring(3));
          }
        }
      }

      empresasSub = _db.collection('empresas_corporativas').snapshots().listen(
        (snap) {
          empresasNombres = {
            for (final d in snap.docs)
              d.id: ((d.data()['nombre'] ??
                          d.data()['nombreComercial'] ??
                          d.id) as Object)
                      .toString()
                      .trim(),
          };
          final ids = snap.docs.map((d) => d.id).toSet();
          cancelarSubsPlantillasExcept(ids);

          for (final d in snap.docs) {
            final eid = d.id;
            final subKey = 'pl:$eid';
            if (subs.containsKey(subKey)) continue;
            subs[subKey] = _db
                .collection('empresas_corporativas')
                .doc(eid)
                .collection('plantillas_ruta')
                .snapshots()
                .listen(
              (plSnap) {
                plantillasPorEmpresa[eid] = plSnap.docs;
                emit();
              },
              onError: controller.addError,
            );
          }
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        empresasSub?.cancel();
        for (final s in subs.values) {
          s.cancel();
        }
        subs.clear();
      };
    });
  }
}
