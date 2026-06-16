import 'package:cloud_firestore/cloud_firestore.dart';

/// Consultas escalables para Gestionar usuarios (ADM).
/// Evita escuchar toda la colección `usuarios` (costoso e inestable con miles de docs).
class AdminUsuariosListaService {
  AdminUsuariosListaService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int limiteInicial = 500;
  static const int pasoCargarMas = 500;
  static const int limiteMaximo = 3000;
  static const int limiteBloqueados = 500;

  static const List<String> camposOrdenFallback = [
    'updatedAt',
    'actualizadoEn',
    'creadoEn',
  ];

  static Query<Map<String, dynamic>> queryLista({
    required String modo,
    required String campoOrden,
    required int limite,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('usuarios');

    switch (modo) {
      case 'bloqueados':
        q = q.where('tienePagoPendiente', isEqualTo: true);
        break;
      case 'taxistas':
        q = q.where('rol', whereIn: const ['taxista', 'driver']);
        break;
      case 'clientes':
        q = q.where('rol', whereIn: const ['cliente', 'user']);
        break;
      default:
        break;
    }

    return q.orderBy(campoOrden, descending: true).limit(limite);
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamLista({
    required String modo,
    required String campoOrden,
    required int limite,
  }) {
    return queryLista(modo: modo, campoOrden: campoOrden, limite: limite)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamPorUid(
      String uid) {
    return _db.collection('usuarios').doc(uid.trim()).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPorEmail(
      String email) {
    final normalizado = email.trim().toLowerCase();
    return _db
        .collection('usuarios')
        .where('email', isEqualTo: normalizado)
        .limit(20)
        .snapshots();
  }

  /// Teléfono: compara dígitos guardados tal cual (la app suele normalizar en perfil).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPorTelefono(
      String telefono) {
    final digits = telefono.replaceAll(RegExp(r'\D'), '');
    return _db
        .collection('usuarios')
        .where('telefono', isEqualTo: digits)
        .limit(20)
        .snapshots();
  }

  static String descripcionModo(String modo, int limiteVisible) {
    switch (modo) {
      case 'bloqueados':
        return 'Taxistas con tienePagoPendiente (prepago/comisión). '
            'Hasta $limiteBloqueados en vivo.';
      case 'taxistas':
        return 'Conductores (rol taxista/driver), los $limiteVisible más recientes. '
            'Usa «Cargar más» hasta $limiteMaximo.';
      case 'clientes':
        return 'Clientes (rol cliente/user), los $limiteVisible más recientes. '
            'Usa «Cargar más» hasta $limiteMaximo.';
      default:
        return 'Todos los roles: $limiteVisible usuarios más recientes en tiempo real. '
            '«Cargar más» hasta $limiteMaximo. Email, teléfono o UID exacto para buscar fuera del lote.';
    }
  }
}
