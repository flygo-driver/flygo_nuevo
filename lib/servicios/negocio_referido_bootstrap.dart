import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

import 'package:flygo_nuevo/servicios/negocio_referido_deep_link.dart';
import 'package:flygo_nuevo/servicios/negocio_referido_install_referrer_stub.dart'
    if (dart.library.io) 'package:flygo_nuevo/servicios/negocio_referido_install_referrer_android.dart';
import 'package:flygo_nuevo/servicios/negocio_referido_service.dart';

/// Arranque: deep link QR + Install Referrer (Play) antes del registro.
abstract final class NegocioReferidoBootstrap {
  NegocioReferidoBootstrap._();

  static bool _instalado = false;

  static Future<void> install() async {
    if (_instalado) return;
    _instalado = true;

    if (kIsWeb) return;

    await NegocioReferidoDeepLink.install();

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final String? codigo = await leerCodigoNegocioInstallReferrer();
        if (codigo != null && codigo.trim().isNotEmpty) {
          await NegocioReferidoService.guardarPendiente(codigo);
        }
      } catch (e) {
        debugPrint('[NegocioReferidoBootstrap] installReferrer: $e');
      }
    }
  }
}
