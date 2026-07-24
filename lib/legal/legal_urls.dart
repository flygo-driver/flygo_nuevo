import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre una URL legal pública (Firebase Hosting / Play Console).
Future<void> abrirUrlLegal(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo abrir: $url')),
    );
  }
}

/// Enlace web a la política publicada (misma URL que Google Play).
Future<void> abrirPoliticaPrivacidadWeb(BuildContext context) =>
    abrirUrlLegal(context, kPrivacyPolicyPublicUrl);

Future<void> abrirTerminosWeb(BuildContext context) =>
    abrirUrlLegal(context, kTermsPublicUrl);

Future<void> abrirEliminarCuentaWeb(BuildContext context) =>
    abrirUrlLegal(context, kAccountDeletionPublicUrl);

Future<void> abrirContratoCorporativoWeb(BuildContext context) =>
    abrirUrlLegal(context, kCorporativoContractPublicUrl);
