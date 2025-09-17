import 'package:intl/intl.dart';

class FormatosFecha {
  // Retorna una fecha legible: "Martes 6 de Agosto de 2025, 3:30 PM"
  static String formatoCompleto(DateTime fecha) {
    final DateFormat formato = DateFormat(
      'EEEE d \'de\' MMMM \'de\' y, h:mm a',
      'es_ES',
    );
    return formato.format(fecha);
  }

  // Retorna solo fecha: "06/08/2025"
  static String formatoCorto(DateTime fecha) {
    final DateFormat formato = DateFormat('dd/MM/yyyy');
    return formato.format(fecha);
  }

  // Retorna hora: "3:30 PM"
  static String soloHora(DateTime fecha) {
    final DateFormat formato = DateFormat('h:mm a');
    return formato.format(fecha);
  }

  // Para backend o Firestore: "2025-08-06 15:30:00"
  static String paraBaseDeDatos(DateTime fecha) {
    final DateFormat formato = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formato.format(fecha);
  }
}
