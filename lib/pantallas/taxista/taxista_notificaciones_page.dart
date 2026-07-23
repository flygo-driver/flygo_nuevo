import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Bandeja de notificaciones (UI). Los avisos operativos siguen llegando por push.
class TaxistaNotificacionesPage extends StatelessWidget {
  const TaxistaNotificacionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: RaiDsColors.bg,
        appBar: RaiAppBar(
          title: 'Notificaciones',
          showBackWhenCanPop: true,
          bottom: TabBar(
            indicatorColor: RaiDsColors.neon,
            labelColor: RaiDsColors.neon,
            unselectedLabelColor: RaiDsColors.textMuted,
            tabs: const [
              Tab(text: 'Viajes'),
              Tab(text: 'Pagos'),
              Tab(text: 'Sistema'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NotifEmptyPanel(
              icon: PhosphorIconsFill.car,
              title: 'Sin avisos de viajes',
              message:
                  'Cuando haya ofertas, cambios de estado o mensajes de un viaje, '
                  'aparecerán aquí. También recibirás alertas push en el teléfono.',
            ),
            _NotifEmptyPanel(
              icon: PhosphorIconsFill.wallet,
              title: 'Sin avisos de pagos',
              message:
                  'Recargas, comisiones y liquidaciones aprobadas se mostrarán en esta sección.',
            ),
            _NotifEmptyPanel(
              icon: PhosphorIconsFill.bell,
              title: 'Todo al día',
              message:
                  'Avisos de documentos, aprobaciones de servicios y novedades de RAI '
                  'aparecerán aquí cuando correspondan.',
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifEmptyPanel extends StatelessWidget {
  const _NotifEmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RaiDsColors.card,
              border: Border.all(color: RaiDsColors.border),
              boxShadow: [
                BoxShadow(
                  color: RaiDsColors.neon.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, size: 40, color: RaiDsColors.neon),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: RaiDsColors.textMuted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                PhosphorIconsRegular.info,
                color: RaiDsColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Las notificaciones urgentes (nuevo viaje, timbre) siguen activas '
                  'aunque esta bandeja esté vacía.',
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
