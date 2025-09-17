// lib/widgets/acciones_viaje_taxista.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ======================
///  SERVICIO (sin UI)
/// ======================
class AccionesViajeTaxistaService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Ajusta estos nombres si tu esquema es distinto
  static const String colSolicitudes = 'solicitudes_viaje';
  static const String colViajes = 'viajes';
  static const String colTaxistas = 'taxistas';
  static const String colUbicaciones = 'ubicaciones_taxistas';

  // Estados sugeridos
  static const String stSolicitudPendiente = 'pendiente';
  static const String stSolicitudAceptada = 'aceptada';
  static const String stSolicitudRechazada = 'rechazada';

  static const String stViajeCreado = 'creado';
  static const String stViajeEnCurso = 'en_curso';
  static const String stViajeFinalizado = 'finalizado';
  static const String stViajeCanceladoTaxista = 'cancelado_taxista';

  static String _uidOrThrow() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No hay sesión del taxista. Inicia sesión primero.');
    }
    return uid;
  }

  /// Aceptar solicitud pendiente y crear viaje
  static Future<String> aceptarSolicitud({required String solicitudId}) async {
    final taxistaId = _uidOrThrow();

    final solRef = _db.collection(colSolicitudes).doc(solicitudId);
    final viajeRef = _db.collection(colViajes).doc();

    await _db.runTransaction((tx) async {
      final solSnap = await tx.get(solRef);
      if (!solSnap.exists) throw StateError('La solicitud no existe.');

      final data = solSnap.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString();
      if (estado != stSolicitudPendiente) {
        throw StateError('La solicitud ya no está disponible (estado: $estado).');
      }

      final clienteId = (data['clienteId'] ?? '').toString();
      final origen = data['origen'];
      final destino = data['destino'];
      final precioEstimado = data['precioEstimado'];

      tx.update(solRef, <String, dynamic>{
        'estado': stSolicitudAceptada,
        'taxistaId': taxistaId,
        'aceptadaAt': FieldValue.serverTimestamp(),
        'viajeId': viajeRef.id,
      });

      tx.set(viajeRef, <String, dynamic>{
        'viajeId': viajeRef.id,
        'solicitudId': solicitudId,
        'clienteId': clienteId,
        'taxistaId': taxistaId,
        'origen': origen,
        'destino': destino,
        'precioEstimado': precioEstimado,
        'estado': stViajeCreado,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return viajeRef.id;
  }

  /// Rechazar solicitud
  static Future<void> rechazarSolicitud({
    required String solicitudId,
    String? motivo,
  }) async {
    final taxistaId = _uidOrThrow();
    final solRef = _db.collection(colSolicitudes).doc(solicitudId);

    await _db.runTransaction((tx) async {
      final solSnap = await tx.get(solRef);
      if (!solSnap.exists) return;

      final data = solSnap.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString();
      if (estado != stSolicitudPendiente) return;

      tx.update(solRef, <String, dynamic>{
        'estado': stSolicitudRechazada,
        'rechazadaAt': FieldValue.serverTimestamp(),
        'rechazadaPor': taxistaId,
        if (motivo != null && motivo.isNotEmpty) 'motivoRechazo': motivo,
      });
    });
  }

  /// Iniciar viaje (de 'creado' -> 'en_curso')
  static Future<void> iniciarViaje({required String viajeId}) async {
    final taxistaId = _uidOrThrow();
    final vRef = _db.collection(colViajes).doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(vRef);
      if (!snap.exists) throw StateError('El viaje no existe.');
      final data = snap.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString();
      if (estado != stViajeCreado) {
        throw StateError('No se puede iniciar. Estado actual: $estado');
      }
      tx.update(vRef, <String, dynamic>{
        'estado': stViajeEnCurso,
        'iniciadoAt': FieldValue.serverTimestamp(),
        'iniciadoPor': taxistaId,
      });
    });
  }

  /// Finalizar viaje (de 'en_curso' -> 'finalizado')
  static Future<void> finalizarViaje({
    required String viajeId,
    num? precioFinal,
    Map<String, dynamic>? extras,
  }) async {
    final taxistaId = _uidOrThrow();
    final vRef = _db.collection(colViajes).doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(vRef);
      if (!snap.exists) throw StateError('El viaje no existe.');
      final data = snap.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString();
      if (estado != stViajeEnCurso) {
        throw StateError('No se puede finalizar. Estado actual: $estado');
      }
      final update = <String, dynamic>{
        'estado': stViajeFinalizado,
        'finalizadoAt': FieldValue.serverTimestamp(),
        'finalizadoPor': taxistaId,
        if (precioFinal != null) 'precioFinal': precioFinal,
      };
      if (extras != null) update.addAll(extras);
      tx.update(vRef, update);
    });
  }

  /// Cancelar viaje por taxista (si no está finalizado)
  static Future<void> cancelarViajePorTaxista({
    required String viajeId,
    String? motivo,
  }) async {
    final taxistaId = _uidOrThrow();
    final vRef = _db.collection(colViajes).doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(vRef);
      if (!snap.exists) throw StateError('El viaje no existe.');
      final data = snap.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString();

      if (estado == stViajeFinalizado) {
        throw StateError('El viaje ya fue finalizado.');
      }

      tx.update(vRef, <String, dynamic>{
        'estado': stViajeCanceladoTaxista,
        'canceladoAt': FieldValue.serverTimestamp(),
        'canceladoPor': taxistaId,
        if (motivo != null && motivo.isNotEmpty) 'motivoCancelacion': motivo,
      });
    });
  }

  /// Tracking de ubicación del taxista
  static Future<void> actualizarUbicacion({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) async {
    final taxistaId = _uidOrThrow();
    final ref = _db.collection(colUbicaciones).doc(taxistaId);

    await ref.set(<String, dynamic>{
      'taxistaId': taxistaId,
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Cambiar disponibilidad
  static Future<void> setDisponible(bool disponible) async {
    final taxistaId = _uidOrThrow();
    final ref = _db.collection(colTaxistas).doc(taxistaId);

    await ref.set(<String, dynamic>{
      'disponible': disponible,
      'disponibleUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// ======================
///  WIDGET (UI de botones)
/// ======================
class AccionesViajeTaxista extends StatefulWidget {
  final String viajeId;
  /// Estados esperados: 'creado', 'en_curso', 'finalizado', etc.
  final String estadoActual;

  const AccionesViajeTaxista({
    super.key,
    required this.viajeId,
    required this.estadoActual,
  });

  @override
  State<AccionesViajeTaxista> createState() => _AccionesViajeTaxistaState();
}

class _AccionesViajeTaxistaState extends State<AccionesViajeTaxista> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() op, String okMsg) async {
    if (_loading) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await op();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estadoActual;

    final List<Widget> botones = [];

    if (estado == 'creado') {
      botones.add(
        ElevatedButton.icon(
          onPressed: _loading
              ? null
              : () => _run(
                    () => AccionesViajeTaxistaService.iniciarViaje(
                      viajeId: widget.viajeId,
                    ),
                    'Viaje iniciado',
                  ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar viaje'),
        ),
      );
    }

    if (estado == 'en_curso') {
      botones.add(
        ElevatedButton.icon(
          onPressed: _loading
              ? null
              : () => _run(
                    () => AccionesViajeTaxistaService.finalizarViaje(
                      viajeId: widget.viajeId,
                    ),
                    'Viaje finalizado',
                  ),
          icon: const Icon(Icons.flag),
          label: const Text('Finalizar viaje'),
        ),
      );
    }

    if (estado != 'finalizado' && estado != 'cancelado_taxista') {
      botones.add(
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => _run(
                    () => AccionesViajeTaxistaService.cancelarViajePorTaxista(
                      viajeId: widget.viajeId,
                    ),
                    'Viaje cancelado',
                  ),
          icon: const Icon(Icons.cancel),
          label: const Text('Cancelar'),
        ),
      );
    }

    if (botones.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ...botones,
      ],
    );
  }
}
