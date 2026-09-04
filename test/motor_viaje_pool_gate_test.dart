import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/operaciones_mensajes_adm_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

void main() {
  group('Motor — pool y vinculo cliente', () {
    Map<String, dynamic> viajeMotorAhora({
      String uidCliente = 'cliente-1',
    }) {
      final now = DateTime.utc(2026, 8, 12, 21, 0);
      return <String, dynamic>{
        'uidCliente': uidCliente,
        'clienteId': uidCliente,
        'uidTaxista': '',
        'taxistaId': '',
        'tipoServicio': 'motor',
        'canalAsignacion': 'pool',
        'estado': EstadosViaje.pendiente,
        'esAhora': true,
        'programado': false,
        'activo': true,
        'fechaHora': Timestamp.fromDate(now),
        'publishAt': Timestamp.fromDate(now),
        'acceptAfter': Timestamp.fromDate(now),
      };
    }

    test('viaje motor entra al pool de motoristas', () {
      final data = viajeMotorAhora();
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(
          data,
          'taxista-motor',
          poolModoConductor: TaxistaPoolModoConductor.motor,
        ),
        isTrue,
      );
    });

    test('viaje motor NO entra al pool de vehículos', () {
      final data = viajeMotorAhora();
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(
          data,
          'taxista-carro',
          poolModoConductor: TaxistaPoolModoConductor.vehiculo,
        ),
        isFalse,
      );
    });

    test('viaje normal NO entra al pool de motoristas', () {
      final data = viajeMotorAhora()..['tipoServicio'] = 'normal';
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(
          data,
          'taxista-motor',
          poolModoConductor: TaxistaPoolModoConductor.motor,
        ),
        isFalse,
      );
    });

    test('cliente motor ahora debe ver overlay en curso (no confirmación programada)', () {
      final data = viajeMotorAhora(uidCliente: 'u1');
      expect(
        ViajePoolTaxistaGate.clienteDebeVerConfirmacionProgramado(data),
        isFalse,
      );
      expect(
        ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(data, 'u1'),
        isTrue,
      );
    });

    test('crear motor ahora vincula viajeActivoId al nuevo viaje', () {
      final patch = ViajePoolTaxistaGate.patchUsuarioTrasCrearViajeCliente(
        uidCliente: 'u1',
        nuevoViajeId: 'motor-nuevo',
        nuevoEsAhora: true,
        userData: const <String, dynamic>{},
        viajeActivoDoc: null,
      );
      expect(patch['viajeActivoId'], 'motor-nuevo');
    });

    test('ADM mensajes usa motor aunque falte tipoServicio explícito', () {
      expect(
        OperacionesMensajesAdmRepo.tipoServicioParaAdm(<String, dynamic>{
          'tipoVehiculo': '🛵 MOTOR 🛵',
        }),
        'motor',
      );
      expect(
        OperacionesMensajesAdmRepo.tipoServicioParaAdm(<String, dynamic>{
          'tipoServicio': 'motor',
        }),
        'motor',
      );
    });
  });
}
