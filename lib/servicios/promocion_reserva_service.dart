import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class PromocionReservaService {
  const PromocionReservaService();

  /// Devuelve el id del viaje promovido a "aceptado",
  /// o null si no había cola válida (reserva formal o encolado legado).
  Future<String?> promoverSiExiste({required String uidTaxista}) {
    return ViajesRepo.promoverColaTrasFinalizarTaxista(uidTaxista: uidTaxista);
  }
}
