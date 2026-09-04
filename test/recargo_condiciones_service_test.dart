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
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.15), 8);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.30), 14);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.50), 20);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.65), 26);
    expect(RecargoCondicionesService.pctTaponDesdeRatio(1.90), 30);
  });

  test('aplica recargo acumulado con tope 35%', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: true,
      lluvia: true,
      tapon: true,
      pctHoraPico: 10,
      pctLluvia: 8,
      pctTapon: 26,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
    );
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 380);
    expect(aplicado.pctTotal, 35);
    expect(aplicado.precioDespuesRecargoRd, 513);
  });

  test('urbano por tiempo: hora pico informativa sin recargo extra', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: true,
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
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 358);
    expect(aplicado.precioDespuesRecargoRd, 358);
    expect(aplicado.tieneRecargo, isFalse);
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
