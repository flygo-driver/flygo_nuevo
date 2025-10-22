import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class PromocionReservaService {
  const PromocionReservaService();

  /// Devuelve el id del viaje promovido a "aceptado",
  /// o null si no había reserva válida.
  Future<String?> promoverSiExiste({required String uidTaxista}) {
    // ✅ Llamada estática al repo
    return ViajesRepo.promoverReservaAlCompletar(uidTaxista: uidTaxista);
  }
}
