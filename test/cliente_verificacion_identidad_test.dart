import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

void main() {
  const cliente = <String, dynamic>{'rol': 'cliente'};

  test('usuario legacy sin fecha de registro exige selfie', () {
    expect(
      ClienteVerificacionIdentidadService.debeVerificarAhora(cliente),
      true,
    );
  });

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
    expect(
      ClienteVerificacionIdentidadService.estadoDesde(data),
      ClienteVerificacionIdentidadEstado.vencida,
    );
  });

  test('selfie reciente sin revisar queda en la cola del ADM', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn': DateTime.now().subtract(const Duration(days: 2)),
    };
    expect(
      ClienteVerificacionIdentidadService.estadoDesde(data),
      ClienteVerificacionIdentidadEstado.porRevisar,
    );
    // Pendiente de revisar no frena al pasajero: si no, nadie viaja de madrugada.
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), false);
  });

  test('selfie aprobada por el ADM marca estado vigente', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn': DateTime.now().subtract(const Duration(days: 2)),
      'verificacionIdentidadRevision': 'aprobada',
    };
    expect(
      ClienteVerificacionIdentidadService.estadoDesde(data),
      ClienteVerificacionIdentidadEstado.vigente,
    );
    expect(
      ClienteVerificacionIdentidadService.etiquetaEstado(
        ClienteVerificacionIdentidadEstado.vigente,
      ),
      'Selfie al día',
    );
  });

  test('selfie rechazada obliga a repetirla aunque sea reciente', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn': DateTime.now().subtract(const Duration(days: 1)),
      'verificacionIdentidadRevision': 'rechazada',
      'verificacionIdentidadRechazoMotivo': 'No se ve el rostro',
    };
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), true);
    expect(
      ClienteVerificacionIdentidadService.estadoDesde(data),
      ClienteVerificacionIdentidadEstado.rechazada,
    );
    expect(
      ClienteVerificacionIdentidadService.motivoRechazoDesde(data),
      'No se ve el rostro',
    );
  });

  test('el motivo solo se muestra si sigue rechazada', () {
    final data = <String, dynamic>{
      ...cliente,
      'verificacionIdentidadEn': DateTime.now(),
      'verificacionIdentidadRevision': 'pendiente',
      'verificacionIdentidadRechazoMotivo': 'motivo viejo',
    };
    expect(ClienteVerificacionIdentidadService.motivoRechazoDesde(data), isNull);
    expect(ClienteVerificacionIdentidadService.debeVerificarAhora(data), false);
  });

  test('las reglas impiden que el cliente se apruebe la selfie', () {
    final rules = File('firestore.rules').readAsStringSync();
    final bloque = rules.substring(
      rules.indexOf('"verificacionIdentidadEn", "verificacionIdentidadUrl",'),
    );
    expect(
      bloque.contains(
        'request.resource.data.verificacionIdentidadRevision == "pendiente"',
      ),
      true,
      reason: 'el dueño solo puede dejar la selfie pendiente de revisión',
    );
  });
}
