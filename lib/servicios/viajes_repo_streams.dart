import 'package:cloud_firestore/cloud_firestore.dart';

class ViajesRepoStreams {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('viajes');

  // -------- CLIENTE: MIS VIAJES --------
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamViajesAhora(
    String uidCliente, {
    int umbralMin = 10,
  }) {
    final limite = DateTime.now().add(Duration(minutes: umbralMin));
    return _col
        .where('uidCliente', isEqualTo: uidCliente)
        .where('estado', whereIn: [
          'pendiente',
          'aceptado',
          'en_camino_pickup',
          'a_bordo',
          'en_curso',
        ])
        .where('fechaHora', isLessThanOrEqualTo: Timestamp.fromDate(limite))
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamViajesProgramados(
    String uidCliente, {
    int umbralMin = 10,
  }) {
    final limite = DateTime.now().add(Duration(minutes: umbralMin));
    return _col
        .where('uidCliente', isEqualTo: uidCliente)
        .where('estado', isEqualTo: 'pendiente')
        .where('fechaHora', isGreaterThan: Timestamp.fromDate(limite))
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  // -------- TAXISTA: DISPONIBLES GLOBALES --------
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamDisponiblesAhora({
    int umbralMin = 10,
  }) {
    final limite = DateTime.now().add(Duration(minutes: umbralMin));
    return _col
        .where('estado', isEqualTo: 'pendiente')
        .where('fechaHora', isLessThanOrEqualTo: Timestamp.fromDate(limite))
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamDisponiblesProgramados({
    int umbralMin = 10,
  }) {
    final limite = DateTime.now().add(Duration(minutes: umbralMin));
    return _col
        .where('estado', isEqualTo: 'pendiente')
        .where('fechaHora', isGreaterThan: Timestamp.fromDate(limite))
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }
}
