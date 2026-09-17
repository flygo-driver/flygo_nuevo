import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/recargo_condiciones_cotizacion.dart';
import 'package:flygo_nuevo/servicios/recargo_condiciones_service.dart';

void main() {
  test('hora pico manana 8:30', () {
    final t = DateTime(2026, 3, 9, 8, 30);
    expect(RecargoCondicionesService.esHoraPico(t), isTrue);
  });

  test('hora pico tarde 18:00', () {
    final t = DateTime(2026, 3, 9, 18, 0);
    expect(RecargoCondicionesService.esHoraPico(t), isTrue);
  });

  test('antes de hora pico manana 7:15 no es pico', () {
    final t = DateTime(2026, 3, 9, 7, 15);
    expect(RecargoCondicionesService.esHoraPico(t), isFalse);
  });

  test('despues de hora pico manana 9:10 no es pico', () {
    final t = DateTime(2026, 3, 9, 9, 10);
    expect(RecargoCondicionesService.esHoraPico(t), isFalse);
  });

  test('tarde antes de pico 16:00 no es pico', () {
    final t = DateTime(2026, 3, 9, 16, 0);
    expect(RecargoCondicionesService.esHoraPico(t), isFalse);
  });

  test('tarde despues de pico 19:45 no es pico', () {
    final t = DateTime(2026, 3, 9, 19, 45);
    expect(RecargoCondicionesService.esHoraPico(t), isFalse);
  });

  test('fuera de hora pico mediodia', () {
    final t = DateTime(2026, 3, 9, 12, 0);
    expect(RecargoCondicionesService.esHoraPico(t), isFalse);
  });

  test('tapón cuando tráfico supera 18%', () {
    expect(
      RecargoCondicionesService.hayTapon(
        durationSeconds: 600,
        durationInTrafficSeconds: 750,
      ),
      isTrue,
    );
    expect(
      RecargoCondicionesService.hayTapon(
        durationSeconds: 600,
        durationInTrafficSeconds: 650,
      ),
      isFalse,
    );
  });

  test('tapón progresivo según ratio Google', () {
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.05), 0);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.15), 10);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.30), 16);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.50), 22);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.65), 28);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.90), 34);
  });

  test('aplica recargo aditivo acumulado con tope 50%', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: true,
      lluvia: true,
      tapon: true,
      pctHoraPico: 12,
      pctLluvia: 15,
      pctTapon: 28,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
    );
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 380);
    expect(aplicado.pctTotal, 50);
    expect(aplicado.precioDespuesRecargoRd, 570);
  });

  test('urbano por tiempo: recargo multiplicativo lluvia', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: false,
      lluvia: true,
      tapon: false,
      pctHoraPico: 0,
      pctLluvia: 0,
      pctTapon: 0,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
      modoRecargo: 'multiplicativo',
    );
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 358);
    expect(aplicado.precioDespuesRecargoRd, greaterThan(358));
    expect(aplicado.tieneRecargo, isTrue);
  });

  test('sin condiciones no cambia precio', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: false,
      lluvia: false,
      tapon: false,
      pctHoraPico: 0,
      pctLluvia: 0,
      pctTapon: 0,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
    );
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 200);
    expect(aplicado.precioDespuesRecargoRd, 200);
    expect(aplicado.tieneRecargo, isFalse);
  });
}
