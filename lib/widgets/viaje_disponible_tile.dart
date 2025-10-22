import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class ViajeDisponibleTile extends StatelessWidget {
  const ViajeDisponibleTile({
    super.key,
    required this.viajeId,
    required this.uidTaxista,
    required this.tieneViajeActivo, // pásalo desde tu estado actual (true/false)
    required this.onAceptar,        // tu aceptar original (cuando NO hay viaje activo)
    this.db,                        // opcional; no se usa aquí
  });

  final String viajeId;
  final String uidTaxista;
  final bool tieneViajeActivo;
  final Future<void> Function()? onAceptar;

  // ignore: unused_field
  final FirebaseFirestore? db; // mantenemos la firma para no romper llamadas existentes

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('Viaje $viajeId'),
      subtitle: Text(tieneViajeActivo ? 'Reserva como siguiente' : 'Disponible'),
      trailing: ElevatedButton(
        onPressed: () async {
          try {
            if (tieneViajeActivo) {
              // ✅ Llamada estática al repo
              await ViajesRepo.reservarComoSiguiente(
                viajeId: viajeId,
                uidTaxista: uidTaxista,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reservado como siguiente ✅')),
              );
            } else {
              if (onAceptar != null) {
                await onAceptar!.call(); // tu lógica actual
              }
            }
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo reservar: $e')),
            );
          }
        },
        child: Text(tieneViajeActivo ? 'Reservar como siguiente' : 'Aceptar'),
      ),
    );
  }
}
