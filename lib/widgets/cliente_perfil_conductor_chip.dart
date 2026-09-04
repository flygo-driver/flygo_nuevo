import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/cliente_perfil_conductor.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

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

  static Color _tituloColor(Color ac, bool isDark) {
    if (isDark) return ac;
    return Color.lerp(ac, const Color(0xFF101828), 0.42)!;
  }

  static Color _textoSecundario(bool isDark) {
    return isDark
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFF344054);
  }

  static Color _textoPrincipal(bool isDark) {
    return isDark ? Colors.white : const Color(0xFF101828);
  }

  static Color _textoEtiqueta(bool isDark) {
    return isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF667085);
  }

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
        final Map<String, dynamic> userData =
            snap.data?.data() ?? <String, dynamic>{};
        final estadoSelfie =
            ClienteVerificacionIdentidadService.estadoDesde(userData);
        final Color ac = p.colorAcento;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;

        if (compacto) {
          return _franjaCompacta(context, p, ac, isDark, estadoSelfie);
        }
        return _franjaCompleta(context, p, ac, isDark, estadoSelfie);
      },
    );
  }

  Widget _franjaCompacta(
    BuildContext context,
    ClientePerfilConductorVista p,
    Color ac,
    bool isDark,
    ClienteVerificacionIdentidadEstado estadoSelfie,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: ac.withValues(alpha: isDark ? 0.14 : 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ac.withValues(alpha: isDark ? 0.55 : 0.38),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ac.withValues(alpha: isDark ? 0.22 : 0.16),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(p.iconoNivel, color: _tituloColor(ac, isDark), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.tituloPerfil.toUpperCase(),
                      style: TextStyle(
                        color: _tituloColor(ac, isDark),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.lineaViajes,
                      style: TextStyle(
                        color: _textoSecundario(isDark),
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
                  child: _pillPremium(ac, isDark),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _badgeSelfie(estadoSelfie, isDark),
      ],
    );
  }

  Widget _franjaCompleta(
    BuildContext context,
    ClientePerfilConductorVista p,
    Color ac,
    bool isDark,
    ClienteVerificacionIdentidadEstado estadoSelfie,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ac.withValues(alpha: isDark ? 0.22 : 0.14),
                ac.withValues(alpha: isDark ? 0.06 : 0.04),
              ],
            ),
            border: Border.all(
              color: ac.withValues(alpha: isDark ? 0.5 : 0.35),
              width: 1.4,
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: ac.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
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
                      color: ac.withValues(alpha: isDark ? 0.25 : 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      p.iconoNivel,
                      color: _tituloColor(ac, isDark),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PERFIL DEL PASAJERO',
                          style: TextStyle(
                            color: _textoEtiqueta(isDark),
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.tituloPerfil,
                          style: TextStyle(
                            color: _textoPrincipal(isDark),
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.lineaViajes,
                          style: TextStyle(
                            color: _textoSecundario(isDark),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p.esPremium) _pillPremium(ac, isDark),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                p.detalleConductor,
                style: TextStyle(
                  color: _textoSecundario(isDark).withValues(alpha: 0.92),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _badgeSelfie(estadoSelfie, isDark),
      ],
    );
  }

  Widget _badgeSelfie(
    ClienteVerificacionIdentidadEstado estado, bool isDark,
  ) {
    if (estado == ClienteVerificacionIdentidadEstado.noAplica) {
      return const SizedBox.shrink();
    }
    final color = ClienteVerificacionIdentidadService.colorEstado(
      estado,
      isDark: isDark,
    );
    final String detalle = switch (estado) {
      ClienteVerificacionIdentidadEstado.vigente =>
        'Confirmó identidad con selfie reciente en RAI.',
      ClienteVerificacionIdentidadEstado.porRevisar =>
        'Envió su selfie; RAI todavía la está revisando.',
      ClienteVerificacionIdentidadEstado.vencida =>
        'La confirmación con selfie está vencida o pendiente.',
      ClienteVerificacionIdentidadEstado.rechazada =>
        'RAI rechazó su última selfie; debe enviar otra.',
      ClienteVerificacionIdentidadEstado.sinSelfie =>
        'Aún no ha enviado selfie de confirmación en RAI.',
      ClienteVerificacionIdentidadEstado.noAplica => '',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            estado == ClienteVerificacionIdentidadEstado.vigente
                ? Icons.verified_user_outlined
                : Icons.face_retouching_natural_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ClienteVerificacionIdentidadService.etiquetaEstado(estado),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: TextStyle(
                      color: _textoSecundario(isDark),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillPremium(Color ac, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ac.withValues(alpha: isDark ? 0.35 : 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ac.withValues(alpha: isDark ? 1 : 0.55),
          width: 1,
        ),
      ),
      child: Text(
        'PREMIUM',
        style: TextStyle(
          color: _tituloColor(ac, isDark),
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
