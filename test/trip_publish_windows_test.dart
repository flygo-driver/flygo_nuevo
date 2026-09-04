import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

void main() {
  group('TripPublishWindows', () {
    test('poolOpensAtForScheduledPickup — mañana abre T-45 min, no ahora', () {
      final DateTime now = DateTime(2026, 8, 12, 10, 0);
      final DateTime pickup = DateTime(2026, 8, 13, 10, 0);
      final DateTime opens = TripPublishWindows.poolOpensAtForScheduledPickup(
        pickup,
        now,
      );
      expect(opens, DateTime(2026, 8, 13, 9, 15));
      expect(opens.isAfter(now), isTrue);
    });

    test('poolOpensAtForScheduledPickup — pickup ya pasó abre ahora', () {
      final DateTime now = DateTime(2026, 8, 13, 10, 0);
      final DateTime pickup = DateTime(2026, 8, 13, 9, 0);
      final DateTime opens = TripPublishWindows.poolOpensAtForScheduledPickup(
        pickup,
        now,
      );
      expect(opens, now);
    });

    test('esProgramadoRecogidaCasiInmediata — dentro de 45 min es inmediato', () {
      final DateTime now = DateTime(2026, 8, 12, 10, 0).toUtc();
      final DateTime pickup30 = now.add(const Duration(minutes: 30));
      expect(
        TripPublishWindows.esProgramadoRecogidaCasiInmediata(pickup30, now),
        isTrue,
      );
    });

    test('esProgramadoRecogidaCasiInmediata — mañana no es inmediato', () {
      final DateTime now = DateTime(2026, 8, 12, 10, 0).toUtc();
      final DateTime pickupManana = now.add(const Duration(hours: 20));
      expect(
        TripPublishWindows.esProgramadoRecogidaCasiInmediata(pickupManana, now),
        isFalse,
      );
    });

    test('acceptAfter y startWindow alineados con pool lead 45 min', () {
      final DateTime now = DateTime(2026, 8, 12, 10, 0);
      final DateTime pickup = DateTime(2026, 8, 14, 8, 30);
      expect(
        TripPublishWindows.acceptAfterForScheduledPickup(pickup, now),
        DateTime(2026, 8, 14, 7, 45),
      );
      expect(
        TripPublishWindows.startWindowAtForScheduledPickup(pickup, now),
        DateTime(2026, 8, 14, 7, 45),
      );
    });
  });

  group('ViajePoolTaxistaGate — reserva programada lejana', () {
    Map<String, dynamic> docProgramado({
      required DateTime pickup,
      required DateTime publishAt,
    }) {
      return <String, dynamic>{
        'programado': true,
        'esAhora': false,
        'activo': false,
        'estado': 'pendiente',
        'fechaHora': Timestamp.fromDate(pickup),
        'publishAt': Timestamp.fromDate(publishAt),
        'acceptAfter': Timestamp.fromDate(publishAt),
      };
    }

    test('esReservaProgramadaLejana — mañana no entra al pool', () {
      final DateTime now = DateTime.now();
      final DateTime pickup = now.add(const Duration(days: 1));
      final DateTime publishAt =
          TripPublishWindows.poolOpensAtForScheduledPickup(pickup, now);
      final Map<String, dynamic> doc = docProgramado(
        pickup: pickup,
        publishAt: publishAt,
      );

      expect(publishAt.isAfter(now), isTrue);
      expect(ViajePoolTaxistaGate.esReservaProgramadaLejana(doc), isTrue);
      expect(ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(doc), isFalse);
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(doc, 'taxista_uid'),
        isFalse,
      );
    });

    test('ventana abierta — recogida pronto entra al pool', () {
      final DateTime now = DateTime.now();
      final DateTime pickup = now.add(const Duration(minutes: 30));
      final DateTime publishAt =
          TripPublishWindows.poolOpensAtForScheduledPickup(pickup, now);
      final Map<String, dynamic> doc = docProgramado(
        pickup: pickup,
        publishAt: publishAt,
      );

      expect(publishAt.isBefore(now.add(const Duration(seconds: 2))), isTrue);
      expect(ViajePoolTaxistaGate.esReservaProgramadaLejana(doc), isFalse);
      expect(ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(doc), isTrue);
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(doc, 'taxista_uid'),
        isTrue,
      );
    });

    test('programado sin publishAt — bloqueado (datos incompletos)', () {
      final DateTime now = DateTime(2026, 8, 12, 11, 0);
      final Map<String, dynamic> doc = <String, dynamic>{
        'programado': true,
        'esAhora': false,
        'activo': false,
        'estado': 'pendiente',
        'fechaHora': Timestamp.fromDate(now.add(const Duration(days: 1))),
        'acceptAfter': Timestamp.fromDate(now.add(const Duration(days: 1))),
      };
      expect(ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(doc), isFalse);
      expect(
        ViajePoolTaxistaGate.viajeTomableEnPool(doc, 'taxista_uid'),
        isFalse,
      );
    });
  });
}
