// lib/pantallas/cliente/guardar_viaje_helper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/viaje_data.dart';
import '../../servicios/analytics_rai.dart';
import '../../servicios/distancia_service.dart';
import '../../servicios/tarifa_service_unificado.dart';
import '../../utils/formatos_moneda.dart';

Future<void> guardarViajeCliente({
  required BuildContext context,
  required String origen,
  required String destino,
  required double latCliente,
  required double lonCliente,
  required double latDestino,
  required double lonDestino,
  required String metodoPago,
  DateTime? fechaHora, // (no lo usa ViajeData.crearViajeCliente)
  // bool idaYVuelta = false,  // ❌ ELIMINADO - No se usa en ViajeData.crearViajeCliente
}) async {
  // ⚠️ Captura referencias sincronas (no dependen de await)
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Inicia sesión para crear el viaje')),
    );
    return;
  }

  bool coordsOk(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      !(lat.abs() < 1e-6 && lon.abs() < 1e-6) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  if (!coordsOk(latCliente, lonCliente) || !coordsOk(latDestino, lonDestino)) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Ubicación de origen o destino inválida.')),
    );
    return;
  }

  // Distancia y precio (SIN ida y vuelta porque no se soporta)
  final km = DistanciaService.calcularDistancia(
    latCliente,
    lonCliente,
    latDestino,
    lonDestino,
  );
  final precio =
      await TarifaServiceUnificado.precioNormalCarroReferencia(km);

  try {
    final id = await ViajeData.crearViajeCliente(
      origen: origen,
      destino: destino,
      latCliente: latCliente,
      lonCliente: lonCliente,
      latDestino: latDestino,
      lonDestino: lonDestino,
      precio: precio,
      metodoPago: metodoPago,
    );

    await AnalyticsRai.logTripRequested();

    // Si la vista fue desmontada mientras esperábamos, salimos
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '✅ Viaje creado ($id). Total: ${FormatosMoneda.rd(precio)} • Dist: ${FormatosMoneda.numero2(km)} km',
        ),
      ),
    );

    if (nav.canPop()) nav.pop();
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('❌ Error al crear viaje: $e')),
    );
  }
}
