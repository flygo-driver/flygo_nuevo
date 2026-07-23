import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';
import 'package:flygo_nuevo/widgets/taxista_inicio_header.dart';

/// Inicio del conductor: saldo + tres accesos principales (sin pool mezclado).
class TaxistaInicioDashboard extends StatelessWidget {
  const TaxistaInicioDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: context.raiBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = context.isRaiDark;

    return Scaffold(
      backgroundColor: context.raiBg,
      appBar: AppBar(
        backgroundColor: context.raiBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const RaiDriverBrandMark(),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: ListView(
          key: const ValueKey<String>('taxista-inicio'),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
          children: [
            TaxistaInicioHeader(uid: user.uid),
            const SizedBox(height: 8),
            AppBalanceCard(uidTaxista: user.uid),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '¿Qué querés hacer?',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.raiTextSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppHeroAccessCard(
                heroTag: 'hero-viajes-ahora',
                title: 'Viajes Ahora',
                subtitle: 'Ofertas inmediatas en tu zona',
                icon: Icons.local_taxi_rounded,
                accent: RaiDsColors.neon,
                showVehicleGlyph: true,
                onTap: () => ShellTabController.taxistaIrAViajesAhora(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: AppHeroAccessCard(
                heroTag: 'hero-viajes-programados',
                title: 'Programados',
                subtitle: 'Viajes con hora y fecha confirmada',
                icon: Icons.event_rounded,
                accent: RaiDsColors.purple,
                onTap: () => ShellTabController.taxistaIrAViajesProgramados(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: AppHeroAccessCard(
                heroTag: 'hero-servicios',
                title: 'Servicios',
                subtitle: 'Pool, turismo, corporativo y más',
                icon: Icons.grid_view_rounded,
                accent: isDark ? RaiDsColors.gold : const Color(0xFFD97706),
                onTap: ShellTabController.taxistaIrAServicios,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
