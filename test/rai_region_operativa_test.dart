import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';

void main() {
  group('RaiRegionOperativa — cobertura nacional', () {
    test('ciudades principales resuelven región esperada', () {
      expect(
        RaiRegionOperativa.resolver(18.4861, -69.9312),
        RaiRegionOperativa.metro,
      );
      expect(
        RaiRegionOperativa.resolver(19.4517, -70.6970),
        RaiRegionOperativa.santiago,
      );
      expect(
        RaiRegionOperativa.resolver(18.5601, -68.3725),
        RaiRegionOperativa.este,
      );
      expect(
        RaiRegionOperativa.resolver(19.7934, -70.6884),
        RaiRegionOperativa.norte,
      );
      expect(
        RaiRegionOperativa.resolver(18.2085, -71.1008),
        RaiRegionOperativa.sur,
      );
      expect(
        RaiRegionOperativa.resolver(19.2220, -70.5296),
        RaiRegionOperativa.cibao,
      );
      expect(
        RaiRegionOperativa.resolver(19.2058, -69.3366),
        RaiRegionOperativa.samana,
      );
      expect(
        RaiRegionOperativa.resolver(18.4539, -69.2975),
        RaiRegionOperativa.sanPedro,
      );
      expect(
        RaiRegionOperativa.resolver(19.8470, -71.6500),
        RaiRegionOperativa.noroeste,
      );
      expect(
        RaiRegionOperativa.resolver(18.3000, -70.4000),
        RaiRegionOperativa.valdesia,
      );
    });

    test('territorio RD incluye islas y fronteras', () {
      expect(RaiRegionOperativa.enTerritorioRd(18.4861, -69.9312), isTrue);
      expect(RaiRegionOperativa.enTerritorioRd(19.85, -71.65), isTrue);
      expect(RaiRegionOperativa.enTerritorioRd(18.04, -71.75), isTrue);
      expect(RaiRegionOperativa.enTerritorioRd(25.0, -80.0), isFalse);
    });

    test('regionEfectiva usa coordenadas si falta campo region', () {
      final String r = RaiRegionOperativa.regionEfectiva(<String, dynamic>{
        'location': GeoPoint(19.4517, -70.6970),
      });
      expect(r, RaiRegionOperativa.santiago);
    });
  });
}
