// lib/servicios/app_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/recarga_bancaria_config.dart';

class DatosBancarios {
  final String bancoNombre;
  final String tipoCuenta; // "Corriente" | "Ahorros"
  final String numeroCuenta;
  final String titular;
  final String rnc;
  final String alias;
  final String nota;
  final String qrUrl;
  final String whatsappSoporte;

  const DatosBancarios({
    required this.bancoNombre,
    required this.tipoCuenta,
    required this.numeroCuenta,
    required this.titular,
    required this.rnc,
    required this.alias,
    required this.nota,
    required this.qrUrl,
    required this.whatsappSoporte,
  });

  factory DatosBancarios.fromMap(Map<String, dynamic> m) {
    String _s(String k) => (m[k] ?? '').toString();
    return DatosBancarios(
      bancoNombre: _s('banco_nombre'),
      tipoCuenta: _s('tipo_cuenta'),
      numeroCuenta: _s('numero_cuenta'),
      titular: _s('titular'),
      rnc: _s('rnc'),
      alias: _s('alias'),
      nota: _s('nota'),
      qrUrl: _s('qr_url'),
      whatsappSoporte: _s('whatsapp_soporte'),
    );
  }

  Map<String, dynamic> toMap() => {
        'banco_nombre': bancoNombre,
        'tipo_cuenta': tipoCuenta,
        'numero_cuenta': numeroCuenta,
        'titular': titular,
        'rnc': rnc,
        'alias': alias,
        'nota': nota,
        'qr_url': qrUrl,
        'whatsapp_soporte': whatsappSoporte,
      };
}

class AppConfigService {
  AppConfigService._();
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _refPagos() =>
      _db.collection('app_config').doc('pagos');

  /// Valores por defecto producción (misma cuenta que Play / depósitos reales).
  static DatosBancarios get datosBancariosPorDefecto => DatosBancarios(
        bancoNombre: RecargaBancariaConfig.banco,
        tipoCuenta: RecargaBancariaConfig.tipoCuenta,
        numeroCuenta: RecargaBancariaConfig.numeroCuenta,
        titular: RecargaBancariaConfig.titular,
        rnc: RecargaBancariaConfig.rnc,
        alias: '',
        nota: RecargaBancariaConfig.notaRecarga,
        qrUrl: '',
        whatsappSoporte: '',
      );

  static String _pick(String remote, String fallback) {
    final t = remote.trim();
    return t.isNotEmpty ? t : fallback;
  }

  /// Firestore (`app_config/pagos`) con fallback campo a campo a [datosBancariosPorDefecto].
  /// Cuenta empresa (titular, RNC, banco, tipo, número) siempre [RecargaBancariaConfig].
  /// Firestore no puede pisar con placeholders (ej. 000-000000-0).
  static DatosBancarios efectivos(DatosBancarios? remoto) {
    final d = datosBancariosPorDefecto;
    if (remoto == null) return d;
    return DatosBancarios(
      bancoNombre: d.bancoNombre,
      tipoCuenta: d.tipoCuenta,
      numeroCuenta: d.numeroCuenta,
      titular: d.titular,
      rnc: d.rnc,
      alias: _pick(remoto.alias, d.alias),
      nota: _pick(remoto.nota, d.nota),
      qrUrl: _pick(remoto.qrUrl, d.qrUrl),
      whatsappSoporte: _pick(remoto.whatsappSoporte, d.whatsappSoporte),
    );
  }

  /// Stream con datos empresa siempre completos (taxista / Mis pagos).
  static Stream<DatosBancarios> streamDatosBancariosEfectivos() {
    return streamDatosBancarios().map(efectivos);
  }

  /// Lee 1 sola vez la config bancaria (null si no existe).
  static Future<DatosBancarios?> obtenerDatosBancarios() async {
    final snap = await _refPagos().get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return DatosBancarios.fromMap(data);
  }

  /// Stream en vivo de la config bancaria (null si borran el doc).
  static Stream<DatosBancarios?> streamDatosBancarios() {
    return _refPagos().snapshots().map((s) {
      if (!s.exists) return null;
      final data = s.data();
      if (data == null) return null;
      return DatosBancarios.fromMap(data);
    });
  }

  /// Solo para admins: actualizar los datos bancarios.
  static Future<void> actualizarDatosBancarios(DatosBancarios cfg) async {
    await _refPagos().set(cfg.toMap(), SetOptions(merge: true));
  }

  /// Publica en Firestore la cuenta empresa real (merge; no borra campos extra).
  static Future<void> publicarDatosEmpresaProduccion() async {
    await _refPagos().set(
      RecargaBancariaConfig.toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  /// Sugerencia de referencia para transferencias del taxista (TX-<uid>-YYYY-MM).
  static String referenciaSugerida(
      {required String uidTaxista, DateTime? fecha}) {
    final f = fecha ?? DateTime.now();
    final mm = f.month.toString().padLeft(2, '0');
    return 'TX-$uidTaxista-${f.year}-$mm';
  }
}
