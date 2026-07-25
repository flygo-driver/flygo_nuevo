// lib/utils/telefono_viaje.dart
// Normalización y URIs compartidos: DetalleViaje + viaje en curso (cliente/taxista).
import 'package:url_launcher/url_launcher.dart';

/// Dígitos para E.164 RD típico (prefijo 1 si faltaba en número de 10 cifras).
String telefonoNormalizarDigitos(String raw) {
  final String onlyDigits = raw.replaceAll(RegExp(r'\D+'), '');
  if (onlyDigits.isEmpty) return '';
  if (onlyDigits.startsWith('1') && onlyDigits.length == 11) return onlyDigits;
  if (onlyDigits.length == 10) return '1$onlyDigits';
  if (onlyDigits.startsWith('1') && onlyDigits.length > 11) {
    return onlyDigits.substring(0, 11);
  }
  return onlyDigits;
}

/// Número RD listo para wa.me / tel: (11 dígitos con prefijo país 1).
bool telefonoContactoValidoRd(String raw) {
  final d = telefonoNormalizarDigitos(raw);
  return d.length == 11 && d.startsWith('1');
}

/// WhatsApp publicado en giras: prioriza campo WhatsApp, si no el teléfono.
String telefonoChoferGiraWhatsApp(String telefono, String whatsapp) {
  final wa = whatsapp.trim();
  if (wa.isNotEmpty) return wa;
  return telefono.trim();
}

/// Llamada al chofer de gira: prioriza teléfono, si no WhatsApp.
String telefonoChoferGiraLlamada(String telefono, String whatsapp) {
  final tel = telefono.trim();
  if (tel.isNotEmpty) return tel;
  return whatsapp.trim();
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

Future<bool> telefonoAbrirLlamada(String raw) async {
  final d = telefonoNormalizarDigitos(raw);
  if (!telefonoContactoValidoRd(raw)) return false;
  return telefonoLaunchUri(telefonoUriLlamada(d));
}

Future<bool> telefonoAbrirWhatsApp(
  String raw, {
  String mensaje = '',
}) async {
  final d = telefonoNormalizarDigitos(raw);
  if (!telefonoContactoValidoRd(raw)) return false;
  if (await telefonoLaunchUri(telefonoUriWhatsAppApp(d, mensaje))) {
    return true;
  }
  return telefonoLaunchUri(telefonoUriWhatsAppWeb(d, mensaje));
}
