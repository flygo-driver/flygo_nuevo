// lib/utils/open_map.dart
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre Google Maps de forma universal (app si está instalada, si no: web).
Future<void> openMap({
  double? lat,
  double? lon,
  String? label,
  String? query, // texto si no tienes coords
}) async {
  // Construimos la query
  String q;
  if (lat != null && lon != null) {
    final lbl = Uri.encodeComponent(label ?? 'Destino');
    q = '$lat,$lon($lbl)';
  } else {
    q = Uri.encodeComponent(query ?? 'Destino');
  }

  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');

  if (await canLaunchUrl(uri)) {
    // En web dejamos el modo por defecto; en móvil forzamos externa (app)
    await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }
}
