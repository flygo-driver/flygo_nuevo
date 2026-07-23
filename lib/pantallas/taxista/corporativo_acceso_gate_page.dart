import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/pantallas/taxista/login_chofer_corporativo.dart';
import 'package:flygo_nuevo/servicios/solicitud_corporativo_repo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Pantalla premium de acceso corporativo (antes de aprobación ADM).
class CorporativoAccesoGatePage extends StatelessWidget {
  const CorporativoAccesoGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: RaiDsColors.bg,
      appBar: const RaiAppBar(
        title: 'Corporativo',
        showBackWhenCanPop: true,
      ),
      body: uid == null
          ? const Center(child: Text('Inicia sesión'))
          : StreamBuilder<EstadoRegistroCorporativo>(
              stream: SolicitudCorporativoRepo.streamEstadoRegistro(uid),
              builder: (context, estadoSnap) {
                final reg = estadoSnap.data;
                final aprobado = reg?.fase == 'aprobado';
                final pendiente = reg?.fase == 'pendiente_adm';

                return _GateBody(
                  pendiente: pendiente,
                  aprobado: aprobado,
                  onPrimary: () {
                    if (aprobado) {
                      Navigator.pop(context);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginChoferCorporativo(),
                      ),
                    );
                  },
                  primaryLabel: aprobado
                      ? 'Volver'
                      : (pendiente ? 'Ver solicitud' : 'Solicitar acceso'),
                );
              },
            ),
    );
  }
}

class _GateBody extends StatelessWidget {
  const _GateBody({
    required this.pendiente,
    required this.aprobado,
    required this.onPrimary,
    required this.primaryLabel,
  });

  final bool pendiente;
  final bool aprobado;
  final VoidCallback onPrimary;
  final String primaryLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  RaiDsColors.blue.withValues(alpha: 0.28),
                  RaiDsColors.bg,
                ],
              ),
              border: Border.all(
                color: RaiDsColors.blue.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: RaiDsColors.blue.withValues(alpha: 0.22),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              PhosphorIconsFill.buildings,
              size: 52,
              color: RaiDsColors.blue,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          aprobado ? 'Acceso habilitado' : 'Acceso no habilitado',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          aprobado
              ? 'Tu perfil corporativo está activo. RAI te asignará rutas de empresas.'
              : 'Operá rutas fijas para empresas con RAI Driver. '
                  'Completá tu solicitud y administración revisará tu perfil.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: RaiDsColors.textMuted,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        if (pendiente && !aprobado) ...[
          const SizedBox(height: 24),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsFill.hourglass,
                  color: RaiDsColors.blue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solicitud en revisión',
                        style: TextStyle(
                          color: RaiDsColors.blue,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'RAI revisará tu perfil de taxista. Te avisaremos cuando esté listo.',
                        style: RaiDsTypography.caption(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        AppButton(
          label: primaryLabel,
          icon: pendiente
              ? PhosphorIconsRegular.eye
              : PhosphorIconsRegular.arrowRight,
          onPressed: onPrimary,
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIconsRegular.briefcase,
                color: RaiDsColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Las rutas corporativas son asignadas manualmente por RAI. '
                  'No aparecen en el pool público de viajes.',
                  style: RaiDsTypography.caption(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
