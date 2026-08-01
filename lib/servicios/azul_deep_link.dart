import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_cliente_nav.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_taxista_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pagos/azul_payment_service.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Retorno AZUL → app (`raidriver://` o `https://flygo-rd.web.app/azul/resultado`).
class AzulDeepLink {
  AzulDeepLink._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static Timer? _pendingTimer;
  static _AzulReturnTarget? _pending;
  static _AzulAppLifecycleObserver? _lifecycleObserver;

  static Future<void> install() async {
    await dispose();
    if (kIsWeb) return;

    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _enqueue(initial);
      }
      _sub = _appLinks.uriLinkStream.listen(_enqueue);
    } catch (_) {}

    _lifecycleObserver ??= _AzulAppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pending = null;
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  static _AzulReturnTarget? parse(Uri uri) {
    final String host = uri.host.toLowerCase();
    final String path = uri.path.toLowerCase();

    final bool hosting =
        (host == 'flygo-rd.web.app' || host == 'flygo-rd.firebaseapp.com') &&
            path.startsWith('/azul/resultado');
    final bool custom =
        uri.scheme == 'raidriver' && host == 'azul' && path.startsWith('/resultado');

    if (!hosting && !custom) return null;

    final String viajeId = (uri.queryParameters['viajeId'] ?? '').trim();
    final String recargaId = (uri.queryParameters['recargaId'] ?? '').trim();
    final String rol = (uri.queryParameters['rol'] ?? '').trim().toLowerCase();
    final String estado =
        (uri.queryParameters['estado'] ?? '').trim().toLowerCase();

    final bool esRecargaTaxista =
        recargaId.isNotEmpty || (rol == 'taxista' && viajeId.isEmpty);
    if (esRecargaTaxista) {
      final String id = recargaId.isNotEmpty ? recargaId : viajeId;
      if (id.isEmpty) return null;
      return _AzulReturnTarget.recarga(recargaId: id, estado: estado);
    }

    if (viajeId.isEmpty) return null;
    return _AzulReturnTarget.viaje(viajeId: viajeId, estado: estado);
  }

  static void _enqueue(Uri uri) {
    final target = parse(uri);
    if (target == null) return;
    _pending = target;
    if (target.esRecarga) {
      AzulPaymentService.registrarRecargaPagoEnCurso(target.recargaId!);
    } else {
      AzulPaymentService.registrarViajePagoEnCurso(target.viajeId!);
    }
    unawaited(_handlePending());
    _pendingTimer?.cancel();
    _pendingTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_pending == null) {
        _pendingTimer?.cancel();
        _pendingTimer = null;
        return;
      }
      unawaited(_handlePending());
    });
  }

  /// Al volver del navegador AZUL sin tocar el enlace (icono de la app).
  static Future<void> reconciliarAlReanudarApp() async {
    final String? recargaId = AzulPaymentService.recargaPagoEnCursoId;
    if (recargaId != null && recargaId.isNotEmpty) {
      await _reconciliarRecargaAlReanudar(recargaId);
      return;
    }

    final String? viajeId = AzulPaymentService.viajePagoEnCursoId;
    if (viajeId == null || viajeId.isEmpty) return;

    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;

    try {
      await AzulPaymentService.verifyPayment(viajeId: viajeId);
    } catch (_) {}

    final Map<String, dynamic>? data = await _leerViajeConReintentos(viajeId);
    if (data == null) return;

    if (data['completado'] == true) {
      AzulPaymentService.limpiarViajePagoEnCurso(viajeId);
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    final String uidCliente =
        (data['uidCliente'] ?? data['clienteId'] ?? '').toString().trim();
    if (!isConductorFlavor && uid != null && uid == uidCliente) {
      final bool yaEnViajeEnCurso =
          !ActiveTripService.debeForzarInicioClienteShell &&
              ActiveTripService.debeMantenerOverlayViajeEnShell;
      if (!yaEnViajeEnCurso) {
        await NavigationService.retomarViajeClienteTrasPagoAzul(viajeId: viajeId);
      }
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data) && nav.mounted) {
        ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Pago con tarjeta confirmado. Seguí tu viaje en curso.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) {
        AzulPaymentService.limpiarViajePagoEnCurso(viajeId);
      }
    }
  }

  static Future<void> _reconciliarRecargaAlReanudar(String recargaId) async {
    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    if (isClienteFlavor) return;

    try {
      final res = await AzulPaymentService.verifyRecargaTaxista(
        recargaId: recargaId,
      );
      final ok = res['captured'] == true ||
          res['estado']?.toString().toLowerCase() == 'pagado';
      await NavigationService.retomarTaxistaTrasRecargaAzul(
        recargaId: ok ? recargaId : null,
      );
      if (ok) {
        AzulPaymentService.limpiarRecargaPagoEnCurso(recargaId);
      }
    } catch (_) {
      await NavigationService.retomarTaxistaTrasRecargaAzul();
    }
  }

  static Future<void> _handlePending() async {
    final target = _pending;
    if (target == null) return;

    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;

    _pending = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;

    if (target.esRecarga) {
      await _handleRecargaPending(target, nav);
      return;
    }

    await _handleViajePending(target, nav);
  }

  static Future<void> _handleRecargaPending(
    _AzulReturnTarget target,
    NavigatorState nav,
  ) async {
    final String recargaId = target.recargaId ?? '';
    if (recargaId.isEmpty) return;
    if (isClienteFlavor) {
      // APK solo pasajero no opera recargas taxista.
      return;
    }

    bool ok = false;
    try {
      final res = await AzulPaymentService.verifyRecargaTaxista(
        recargaId: recargaId,
      );
      ok = res['captured'] == true ||
          res['estado']?.toString().toLowerCase() == 'pagado';
    } catch (_) {}

    await NavigationService.retomarTaxistaTrasRecargaAzul(
      recargaId: ok ? recargaId : null,
    );

    final messenger = ScaffoldMessenger.maybeOf(nav.context);
    if (ok) {
      AzulPaymentService.limpiarRecargaPagoEnCurso(recargaId);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Recarga con tarjeta confirmada. Seguís en el modo taxista.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } else if (target.estado == 'aprobado') {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'AZUL está confirmando la recarga. En segundos verás el saldo en Mis pagos.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    } else if (target.estado == 'declinado' || target.estado == 'cancelado') {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            target.estado == 'cancelado'
                ? 'Recarga cancelada. Podés intentar de nuevo en Mis pagos.'
                : 'Recarga declinada. Intentá otra tarjeta en Mis pagos.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      AzulPaymentService.limpiarRecargaPagoEnCurso(recargaId);
    }
  }

  static Future<void> _handleViajePending(
    _AzulReturnTarget target,
    NavigatorState nav,
  ) async {
    final String viajeId = target.viajeId ?? '';
    if (viajeId.isEmpty) return;

    try {
      await AzulPaymentService.verifyPayment(viajeId: viajeId);
    } catch (_) {}

    Map<String, dynamic>? data = await _leerViajeConReintentos(viajeId);
    if (data == null) return;

    final bool pagadoAzul = MetodoPagoViaje.tarjetaPagadoVerificado(data);

    if (data['completado'] != true) {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      final String uidCliente =
          (data['uidCliente'] ?? data['clienteId'] ?? '').toString().trim();
      final String uidTaxista =
          (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();

      if (!isConductorFlavor && uid != null && uid == uidCliente) {
        await NavigationService.retomarViajeClienteTrasPagoAzul(
          viajeId: viajeId,
        );
      }

      final messenger = ScaffoldMessenger.maybeOf(nav.context);
      if (pagadoAzul) {
        AzulPaymentService.limpiarViajePagoEnCurso(viajeId);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Pago con tarjeta confirmado. Tu viaje sigue activo.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } else if (target.estado == 'aprobado') {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'AZUL está confirmando el pago. En unos segundos verás «Tarjeta pagada» en tu viaje.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      } else if (!isConductorFlavor && uid == uidCliente) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Volviste a tu viaje en curso. Revisá el estado del pago en el panel de tarjeta.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      } else if (!isConductorFlavor && uid == uidTaxista) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Volvé al viaje para revisar el estado del pago.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    AzulPaymentService.limpiarViajePagoEnCurso(viajeId);

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final String uidCliente =
        (data['uidCliente'] ?? data['clienteId'] ?? '').toString().trim();
    final String uidTaxista =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();

    if (!isClienteFlavor && uid == uidTaxista) {
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        context: nav.context,
        viajeId: viajeId,
        uidTaxista: uid,
        viajeDataSemilla: data,
      );
      if (!pagadoAzul && nav.mounted) {
        ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Factura abierta. El sello «Tarjeta pagada» aparece solo cuando AZUL confirma el cobro.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (!isConductorFlavor && uid == uidCliente) {
      await PostViajeClienteNav.abrirFacturaYFlujo(
        context: nav.context,
        viajeId: viajeId,
        viajeDataSemilla: data,
      );
      if (!pagadoAzul && nav.mounted) {
        ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Factura abierta. «Tarjeta pagada» solo si AZUL ya confirmó el pago en servidor.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// AZUL puede tardar 1–3 s en escribir `estadoPago: verificado` tras el redirect.
  static Future<Map<String, dynamic>?> _leerViajeConReintentos(String viajeId) async {
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 800),
      Duration(milliseconds: 1600),
      Duration(milliseconds: 2800),
    ];
    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      final data = snap.data();
      if (data != null) return data;
    }
    return null;
  }
}

class _AzulAppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AzulDeepLink.reconciliarAlReanudarApp());
    }
  }
}

class _AzulReturnTarget {
  const _AzulReturnTarget._({
    this.viajeId,
    this.recargaId,
    required this.estado,
    required this.esRecarga,
  });

  factory _AzulReturnTarget.viaje({
    required String viajeId,
    required String estado,
  }) =>
      _AzulReturnTarget._(
        viajeId: viajeId,
        estado: estado,
        esRecarga: false,
      );

  factory _AzulReturnTarget.recarga({
    required String recargaId,
    required String estado,
  }) =>
      _AzulReturnTarget._(
        recargaId: recargaId,
        estado: estado,
        esRecarga: true,
      );

  final String? viajeId;
  final String? recargaId;
  final String estado;
  final bool esRecarga;
}
