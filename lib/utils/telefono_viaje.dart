// lib/utils/telefono_viaje.dart
// Normalización y URIs compartidos: DetalleViaje + viaje en curso (cliente/taxista).
import 'package:url_launcher/url_launcher.dart';

/// Dígitos para E.164 RD típico (prefijo 1 si faltaba en número de 10 cifras).
String telefonoNormalizarDigitos(String raw) {
  final String onlyDigits = raw.replaceAll(RegExp(r'\D+'), '');
  if (onlyDigits.isEmpty) return '';
  if (onlyDigits.startsWith('1')) return onlyDigits;
  if (onlyDigits.length == 10) return '1$onlyDigits';
  return onlyDigits;
}

/// Primer valor no vacío entre claves habituales en `usuarios` / viajes (evita botones inactivos si el campo no se llama `telefono`).
String telefonoCrudoDesdeMapa(Map<String, dynamic> m) {
  const List<String> keys = <String>[
    'telefonoTaxista',
    'telefono',
    'phone',
    'phoneNumber',
    'celular',
    'movil',
    'telefonoMovil',
    'whatsapp',
    'whatsappNumber',
    'numeroTelefono',
    'telefonoContacto',
    'mobile',
  ];
  for (final String k in keys) {
    final Object? v = m[k];
    if (v == null) continue;
    final String s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// Misma forma en toda la app: `tel:+<digitos>`.
Uri telefonoUriLlamada(String digitosNormalizados) =>
    Uri.parse('tel:+$digitosNormalizados');

Uri telefonoUriWhatsAppApp(String digitosNormalizados, String mensajePlano) {
  final String q = Uri.encodeComponent(mensajePlano);
  return Uri.parse('whatsapp://send?phone=%2B$digitosNormalizados&text=$q');
}

Uri telefonoUriWhatsAppWeb(String digitosNormalizados, String mensajePlano) {
  final String q = Uri.encodeComponent(mensajePlano);
  return Uri.parse('https://wa.me/$digitosNormalizados?text=$q');
}

/// Lanzamiento robusto (app externa → predeterminada → http).
Future<bool> telefonoLaunchUri(Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      return true;
    }
    if (uri.scheme.startsWith('http')) {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}
