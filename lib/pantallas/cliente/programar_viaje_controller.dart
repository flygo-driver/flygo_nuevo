// lib/pantallas/cliente/programar_viaje_controller.dart
import 'package:flutter/material.dart';

/// Controlador de estado para Programar Viaje.
/// Mantiene los datos del formulario y el cálculo (distancia, precio, split 20/80).
class ProgramarViajeController with ChangeNotifier {
  // Porcentaje FlyGo (20%)
  static const double _pctFlygo = 0.20;

  String origenManual = '';
  String destino = '';
  DateTime fechaHora = DateTime.now();

  String tipoVehiculo = 'Carro';
  String metodoPago = 'Efectivo'; // 'Efectivo' | 'Tarjeta'
  bool idaYVuelta = false;
  bool usarOrigenManual = false;

  double? latCliente;
  double? lonCliente;
  double? latDestino;
  double? lonDestino;

  String origenTexto = '';
  String destinoTexto = '';
  double distanciaKm = 0.0;
  double precioCalculado = 0.0;

  // Split precalculado (20/80)
  double comisionCalculada = 0.0; // 20% FlyGo
  double gananciaTaxistaCalculada = 0.0; // 80% taxista

  bool ubicacionObtenida = false;
  bool cargando = false;

  // ---- setters de flags / selects
  void setUsarOrigenManual(bool v) {
    usarOrigenManual = v;
    notifyListeners();
  }

  void setIdaYVuelta(bool v) {
    idaYVuelta = v;
    notifyListeners();
  }

  void setTipoVehiculo(String v) {
    tipoVehiculo = v;
    notifyListeners();
  }

  void setMetodoPago(String v) {
    metodoPago = v;
    notifyListeners();
  }

  void setFechaHora(DateTime dt) {
    fechaHora = dt;
    notifyListeners();
  }

  // ---- inputs de texto (sin notify para evitar rebuild en cada tecla)
  void setDestino(String v) => destino = v;
  void setOrigenManual(String v) => origenManual = v;

  // ---- ubicaciones elegidas/calculadas
  void setUbicaciones({
    required double oLat,
    required double oLon,
    required double dLat,
    required double dLon,
    required String origenLegible,
    required String destinoLegible,
  }) {
    latCliente = oLat;
    lonCliente = oLon;
    latDestino = dLat;
    lonDestino = dLon;
    origenTexto = origenLegible;
    destinoTexto = destinoLegible;
    notifyListeners();
  }

  // ---- cálculo de distancia/precio + split 20/80
  void setCalculo({
    required double distanciaKmCalc,
    required double precioCalc,
  }) {
    distanciaKm = _round2(distanciaKmCalc);
    precioCalculado = _round2(precioCalc);

    final comision = _round2(precioCalculado * _pctFlygo);
    final ganancia = _round2(precioCalculado - comision);

    comisionCalculada = comision;
    gananciaTaxistaCalculada = ganancia;

    ubicacionObtenida = true;
    notifyListeners();
  }

  void setCargando(bool v) {
    cargando = v;
    notifyListeners();
  }

  void limpiarCalculo() {
    distanciaKm = 0.0;
    precioCalculado = 0.0;
    comisionCalculada = 0.0;
    gananciaTaxistaCalculada = 0.0;
    ubicacionObtenida = false;
    notifyListeners();
  }

  void resetFormulario() {
    origenManual = '';
    destino = '';
    fechaHora = DateTime.now();
    tipoVehiculo = 'Carro';
    metodoPago = 'Efectivo';
    idaYVuelta = false;
    usarOrigenManual = false;

    latCliente = null;
    lonCliente = null;
    latDestino = null;
    lonDestino = null;
    origenTexto = '';
    destinoTexto = '';
    distanciaKm = 0.0;
    precioCalculado = 0.0;

    comisionCalculada = 0.0;
    gananciaTaxistaCalculada = 0.0;

    ubicacionObtenida = false;
    cargando = false;
    notifyListeners();
  }

  String? validarDestino() =>
      destino.trim().isEmpty ? 'Destino obligatorio' : null;

  String? validarOrigenManualSiAplica() =>
      (usarOrigenManual && origenManual.trim().isEmpty)
          ? 'Origen obligatorio'
          : null;

  bool get listoParaGuardar =>
      ubicacionObtenida &&
      latCliente != null &&
      lonCliente != null &&
      latDestino != null &&
      lonDestino != null &&
      precioCalculado > 0;

  // helper de redondeo
  double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
