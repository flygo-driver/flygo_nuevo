import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/widgets/viaje_overlay_error_shield.dart';

void main() {
  testWidgets(
    'ViajeOverlayErrorShield no reemplaza el ErrorWidget.builder global',
    (WidgetTester tester) async {
      final ErrorWidgetBuilder anterior = ErrorWidget.builder;

      await tester.pumpWidget(
        const MaterialApp(
          home: ViajeOverlayErrorShield(
            child: SizedBox(key: Key('contenido-viaje')),
          ),
        ),
      );

      expect(ErrorWidget.builder, same(anterior));
      expect(find.byKey(const Key('contenido-viaje')), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      expect(ErrorWidget.builder, same(anterior));
    },
  );
}
