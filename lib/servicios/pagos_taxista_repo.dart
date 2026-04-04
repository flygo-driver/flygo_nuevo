// lib/servicios/pagos_taxista_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../modelo/pago_taxista.dart';

class PagosTaxistaRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('pagos_taxistas');
  static const List<String> _estadosDeudaAbierta = <String>[
    'pendiente',
    'vencido',
    'pendiente_verificacion',
    'rechazado',
  ];

  static Future<void> _sincronizarBanderaPendiente(String uidTaxista) async {
    // Evita depender de índices compuestos en una ruta crítica de verificación.
    final snap = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .get();
    final bool tieneAbiertos = snap.docs.any((d) {
      final estado = (d.data()['estado'] ?? '').toString().trim().toLowerCase();
      return _estadosDeudaAbierta.contains(estado);
    });
    await _db.collection('usuarios').doc(uidTaxista).set(
      {
        'tienePagoPendiente': tieneAbiertos,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ==============================================================
  // GENERAR PAGO SEMANAL (llamado por Cloud Function o manualmente)
  // ==============================================================
  static Future<void> generarPagoSemanal(String uidTaxista) async {
    try {
      // Calcular fechas de la semana actual
      final now = DateTime.now();
      final fechaFin = DateTime(now.year, now.month, now.day);
      final fechaInicio = fechaFin.subtract(const Duration(days: 7));
      
      // Número de semana
      final semanaStr = _getWeekString(now);

      final String pagoId = '${uidTaxista}_$semanaStr';
      final DocumentReference<Map<String, dynamic>> pagoRef = _col.doc(pagoId);

      // Obtener nombre del taxista
      final userDoc = await _db.collection('usuarios').doc(uidTaxista).get();
      final userData = userDoc.data() ?? {};
      final nombreTaxista = userData['nombre'] ?? 'Sin nombre';

      // Calcular viajes de la semana
      final viajes = await _db
          .collection('viajes')
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('completado', isEqualTo: true)
          .where('finalizadoEn', isGreaterThanOrEqualTo: Timestamp.fromDate(fechaInicio))
          .where('finalizadoEn', isLessThanOrEqualTo: Timestamp.fromDate(fechaFin))
          .get();

      double totalGanado = 0;      // 80% para taxista
      double totalComision = 0;    // 20% para admin
      
      for (var viaje in viajes.docs) {
        final data = viaje.data();
        // ✅ USAR LOS CAMPOS CORRECTOS
        totalGanado += (data['gananciaTaxista'] ?? 0).toDouble();
        totalComision += (data['comision'] ?? 0).toDouble();
      }

      final viajesSemana = viajes.docs.length;

      // Si no hay viajes, no generar pago
      if (viajesSemana == 0) return;

      // Crear documento de pago
      final pago = PagoTaxista(
        id: pagoId,
        uidTaxista: uidTaxista,
        nombreTaxista: nombreTaxista,
        semana: semanaStr,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        totalGanado: totalGanado,
        comision: totalComision,
        netoAPagar: totalGanado, // El taxista recibe el 80%
        estado: 'pendiente',
        viajesSemana: viajesSemana,
      );

      await _db.runTransaction((tx) async {
        final pagoSnap = await tx.get(pagoRef);
        if (pagoSnap.exists) {
          return; // idempotencia fuerte: ya creado para ese taxista+semana
        }
        tx.set(pagoRef, {
          ...pago.toMap(),
          'id': pagoId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(_db.collection('usuarios').doc(uidTaxista), {
          'tienePagoPendiente': true,
          'semanaPendiente': semanaStr,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

    } catch (e) {
      debugPrint('Error generando pago semanal: $e');
    }
  }

  // ==============================================================
  // GENERAR PAGOS PARA TODOS LOS TAXISTAS (ejecutar cada domingo)
  // ==============================================================
  static Future<void> generarPagosSemanales() async {
    try {
      // Obtener todos los taxistas
      final taxistas = await _db
          .collection('usuarios')
          .where('rol', isEqualTo: 'taxista')
          .get();

      for (var taxista in taxistas.docs) {
        await generarPagoSemanal(taxista.id);
      }
    } catch (e) {
      debugPrint('Error generando pagos semanales: $e');
    }
  }

  // ==============================================================
  // VERIFICAR SI TAXISTA PUEDE TRABAJAR
  // ==============================================================
  static Future<bool> puedeTrabajar(String uidTaxista) async {
    try {
      // Verificar si tiene pagos vencidos (más de 2 semanas)
      final now = DateTime.now();
      final dosSemanasAtras = now.subtract(const Duration(days: 14));
      
      final pagosVencidos = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('estado', whereIn: _estadosDeudaAbierta)
          .where('fechaFin', isLessThan: Timestamp.fromDate(dosSemanasAtras))
          .limit(1)
          .get();

      if (pagosVencidos.docs.isNotEmpty) {
        return false; // Bloqueado por deuda
      }

      return true;
    } catch (e) {
      debugPrint('Error verificando si puede trabajar: $e');
      return true; // Por seguridad, permitir trabajar si hay error
    }
  }

  /// Bloqueo operativo estricto para viajes disponibles/aceptación.
  /// Si existe cualquier deuda semanal abierta, no debe tomar nuevos viajes.
  static Future<bool> tieneBloqueoSemanal(String uidTaxista) async {
    try {
      final pendientes = await _col
          .where('uidTaxista', isEqualTo: uidTaxista)
          .where('estado', whereIn: _estadosDeudaAbierta)
          .limit(1)
          .get();
      return pendientes.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando bloqueo semanal: $e');
      // Fallback conservador para producción financiera.
      return true;
    }
  }

  // ==============================================================
  // SUBIR COMPROBANTE DE PAGO (Taxista)
  // ==============================================================
  static Future<void> subirComprobante({
    required String pagoId,
    required String comprobanteUrl,
    required String metodoPago,
  }) async {
    final ref = _col.doc(pagoId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Pago no encontrado');
      final data = snap.data() ?? {};
      final String estado = (data['estado'] ?? '').toString().trim().toLowerCase();
      if (estado == 'pagado') throw Exception('Este pago ya fue aprobado');
      if (estado == 'pendiente_verificacion') {
        final String prevUrl = (data['comprobanteUrl'] ?? '').toString();
        if (prevUrl == comprobanteUrl) return; // idempotencia
      }
      tx.update(ref, {
        'comprobanteUrl': comprobanteUrl,
        'metodoPago': metodoPago,
        'estado': 'pendiente_verificacion',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ==============================================================
  // VERIFICAR PAGO (Admin)
  // ==============================================================
  static Future<void> verificarPago({
    required String pagoId,
    required bool aprobado,
    String? notaAdmin,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final pagoRef = _col.doc(pagoId);
    
    await _db.runTransaction((tx) async {
      final pagoSnap = await tx.get(pagoRef);
      if (!pagoSnap.exists) throw 'Pago no encontrado';

      final pagoData = pagoSnap.data()!;
      final String uidTaxista = (pagoData['uidTaxista'] ?? '').toString();
      final String estadoActual = (pagoData['estado'] ?? '').toString().trim().toLowerCase();
      if (uidTaxista.isEmpty) throw 'Pago sin uidTaxista';
      if (estadoActual == 'pagado' || estadoActual == 'rechazado') {
        final bool coincideAccion = (aprobado && estadoActual == 'pagado') ||
            (!aprobado && estadoActual == 'rechazado');
        if (coincideAccion) return; // idempotente ante doble click/reintento
        throw 'Este pago ya fue procesado';
      }
      if (!(estadoActual == 'pendiente' || estadoActual == 'pendiente_verificacion')) {
        throw 'Estado no válido para verificación: $estadoActual';
      }

      if (aprobado) {
        tx.update(pagoRef, {
          'estado': 'pagado',
          'fechaPago': FieldValue.serverTimestamp(),
          'verificadoPor': user?.uid,
          'verificadoEn': FieldValue.serverTimestamp(),
          'notaAdmin': notaAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(
          _db.collection('usuarios').doc(uidTaxista),
          {
            'semanaPendiente': null,
            'ultimoPago': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        tx.update(pagoRef, {
          'estado': 'rechazado',
          'notaAdmin': notaAdmin ?? 'Comprobante no válido',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    final snap = await pagoRef.get();
    final uidTaxista = (snap.data()?['uidTaxista'] ?? '').toString();
    if (uidTaxista.isNotEmpty) {
      await _sincronizarBanderaPendiente(uidTaxista);
    }
  }

  // ==============================================================
  // BLOQUEAR TAXISTA POR FALTA DE PAGO
  // ==============================================================
  static Future<void> bloquearPorFaltaPago(String uidTaxista, String semana) async {
    await _db.collection('usuarios').doc(uidTaxista).set({
      'bloqueado': true,
      'motivoBloqueo': 'Falta de pago semana $semana',
      'fechaBloqueo': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================================================
  // STREAMS PARA ADMIN
  // ==============================================================
  static Stream<List<PagoTaxista>> streamPagosPendientes() {
    return _col
        .where('estado', whereIn: ['pendiente', 'pendiente_verificacion'])
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
          return list;
        });
  }

  static Stream<List<PagoTaxista>> streamPagosPorTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
              .toList();
          list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
          return list;
        });
  }

  static Stream<List<PagoTaxista>> streamHistorialPagos({
    int limite = 50,
    String? uidTaxista,
  }) {
    Query<Map<String, dynamic>> query = _col;

    if (uidTaxista != null) {
      query = query.where('uidTaxista', isEqualTo: uidTaxista);
    }

    return query.snapshots().map((snap) {
      final list = snap.docs
          .map((doc) => PagoTaxista.fromMap(doc.id, doc.data()))
          .toList();
      list.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
      return list.take(limite).toList();
    });
  }

  // ==============================================================
  // ESTADÍSTICAS PARA ADMIN
  // ==============================================================
  static Future<Map<String, dynamic>> obtenerEstadisticas() async {
    try {
      final now = DateTime.now();
      final inicioMes = DateTime(now.year, now.month, 1);
      final finMes = DateTime(now.year, now.month + 1, 0);

      // Pagos del mes
      final pagosMes = await _col
          .where('fechaFin', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('fechaFin', isLessThanOrEqualTo: Timestamp.fromDate(finMes))
          .get();

      double totalComisiones = 0;
      double totalPagado = 0;
      int taxistasActivos = 0;
      final taxistasSet = <String>{};

      for (var doc in pagosMes.docs) {
        final data = doc.data();
        final estado = data['estado'];
        final comision = (data['comision'] ?? 0).toDouble();
        final uidTaxista = data['uidTaxista'] ?? '';

        totalComisiones += comision;
        taxistasSet.add(uidTaxista);

        if (estado == 'pagado') {
          totalPagado += comision;
        }
      }

      taxistasActivos = taxistasSet.length;

      return {
        'totalComisiones': totalComisiones,
        'totalPagado': totalPagado,
        'totalPendiente': totalComisiones - totalPagado,
        'taxistasActivos': taxistasActivos,
        'porcentajeCobrado': totalComisiones > 0 
            ? (totalPagado / totalComisiones * 100).toStringAsFixed(1)
            : '0',
      };
    } catch (e) {
      debugPrint('Error obteniendo estadísticas: $e');
      return {
        'totalComisiones': 0,
        'totalPagado': 0,
        'totalPendiente': 0,
        'taxistasActivos': 0,
        'porcentajeCobrado': '0',
      };
    }
  }

  // ==============================================================
  // HELPERS
  // ==============================================================
  static String _getWeekString(DateTime date) {
    final semana = _getWeekNumber(date);
    return '${date.year}-${semana.toString().padLeft(2, '0')}';
  }

  static int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final days = date.difference(firstDayOfYear).inDays;
    return ((days - date.weekday + 10) / 7).floor();
  }
}