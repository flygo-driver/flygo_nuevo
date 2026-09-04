/// Condiciones detectadas al cotizar (hora pico, lluvia, tapón).
/// El precio con estos recargos queda fijado al confirmar el viaje.
class RecargoCondicionesCotizacion {
  const RecargoCondicionesCotizacion({
    required this.horaPico,
    required this.lluvia,
    required this.tapon,
    required this.pctHoraPico,
    required this.pctLluvia,
    required this.pctTapon,
    required this.pctTotal,
    required this.recargoRd,
    required this.precioAntesRecargoRd,
    required this.precioDespuesRecargoRd,
    this.ratioTrafico,
    this.precipitacionMm,
    this.cotizadoEn,
    this.minutosSinTrafico,
    this.minutosConTrafico,
  });

  final bool horaPico;
  final bool lluvia;
  final bool tapon;

  final double pctHoraPico;
  final double pctLluvia;
  final double pctTapon;
  final double pctTotal;

  final double recargoRd;
  final double precioAntesRecargoRd;
  final double precioDespuesRecargoRd;

  final double? ratioTrafico;
  final double? precipitacionMm;
  final DateTime? cotizadoEn;
  final int? minutosSinTrafico;
  final int? minutosConTrafico;

  bool get tieneRecargo => recargoRd > 0.009;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'precioBloqueado': true,
        'horaPico': horaPico,
        'lluvia': lluvia,
        'tapon': tapon,
        'pctHoraPico': pctHoraPico,
        'pctLluvia': pctLluvia,
        'pctTapon': pctTapon,
        'pctTotal': pctTotal,
        'recargoRd': double.parse(recargoRd.toStringAsFixed(2)),
        'precioAntesRecargoRd':
            double.parse(precioAntesRecargoRd.toStringAsFixed(2)),
        'precioDespuesRecargoRd':
            double.parse(precioDespuesRecargoRd.toStringAsFixed(2)),
        if (ratioTrafico != null)
          'ratioTrafico': double.parse(ratioTrafico!.toStringAsFixed(3)),
        if (minutosSinTrafico != null) 'minutosSinTrafico': minutosSinTrafico,
        if (minutosConTrafico != null) 'minutosConTrafico': minutosConTrafico,
        if (precipitacionMm != null)
          'precipitacionMm': double.parse(precipitacionMm!.toStringAsFixed(2)),
        if (cotizadoEn != null) 'cotizadoEn': cotizadoEn!.toIso8601String(),
      };

  List<String> get etiquetasActivas {
    final out = <String>[];
    if (horaPico) out.add('Hora pico');
    if (lluvia) out.add('Lluvia');
    if (tapon) out.add('Tráfico');
    return out;
  }
}
