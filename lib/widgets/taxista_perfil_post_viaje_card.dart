import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/taxista_perfil_cliente.dart';

/// Tarjeta del conductor en post-viaje (estilo apps grandes: foto, estrellas, premium).
class TaxistaPerfilPostViajeCard extends StatelessWidget {
  const TaxistaPerfilPostViajeCard({
    super.key,
    required this.uidTaxista,
    this.nombreFallback = '',
    this.viajeData,
    this.fondoOscuro = true,
  });

  final String uidTaxista;
  final String nombreFallback;
  final Map<String, dynamic>? viajeData;
  final bool fondoOscuro;

  @override
  Widget build(BuildContext context) {
    final String uid = uidTaxista.trim();
    if (uid.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final Map<String, dynamic> u =
            (snap.data?.data() ?? <String, dynamic>{});
        final TaxistaPerfilCliente p = TaxistaPerfilCliente.fromMaps(
          usuario: u,
          viaje: viajeData,
          nombreFallback: nombreFallback,
        );

        final Color fg = fondoOscuro ? Colors.white : Colors.black87;
        final Color muted =
            fondoOscuro ? Colors.white60 : Colors.black54;
        final Color cardBg =
            fondoOscuro ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: fondoOscuro ? Colors.white12 : Colors.black12,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: fondoOscuro ? Colors.white12 : Colors.black12,
                backgroundImage: p.fotoUrl.isNotEmpty
                    ? NetworkImage(p.fotoUrl)
                    : null,
                child: p.fotoUrl.isEmpty
                    ? Icon(Icons.person, color: muted, size: 28)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          p.nombre,
                          style: TextStyle(
                            color: fg,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (p.esPremium) _pillPremium(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _filaEstrellas(p, muted),
                    if (p.tipoVehiculo.isNotEmpty || p.placa.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (p.tipoVehiculo.isNotEmpty) p.tipoVehiculo,
                          if (p.placa.isNotEmpty) 'Placa ${p.placa}',
                        ].join(' · '),
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pillPremium() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 14, color: Colors.black87),
          SizedBox(width: 4),
          Text(
            'Premium',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaEstrellas(TaxistaPerfilCliente p, Color muted) {
    final double avg = p.promedioEstrellas;
    final int llenas = avg.round().clamp(0, 5);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        ...List.generate(5, (i) {
          return Icon(
            i < llenas ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
            color: Colors.amber,
          );
        }),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            avg > 0
                ? '${avg.toStringAsFixed(1)} (${p.totalCalificaciones})'
                : 'Conductor nuevo en RAI',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
