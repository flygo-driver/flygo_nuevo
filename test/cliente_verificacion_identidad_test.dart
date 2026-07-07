import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

void main() {
  const cliente = <String, dynamic>{'rol': 'cliente'};

  test('usuario nuevo no pide selfie en cada viaje', () {
    final data = <String, dynamic>{
      ...cliente,
      'fechaRegistro': DateTime.now().subtract(const Duration(days: 2)),
    };
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), false);
  });

  test('pasado el plazo desde registro pide primera selfie', () {
    final data = <String, dynamic>{
      ...cliente,
      'fechaRegistro': DateTime.now().subtract(const Duration(days: 31)),
    };
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), true);
  });

  test('verificación reciente no pide selfie otra vez', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn': DateTime.now().subtract(const Duration(days: 2)),
    };
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), false);
  });

  test('verificación antigua pide selfie de nuevo', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn':
          DateTime.now().subtract(const Duration(days: 31)),
    };
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), true);
  });
}
