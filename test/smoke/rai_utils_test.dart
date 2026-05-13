import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/ux_log.dart';

void main() {
  test('firebaseFunctionsCodeIsTransient reconoce códigos reintentables', () {
    expect(firebaseFunctionsCodeIsTransient('unavailable'), isTrue);
    expect(firebaseFunctionsCodeIsTransient('deadline-exceeded'), isTrue);
    expect(firebaseFunctionsCodeIsTransient('permission-denied'), isFalse);
    expect(firebaseFunctionsCodeIsTransient('failed-precondition'), isFalse);
  });
}
