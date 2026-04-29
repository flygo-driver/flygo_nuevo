import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/cliente_perfil_conductor.dart';

/// Franja visible tipo inDrive: el taxista ve si el pasajero es nuevo, frecuente, fijo o premium.
class ClientePerfilConductorChip extends StatelessWidget {
  const ClientePerfilConductorChip({
    super.key,
    required this.uidCliente,
    this.compacto = false,
  });

  final String uidCliente;

  /// En listas del pool: una fila más baja. En detalle / viaje en curso: franja completa.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final String uid = uidCliente.trim();
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final ClientePerfilConductorVista p =
            ClientePerfilConductorVista.fromUsuarioDoc(
          snap.hasData ? snap.data! : null,
        );
        final Color ac = p.colorAcento;

        if (compacto) {
          return _franjaCompacta(p, ac);
        }
        return _franjaCompleta(p, ac);
      },
    );
  }

  static const Color _onLightText = Colors.white;

  Widget _franjaCompacta(
    ClientePerfilConductorVista p,
    Color ac,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ac.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ac.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ac.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(p.iconoNivel, color: ac, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.tituloPerfil.toUpperCase(),
                  style: TextStyle(
                    color: ac,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.lineaViajes,
                  style: TextStyle(
                    color: _onLightText.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (p.esPremium)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _pillPremium(ac),
            ),
        ],
      ),
    );
  }

  Widget _franjaCompleta(
    ClientePerfilConductorVista p,
    Color ac,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ac.withValues(alpha: 0.22),
            ac.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: ac.withValues(alpha: 0.5), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: ac.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ac.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(p.iconoNivel, color: ac, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERFIL DEL PASAJERO',
                      style: TextStyle(
                        color: _onLightText.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.tituloPerfil,
                      style: const TextStyle(
                        color: _onLightText,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.lineaViajes,
                      style: TextStyle(
                        color: _onLightText.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (p.esPremium) _pillPremium(ac),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            p.detalleConductor,
            style: TextStyle(
              color: _onLightText.withValues(alpha: 0.72),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillPremium(Color ac) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ac.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ac, width: 1),
      ),
      child: Text(
        'PREMIUM',
        style: TextStyle(
          color: ac,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
