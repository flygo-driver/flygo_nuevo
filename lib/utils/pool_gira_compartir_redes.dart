import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'package:flygo_nuevo/servicios/pool_share_link.dart';

/// Compartir gira en WhatsApp, Facebook, Instagram, X y cualquier red.
abstract final class PoolGiraCompartirRedes {
  PoolGiraCompartirRedes._();

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.flygo.rd2';

  /// Mensaje con el enlace primero (vista previa en WhatsApp, Facebook, etc.).
  static String mensaje({
    required String textoPromo,
    required String poolId,
  }) {
    return PoolShareLink.mensajeRedesSociales(
      textoPromo: textoPromo,
      poolId: poolId,
    );
  }

  static String enlace(String poolId) => PoolShareLink.httpsOpenUrl(poolId);

  static String? primerBannerUrl(Map<String, dynamic> poolData) {
    final urls = poolData['bannerUrls'];
    if (urls is List && urls.isNotEmpty) {
      final u = urls.first.toString().trim();
      if (u.isNotEmpty) return u;
    }
    final single = (poolData['bannerUrl'] ?? '').toString().trim();
    return single.isEmpty ? null : single;
  }

  /// Menú del sistema: elegí WhatsApp Estados, Facebook, Instagram, etc.
  static Future<bool> compartir({
    required BuildContext context,
    required String textoPromo,
    required String poolId,
    String? bannerUrl,
  }) async {
    final texto = mensaje(textoPromo: textoPromo, poolId: poolId);
    final banner = bannerUrl?.trim();

    if (banner != null && banner.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(banner))
            .timeout(const Duration(seconds: 18));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final file = File(
            '${Directory.systemTemp.path}/rai_gira_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await file.writeAsBytes(resp.bodyBytes);
          final result = await Share.shareXFiles(
            <XFile>[XFile(file.path, mimeType: 'image/jpeg')],
            text: texto,
            subject: 'Gira RAI — reservá cupos',
          );
          if (context.mounted) {
            _ayudaTrasCompartir(context);
          }
          return result.status != ShareResultStatus.dismissed;
        }
      } catch (_) {
        // Solo texto + enlace.
      }
    }

    final result = await Share.share(
      texto,
      subject: 'Gira RAI — reservá cupos',
    );
    if (context.mounted) {
      _ayudaTrasCompartir(context);
    }
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<void> copiarEnlace(BuildContext context, String poolId) async {
    final link = enlace(poolId);
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Enlace copiado. Pegalo en tu estado de WhatsApp, Facebook o Instagram.',
        ),
      ),
    );
  }

  static void _ayudaTrasCompartir(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Quien toque el enlace abre la gira en RAI o va a descargar la app.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  static Future<void> mostrarAyuda(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.share_rounded, color: Color(0xFF0D9488)),
        title: const Text('Compartir en redes'),
        content: const Text(
          '1. Tocá «Compartir en redes» en tu gira.\n'
          '2. Elegí WhatsApp (Estados), Facebook, Instagram, etc.\n'
          '3. El enlace es clicable: abre RAI Pasajero en esa gira.\n'
          '4. Si no tienen la app, van a Google Play para descargarla.\n\n'
          'Funciona en WhatsApp, Facebook, Instagram, X y más.',
          style: TextStyle(height: 1.45),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
