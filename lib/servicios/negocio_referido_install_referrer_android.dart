import 'package:flutter/services.dart';

/// Android: lee `referrer=ref=CODIGO` de Play Store tras instalar desde QR.
Future<String?> leerCodigoNegocioInstallReferrer() async {
  const channel = MethodChannel('com.flygo.rd2/negocio_referido');
  try {
    final dynamic raw = await channel.invokeMethod<String>('getInstallReferrer');
    final String s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    return _extraerCodigoDesdeReferrer(s);
  } catch (_) {
    return null;
  }
}

String? _extraerCodigoDesdeReferrer(String referrer) {
  final Uri? uri = Uri.tryParse('https://x/?$referrer');
  if (uri != null) {
    final String? ref = uri.queryParameters['ref']?.trim();
    if (ref != null && ref.isNotEmpty) return ref;
  }
  final RegExp rx = RegExp(r'(?:^|[&?])ref=([^&]+)', caseSensitive: false);
  final Match? m = rx.firstMatch(referrer);
  if (m == null) return null;
  return Uri.decodeComponent(m.group(1) ?? '').trim();
}
