// lib/servicios/negocio_referido_service.dart
//
// Captura código QR de negocio (web / deep link) y lo aplica al perfil cliente.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_codigo.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocios_aliados_repo.dart';

abstract final class NegocioReferidoService {
  NegocioReferidoService._();

  static const String _prefCodigo = 'rai_negocio_ref_pendiente';
  static const String _prefCapturadoEn = 'rai_negocio_ref_capturado_ms';

  /// Lee ?ref= de una URI y guarda pendiente.
  static Future<void> capturarDesdeUri(Uri? uri) async {
    if (uri == null) return;
    final ref = uri.queryParameters['ref']?.trim();
    if (ref == null || ref.isEmpty) return;
    await guardarPendiente(ref);
  }

  /// Web: leer ref de la URL actual al arrancar.
  static Future<void> capturarDesdeUrlActualWeb() async {
    if (!kIsWeb) return;
    try {
      final uri = Uri.base;
      await capturarDesdeUri(uri);
    } catch (e) {
      debugPrint('[NegocioReferido] capturarDesdeUrlActualWeb: $e');
    }
  }

  static Future<void> guardarPendiente(String codigoRaw) async {
    final codigo = NegocioAliadoCodigo.normalizar(codigoRaw);
    if (codigo.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCodigo, codigo);
    await prefs.setInt(
      _prefCapturadoEn,
      DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[NegocioReferido] pendiente=$codigo');
  }

  static Future<String?> consumirPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getString(_prefCodigo)?.trim();
    if (codigo == null || codigo.isEmpty) return null;
    await prefs.remove(_prefCodigo);
    await prefs.remove(_prefCapturadoEn);
    return NegocioAliadoCodigo.normalizar(codigo);
  }

  static Future<String?> peekPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getString(_prefCodigo)?.trim();
    if (c == null || c.isEmpty) return null;
    return NegocioAliadoCodigo.normalizar(c);
  }

  /// Aplica referido al usuario cliente si hay código pendiente y aún no tiene uno.
  static Future<void> aplicarAlUsuarioSiCorresponde({
    required String uid,
    required String rol,
  }) async {
    final r = rol.trim().toLowerCase();
    if (r != 'cliente') return;

    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};
    final existente = (data['negocioReferidoCodigo'] ?? '').toString().trim();
    if (existente.isNotEmpty) return;

    final codigo = await consumirPendiente();
    if (codigo == null || codigo.isEmpty) return;

    final negocio = await NegociosAliadosRepo.obtenerPorCodigo(codigo);
    if (negocio == null || !negocio.activo) {
      debugPrint('[NegocioReferido] código inválido o inactivo: $codigo');
      return;
    }

    final vence = DateTime.now().add(
      const Duration(days: NegocioAliadoConfig.vigenciaDias),
    );

    await ref.set(<String, dynamic>{
      'negocioReferidoCodigo': negocio.codigo,
      'negocioReferidoNombre': negocio.nombre,
      'negocioReferidoCiudad': negocio.ciudad,
      'negocioReferidoOrigen': 'qr_descarga',
      'negocioReferidoAt': FieldValue.serverTimestamp(),
      'negocioPromoMxKM': NegocioAliadoConfig.promoViajesM,
      'negocioPromoMxKK': NegocioAliadoConfig.promoViajesK,
      'negocioPromoVenceAt': Timestamp.fromDate(vence),
      'negocioPromoContador': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection(NegocioAliadoConfig.collection)
        .doc(negocio.codigo)
        .set(<String, dynamic>{
      'clientesReferidos': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('[NegocioReferido] aplicado uid=$uid negocio=${negocio.codigo}');
  }
}
