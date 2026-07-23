import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/pantallas/taxista/login_chofer_turismo.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Pantalla premium de acceso a turismo (antes de aprobación ADM).
class TurismoAccesoGatePage extends StatelessWidget {
  const TurismoAccesoGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: RaiDsColors.bg,
      appBar: const RaiAppBar(
        title: 'Turismo',
        showBackWhenCanPop: true,
      ),
      body: uid == null
          ? const Center(child: Text('Inicia sesión'))
          : StreamBuilder<EstadoRegistroTurismo>(
              stream: SolicitudTurismoRepo.streamEstadoRegistro(uid),
              builder: (context, estadoSnap) {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('choferes_turismo')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, choferSnap) {
                    final data = choferSnap.data?.data();
                    final estado =
                        (data?['estado'] ?? '').toString().trim().toLowerCase();
                    final aprobado =
                        estado == 'aprobado' || estado == 'activo';
                    final pendiente =
                        estadoSnap.data?.fase == 'pendiente_adm';

                    if (aprobado) {
                      return _GateBody(
                        pendiente: false,
                        aprobado: true,
                        onPrimary: () => Navigator.pop(context),
                        primaryLabel: 'Volver',
                      );
                    }

                    return _GateBody(
                      pendiente: pendiente,
                      aprobado: false,
                      onPrimary: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginChoferTurismo(),
                          ),
                        );
                      },
                      primaryLabel:
                          pendiente ? 'Ver solicitud' : 'Solicitar acceso',
                    );
                  },
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
                  RaiDsColors.orange.withValues(alpha: 0.28),
                  RaiDsColors.bg,
                ],
              ),
              border: Border.all(
                color: RaiDsColors.orange.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: RaiDsColors.orange.withValues(alpha: 0.22),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              PhosphorIconsFill.suitcase,
              size: 52,
              color: RaiDsColors.orange,
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
              ? 'Tu perfil turístico ya está activo. Podés operar desde Servicios.'
              : 'Operá viajes turísticos con RAI Driver. '
                  'Completá tu solicitud y el equipo de administración revisará tu vehículo y documentos.',
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
                  color: RaiDsColors.orange,
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
                          color: RaiDsColors.orange,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Administración revisará tu vehículo y documentos. Te avisaremos cuando esté listo.',
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
                PhosphorIconsRegular.shieldCheck,
                color: RaiDsColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Requisitos: licencia vigente, seguro del vehículo y fotos del mismo. '
                  'Solo conductores aprobados ven el pool turístico.',
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
