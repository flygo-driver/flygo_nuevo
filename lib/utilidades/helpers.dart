// lib/utilidades/helpers.dart

import 'package:flutter/material.dart';

// Validar un correo electrónico
bool correoValido(String email) {
  final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  return regex.hasMatch(email.trim());
}

// Mostrar un mensaje tipo SnackBar
void mostrarMensaje(
  BuildContext context,
  String mensaje, {
  bool error = false,
}) {
  final snackBar = SnackBar(
    content: Text(mensaje),
    backgroundColor: error ? Colors.red : Colors.green,
  );
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

// Formatear fecha para mostrar
String formatearFecha(DateTime fecha) {
  return "${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}";
}
