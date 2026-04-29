// lib/pantallas/cliente/guardar_viaje_helper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/viaje_data.dart';
import '../../servicios/distancia_service.dart';
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

  // Distancia y precio (SIN ida y vuelta porque no se soporta)
  final km = DistanciaService.calcularDistancia(
    latCliente,
    lonCliente,
    latDestino,
    lonDestino,
  );
  final precio = DistanciaService.calcularPrecio(km); // ← SIN idaYVuelta

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
