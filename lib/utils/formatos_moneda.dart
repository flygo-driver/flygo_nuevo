// lib/utils/formatos_moneda.dart
import 'package:intl/intl.dart';

class FormatosMoneda {
  static final NumberFormat _rd = NumberFormat.currency(
    locale: 'es_DO', // coma decimal, punto miles
    symbol: 'RD\$ ',
    decimalDigits: 2,
  );

  static final NumberFormat _num2 = NumberFormat.currency(
    locale: 'es_DO',
    symbol: '',
    decimalDigits: 2,
  );

  static final NumberFormat _num0 = NumberFormat.decimalPattern('es_DO');

  /// RD$ 1.234,56
  static String rd(num v) => _rd.format(v);

  /// 1.234,56 (2 decimales)
  static String numero2(num v) => _num2.format(v).trim();

  /// 1.234 (sin decimales)
  static String numero0(num v) => _num0.format(v);

  /// 12,34 km (usa formato local)
  static String km(num v) => '${_num2.format(v).trim()} km';

  /// Convierte texto con coma/punto a double (ej: "1.234,56" -> 1234.56)
  static double parseNumero(String s) {
    final t = s
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9\.-]'), '');
    return double.tryParse(t) ?? 0.0;
  }
}
