import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/feriados_republica_dominicana.dart';

void main() {
  test('RD 2026 incluye Independencia y Navidad', () {
    final map = {
      for (final h in FeriadosRepublicaDominicana.oficialesDelAno(2026))
        FeriadosRepublicaDominicana.clave(h.fecha): h.nombre,
    };
    expect(map['2026-02-27'], 'Independencia Nacional');
    expect(map['2026-12-25'], 'Navidad');
    expect(map.containsKey('2026-01-01'), isTrue);
  });

  test('mapa cubre año anterior, actual y siguiente', () {
    final m = FeriadosRepublicaDominicana.mapaClavesConNombre(
      alrededorDe: DateTime(2026, 6, 1),
    );
    expect(m.keys.any((k) => k.startsWith('2025-')), isTrue);
    expect(m.keys.any((k) => k.startsWith('2026-')), isTrue);
    expect(m.keys.any((k) => k.startsWith('2027-')), isTrue);
  });
}
